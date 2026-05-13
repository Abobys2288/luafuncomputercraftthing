-- CCOS Program: Image Viewer
-- Views CCOS .nfp (32-color) and .nfp256 (256-color hex) images.
local API = _G.ccos_api
local D = _G._desktop
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local P = R.PAL

local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,CYAN=7}
local NFP32_KEYS = "0123456789abcdefghijklmnopqrstuv"
local NFP32_MAP = {}
for i = 1, #NFP32_KEYS do
    NFP32_MAP[NFP32_KEYS:sub(i, i)] = i - 1
end

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or text, fg, bg) end
end

local function button(x, y, w, text)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, text, K.BLACK, K.GRAY, w - 8) end
end

local function readLines(path)
    local f, err = fs.open(path, "r")
    if not f then return nil, "Cannot open: " .. tostring(err) end
    local lines = {}
    while true do
        local line = f.readLine()
        if not line then break end
        table.insert(lines, line)
    end
    f.close()
    return lines
end

local function looksNfp256(line)
    if not line or #line < 2 or #line % 2 ~= 0 then return false end
    return line:match("^[0-9a-fA-F]+$") ~= nil
end

local function parseNfp256(line, stats)
    local row = {}
    for i = 1, #line, 2 do
        local val = tonumber(line:sub(i, i + 1), 16)
        if val then row[#row + 1] = val else stats.bad = stats.bad + 1 end
    end
    return row
end

local function parseNfp32(line, stats)
    local row = {}
    for i = 1, #line do
        local ch = line:sub(i, i):lower()
        local val = NFP32_MAP[ch]
        if val ~= nil then
            row[#row + 1] = val
        elseif ch == " " then
            row[#row + 1] = 0
        else
            row[#row + 1] = 0
            stats.bad = stats.bad + 1
        end
    end
    return row
end

local function appImageViewer(initialPath)
    if not API or not R then return end

    local fp = initialPath
    local pixels, imgW, imgH = {}, 0, 0
    local status = "Open an .nfp or .nfp256 file"
    local formatName = ""
    local scale, ox, oy = 1, 0, 0

    local function loadImage(path, quiet)
        pixels, imgW, imgH = {}, 0, 0
        formatName = ""
        ox, oy = 0, 0

        if not path or path == "" then
            fp = nil
            status = "No image selected"
            return false
        end
        fp = path
        if not fs.exists(fp) then
            status = "Not found: " .. fp
            if not quiet then API.showError("Image Viewer", "File not found: " .. fp) end
            return false
        end
        if fs.isDir(fp) then
            status = "Path is a folder"
            if not quiet then API.showError("Image Viewer", "Folder selected: " .. fp) end
            return false
        end

        local lines, err = readLines(fp)
        if not lines then
            status = err
            if not quiet then API.showError("Image Viewer", err) end
            return false
        end

        local ext = (fp:match("%.([^%.]+)$") or ""):lower()
        local is256 = ext == "nfp256"
        if ext ~= "nfp" and ext ~= "nfp256" then
            for _, line in ipairs(lines) do
                if line ~= "" then is256 = looksNfp256(line); break end
            end
        end
        formatName = is256 and "256-color" or "32-color"

        local stats = {bad=0}
        for _, line in ipairs(lines) do
            if line ~= "" then
                local row = is256 and parseNfp256(line, stats) or parseNfp32(line, stats)
                if #row > 0 then
                    pixels[#pixels + 1] = row
                    imgW = math.max(imgW, #row)
                end
            end
        end
        imgH = #pixels

        if imgH == 0 or imgW == 0 then
            status = "Empty or invalid image"
            if not quiet then API.showError("Image Viewer", "No pixels found in: " .. fp) end
            return false
        end

        status = imgW .. "x" .. imgH .. " " .. formatName
        if stats.bad > 0 then status = status .. " (" .. stats.bad .. " bad chars)" end
        return true
    end

    local wx, wy, ww, wh = API.fitWindow(260, 180)
    local win = API.window("Image Viewer", wx, wy, ww, wh)
    if not win then return end

    if fp then
        win.title = "Image: " .. API.getFileName(fp)
        loadImage(fp, true)
    end

    local function maxOffsets(cw, ch)
        local viewW = math.max(1, cw - 4)
        local viewH = math.max(1, ch - 42)
        return math.max(0, imgW - math.floor(viewW / scale)), math.max(0, imgH - math.floor(viewH / scale))
    end

    local function clampPan(cw, ch)
        local maxOX, maxOY = maxOffsets(cw, ch)
        ox = math.max(0, math.min(ox, maxOX))
        oy = math.max(0, math.min(oy, maxOY))
    end

    local function openDialog()
        D.inputDialog("Open Image", "Path:", fp or "/tools/smile.nfp", function(path)
            if path and path ~= "" then
                if loadImage(path, false) then win.title = "Image: " .. API.getFileName(path) end
                API.redrawContent(win)
            end
        end)
    end

    win.onDraw = function(_, cx, cy, cw, ch)
        button(cx, cy, math.min(42, cw), "Open")
        if cw >= 78 then button(cx + 46, cy, 28, "+") end
        if cw >= 110 then button(cx + 78, cy, 28, "-") end
        if cw >= 150 then drawText(cx + 112, cy + 3, status, K.DBLUE, K.GRAY, cw - 116) end

        local viewX, viewY = cx + 2, cy + 24
        local viewW, viewH = math.max(1, cw - 4), math.max(1, ch - 38)
        R.fillRect(viewX, viewY, viewW, viewH, K.BLACK)

        if #pixels == 0 then
            drawText(viewX + 4, viewY + 4, "No image loaded.", K.WHITE, K.BLACK, viewW - 8)
            drawText(viewX + 4, viewY + 16, "Open .nfp/.nfp256", K.LGRAY, K.BLACK, viewW - 8)
            drawText(cx + 4, cy + ch - 10, clip(status, cw - 8), K.DGRAY, K.GRAY)
            return
        end

        clampPan(cw, ch)
        local maxY = math.min(imgH - oy, math.floor(viewH / scale))
        local maxX = math.min(imgW - ox, math.floor(viewW / scale))
        for y = 1, maxY do
            local row = pixels[y + oy]
            if row then
                for x = 1, maxX do
                    local color = row[x + ox]
                    if color ~= nil then
                        R.fillRect(viewX + (x - 1) * scale, viewY + (y - 1) * scale, scale, scale, color)
                    end
                end
            end
        end
        drawText(cx + 4, cy + ch - 10, "Scale " .. scale .. "x  " .. status, K.DGRAY, K.GRAY, cw - 8)
    end

    win.onClick = function(_, mx, my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 42 then openDialog()
            elseif mx >= 46 and mx < 74 then scale = math.min(8, scale + 1); API.redrawContent(win)
            elseif mx >= 78 and mx < 106 then scale = math.max(1, scale - 1); API.redrawContent(win) end
        end
    end

    win.onDrag = function(_, dx, dy)
        if #pixels == 0 then return end
        local step = math.max(1, math.floor(3 / scale))
        if dx > 0 then ox = ox - step elseif dx < 0 then ox = ox + step end
        if dy > 0 then oy = oy - step elseif dy < 0 then oy = oy + step end
        API.redrawContent(win)
    end

    win.onKey = function(_, k, ch)
        local step = math.max(1, math.floor(4 / scale))
        if ch == "o" or ch == "O" then openDialog()
        elseif k == keys.escape then API.close(win)
        elseif k == keys.left then ox = ox - step; API.redrawContent(win)
        elseif k == keys.right then ox = ox + step; API.redrawContent(win)
        elseif k == keys.up then oy = oy - step; API.redrawContent(win)
        elseif k == keys.down then oy = oy + step; API.redrawContent(win)
        elseif k == keys.home then ox, oy = 0, 0; API.redrawContent(win)
        elseif k == keys.pageUp then scale = math.min(8, scale + 1); API.redrawContent(win)
        elseif k == keys.pageDown then scale = math.max(1, scale - 1); API.redrawContent(win)
        end
    end
end

return {name = "Image View", icon = "img", run = appImageViewer}
