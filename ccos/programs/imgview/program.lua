-- CCOS Program: Image Viewer v4
-- View .nfp (32-color) and .nfp256 (256-color hex) files
-- Supports drag-pan, zoom, and shows errors via API
local D = _G._desktop
local R = _G.ccos_render
local API = _G.ccos_api
local P = R.PAL

-- 32-color NFP text mapping
local NFP32_MAP = {
    ['0'] = 1,  ['1'] = 2,  ['2'] = 3,  ['3'] = 4,
    ['4'] = 5,  ['5'] = 6,  ['6'] = 7,  ['7'] = 8,
    ['8'] = 9,  ['9'] = 10, ['a'] = 11, ['b'] = 12,
    ['c'] = 13, ['d'] = 14, ['e'] = 15, ['f'] = 16,
    ['g'] = 17, ['h'] = 18, ['i'] = 19, ['j'] = 20,
    ['k'] = 21, ['l'] = 22, ['m'] = 23, ['n'] = 24,
    ['o'] = 25, ['p'] = 26, ['q'] = 27, ['r'] = 28,
    ['s'] = 29, ['t'] = 30, ['u'] = 31, ['v'] = 32,
}

local function isNfp256(line)
    -- .nfp256 has only hex chars and line length is even
    if #line % 2 ~= 0 then return false end
    for i = 1, #line do
        local c = line:sub(i,i)
        if not c:match("[0-9a-fA-F]") then return false end
    end
    return #line >= 4
end

local function parseNfp256(line)
    local row = {}
    for i = 1, #line, 2 do
        local hex = line:sub(i, i+1)
        local val = tonumber(hex, 16) or 0
        table.insert(row, val)
    end
    return row
end

local function parseNfp32(line)
    local row = {}
    for i = 1, #line do
        local ch = line:sub(i,i)
        table.insert(row, NFP32_MAP[ch] or 0)
    end
    return row
end

local function appImageViewer(fp)
    fp = fp or "/image.nfp"
    local pixels = {}
    local imgW, imgH = 0, 0
    local status = "No image"
    local formatName = ""

    local scale = 1
    local ox, oy = 0, 0
    local isPanning = false
    local panSX, panSY = 0, 0
    local panOX, panOY = 0, 0

    local function loadImage()
        pixels = {}
        imgW, imgH = 0, 0
        status = "Loading..."
        formatName = ""

        if not fs.exists(fp) then
            status = "Not found"
            API.showError("Image Viewer", "File not found: " .. fp)
            return
        end

        local f, err = fs.open(fp, "r")
        if not f then
            status = "Open error"
            API.showError("Image Viewer", "Cannot open: " .. tostring(err))
            return
        end

        -- Determine format by extension first, then by content
        local ext = fp:match("%.([^%.]+)$") or ""
        local is256 = (ext == "nfp256")
        local is32  = (ext == "nfp")
        local first = true

        while true do
            local line = f.readLine()
            if not line then break end

            if first then
                if not is256 and not is32 then
                    -- Fallback heuristic only when extension unclear
                    is256 = isNfp256(line)
                end
                formatName = is256 and "256-color" or "32-color"
                first = false
            end

            local row = is256 and parseNfp256(line) or parseNfp32(line)
            if #row > 0 then
                table.insert(pixels, row)
                imgW = math.max(imgW, #row)
                imgH = imgH + 1
            end
        end
        f.close()

        if imgH == 0 then
            status = "Empty/invalid"
            API.showError("Image Viewer", "File is empty or invalid: " .. fp)
        else
            status = imgW .. "x" .. imgH .. " " .. formatName
        end
        ox, oy = 0, 0
    end

    loadImage()

    local wx, wy, ww, wh = D.fitWin(220, 170)
    local w = D.createWindow("Image: " .. API.getFileName(fp), wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        -- Toolbar
        R.drawButton(cx,cy,40,14,false)
        R.drawText(cx+4,cy+3,"Open",P.BLACK,P.GRAY)
        R.drawButton(cx+44,cy,28,14,false)
        R.drawText(cx+48,cy+3,"+",P.BLACK,P.GRAY)
        R.drawButton(cx+74,cy,28,14,false)
        R.drawText(cx+78,cy+3,"-",P.BLACK,P.GRAY)
        R.drawText(cx+110,cy+3,status,P.DARK_BLUE,P.GRAY)

        local viewX, viewY = cx+2, cy+28
        local viewW, viewH = cw-4, ch-40

        if #pixels == 0 then
            R.drawText(viewX+4, viewY+4, "No image.", P.BLACK, P.GRAY)
            R.drawText(viewX+4, viewY+16, "Click Open or drag .nfp/.nfp256", P.DARK_GRAY, P.GRAY)
            return
        end

        -- Pan bounds
        local maxOX = math.max(0, imgW - math.floor(viewW/scale))
        local maxOY = math.max(0, imgH - math.floor(viewH/scale))
        ox = math.max(0, math.min(ox, maxOX))
        oy = math.max(0, math.min(oy, maxOY))

        -- Viewport
        local maxY = math.min(imgH, math.floor(viewH/scale))
        local maxX = math.min(imgW, math.floor(viewW/scale))
        for y = 1, maxY do
            local row = pixels[y + oy]
            if row then
                for x = 1, maxX do
                    local color = row[x + ox] or 0
                    R.fillRect(viewX + (x-1)*scale, viewY + (y-1)*scale, scale, scale, color)
                end
            end
        end
    end

    w.onClick = function(_,mx,my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 40 then
                D.inputDialog("Open Image", "Path:", fp, function(path)
                    if path then fp = path; loadImage(); D.markContentDirty(w) end
                end)
            elseif mx >= 44 and mx < 72 then
                scale = math.min(8, scale + 1)
                D.markContentDirty(w)
            elseif mx >= 74 and mx < 102 then
                scale = math.max(1, scale - 1)
                D.markContentDirty(w)
            end
        end
    end

    w.onDrag = function(_, dx, dy)
        local step = math.max(1, math.floor(2 / scale))
        if dx > 0 then ox = math.max(0, ox - step)
        elseif dx < 0 then ox = ox + step end
        if dy > 0 then oy = math.max(0, oy - step)
        elseif dy < 0 then oy = oy + step end
        D.markContentDirty(w)
    end

    w.onKey = function(_,k)
        local step = math.max(1, math.floor(4 / scale))
        if k == keys.left then  ox = math.max(0, ox - step); D.markContentDirty(w)
        elseif k == keys.right then ox = ox + step; D.markContentDirty(w)
        elseif k == keys.up then oy = math.max(0, oy - step); D.markContentDirty(w)
        elseif k == keys.down then oy = oy + step; D.markContentDirty(w)
        end
    end
end

return {name = "Image View", icon = "img", run = appImageViewer}
