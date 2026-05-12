-- CCOS Program: Image Viewer v3
-- View .nfp (NPaintPro) and pixel art files
-- Supports: CC 16-color (0-f) and CCOS 32-color (0-v)
local D = _G._desktop
local R = _G.ccos_render
local P = R.PAL

-- Standard CC 16-color paintutils mapping
local CC16_MAP = {
    ['0'] = P.WHITE,      ['1'] = P.ORANGE,     ['2'] = P.MAGENTA,
    ['3'] = P.LIGHT_BLUE, ['4'] = P.YELLOW,     ['5'] = P.LIME,
    ['6'] = P.PINK,       ['7'] = P.GRAY,       ['8'] = P.LIGHT_GRAY,
    ['9'] = P.CYAN,       ['a'] = P.PURPLE,     ['b'] = P.BLUE,
    ['c'] = P.BROWN,      ['d'] = P.GREEN,      ['e'] = P.RED,
    ['f'] = P.BLACK,
}

-- CCOS 32-color extended mapping
local CCOS32_MAP = {
    ['0'] = P.BLACK,      ['1'] = P.WHITE,      ['2'] = P.GRAY,
    ['3'] = P.LIGHT_GRAY, ['4'] = P.DARK_GRAY,  ['5'] = P.BLUE,
    ['6'] = P.DARK_BLUE,  ['7'] = P.CYAN,       ['8'] = P.LIGHT_BLUE,
    ['9'] = P.GREEN,      ['a'] = P.DARK_GREEN, ['b'] = P.RED,
    ['c'] = P.DARK_RED,   ['d'] = P.YELLOW,     ['e'] = P.ORANGE,
    ['f'] = P.BROWN,      ['g'] = P.PURPLE,     ['h'] = P.PINK,
    ['i'] = P.DARK_TITLE, ['j'] = P.W95_TITLE_BLUE, ['k'] = P.W95_TITLE_INACTIVE,
    ['l'] = P.PURE_BLUE,  ['m'] = P.ALMOST_WHITE,   ['n'] = P.NEAR_BLACK,
    ['o'] = P.MID_GRAY,   ['p'] = P.BUTTON_FACE,    ['q'] = P.BUTTON_HI,
    ['r'] = P.DEEP_NAVY,  ['s'] = P.BTNFACE_DARK,   ['t'] = P.DARK_GREEN_BG,
    ['u'] = P.W95_DESKTOP,['v'] = P.LIGHT_BG,
}

local function detectFormat(firstLine)
    for i = 1, #firstLine do
        local ch = firstLine:sub(i,i)
        if ch >= 'g' and ch <= 'v' then
            return CCOS32_MAP, "CCOS32"
        end
    end
    return CC16_MAP, "CC16"
end

local function appImageViewer(fp)
    fp = fp or "/image.nfp"
    local pixels = {}
    local imgW, imgH = 0, 0
    local formatName = ""
    local status = "No image"

    local function loadImage()
        pixels = {}
        imgW, imgH = 0, 0
        formatName = ""

        if not fs.exists(fp) then
            status = "Not found: " .. fp
            return
        end

        local f, err = fs.open(fp, "r")
        if not f then
            status = "Cannot open: " .. tostring(err)
            return
        end

        -- Read first line to detect format
        local firstLine = f.readLine() or ""
        if #firstLine == 0 then
            status = "Empty file"
            f.close()
            return
        end

        local colorMap, fmtName = detectFormat(firstLine)
        formatName = fmtName

        -- Process first line
        local row = {}
        for x = 1, #firstLine do
            local ch = firstLine:sub(x,x)
            table.insert(row, colorMap[ch] or P.BLACK)
        end
        table.insert(pixels, row)
        imgW = #row
        imgH = 1

        -- Process remaining lines
        while true do
            local line = f.readLine()
            if not line then break end
            row = {}
            for x = 1, #line do
                local ch = line:sub(x,x)
                table.insert(row, colorMap[ch] or P.BLACK)
            end
            table.insert(pixels, row)
            imgW = math.max(imgW, #row)
            imgH = imgH + 1
        end
        f.close()

        status = "Loaded " .. imgW .. "x" .. imgH
    end

    loadImage()

    local scale = 1
    local ox, oy = 0, 0

    local wx, wy, ww, wh = D.fitWin(220, 170)
    local w = D.createWindow("Image Viewer", wx, wy, ww, wh)

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
            R.drawText(viewX+4, viewY+4, "No image loaded.", P.BLACK, P.GRAY)
            R.drawText(viewX+4, viewY+16, "Click Open or drop .nfp file.", P.DARK_GRAY, P.GRAY)
            return
        end

        -- Viewport
        local maxY = math.min(imgH, math.floor(viewH/scale))
        local maxX = math.min(imgW, math.floor(viewW/scale))
        for y = 1, maxY do
            local row = pixels[y + oy]
            if row then
                for x = 1, maxX do
                    local color = row[x + ox] or P.BLACK
                    R.fillRect(viewX + (x-1)*scale, viewY + (y-1)*scale, scale, scale, color)
                end
            end
        end
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 then
            if mx>=0 and mx<40 then
                D.inputDialog("Open Image", "Path:", fp, function(path)
                    if path then
                        fp = path
                        loadImage()
                        D.markContentDirty(w)
                    end
                end)
            elseif mx>=44 and mx<72 then
                scale = math.min(8, scale+1)
                D.markContentDirty(w)
            elseif mx>=74 and mx<102 then
                scale = math.max(1, scale-1)
                D.markContentDirty(w)
            end
        end
    end

    w.onKey = function(_,k)
        if k == keys.left and ox > 0 then ox = ox - 1; D.markContentDirty(w)
        elseif k == keys.right and ox < imgW - 10 then ox = ox + 1; D.markContentDirty(w)
        elseif k == keys.up and oy > 0 then oy = oy - 1; D.markContentDirty(w)
        elseif k == keys.down and oy < imgH - 10 then oy = oy + 1; D.markContentDirty(w)
        end
    end
end

return {name = "Image View", icon = "img", run = appImageViewer}
