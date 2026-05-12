-- CCOS Program: Image Viewer
-- View .nfp (NPaintPro) and pixel art files
-- Supports: CC 16-color (0-f) and CCOS 32-color (0-v)
local D = _G._desktop
local R = _G.ccos_render
local P = R.PAL

-- Standard CC 16-color paintutils mapping
local CC16_MAP = {
    ['0'] = P.WHITE,
    ['1'] = P.ORANGE,
    ['2'] = P.MAGENTA,
    ['3'] = P.LIGHT_BLUE,
    ['4'] = P.YELLOW,
    ['5'] = P.LIME,
    ['6'] = P.PINK,
    ['7'] = P.GRAY,
    ['8'] = P.LIGHT_GRAY,
    ['9'] = P.CYAN,
    ['a'] = P.PURPLE,
    ['b'] = P.BLUE,
    ['c'] = P.BROWN,
    ['d'] = P.GREEN,
    ['e'] = P.RED,
    ['f'] = P.BLACK,
}

-- CCOS 32-color extended mapping (matches convert_to_nfp.py --ccos)
local CCOS32_MAP = {
    ['0'] = P.BLACK,
    ['1'] = P.WHITE,
    ['2'] = P.GRAY,
    ['3'] = P.LIGHT_GRAY,
    ['4'] = P.DARK_GRAY,
    ['5'] = P.BLUE,
    ['6'] = P.DARK_BLUE,
    ['7'] = P.CYAN,
    ['8'] = P.LIGHT_BLUE,
    ['9'] = P.GREEN,
    ['a'] = P.DARK_GREEN,
    ['b'] = P.RED,
    ['c'] = P.DARK_RED,
    ['d'] = P.YELLOW,
    ['e'] = P.ORANGE,
    ['f'] = P.BROWN,
    ['g'] = P.PURPLE,
    ['h'] = P.PINK,
    ['i'] = P.DARK_TITLE,
    ['j'] = P.W95_TITLE_BLUE,
    ['k'] = P.W95_TITLE_INACTIVE,
    ['l'] = P.PURE_BLUE,
    ['m'] = P.ALMOST_WHITE,
    ['n'] = P.NEAR_BLACK,
    ['o'] = P.MID_GRAY,
    ['p'] = P.BUTTON_FACE,
    ['q'] = P.BUTTON_HI,
    ['r'] = P.DEEP_NAVY,
    ['s'] = P.BTNFACE_DARK,
    ['t'] = P.DARK_GREEN_BG,
    ['u'] = P.W95_DESKTOP,
    ['v'] = P.LIGHT_BG,
}

local function detectFormat(content)
    for i = 1, #content do
        local ch = content:sub(i,i)
        if ch > 'f' and ch <= 'v' then
            return CCOS32_MAP, "CCOS 32-color"
        end
    end
    return CC16_MAP, "CC 16-color"
end

local function appImageViewer(fp)
    fp = fp or "/image.nfp"
    local pixels = {}
    local imgW, imgH = 0, 0
    local formatName = "Unknown"

    local function loadImage()
        if not fs.exists(fp) then return end
        local f = fs.open(fp, "r")
        if not f then return end
        local content = ""
        while true do
            local line = f.readLine()
            if not line then break end
            content = content .. line
        end
        f.close()

        local colorMap, fmtName = detectFormat(content)
        formatName = fmtName
        pixels = {}
        imgW, imgH = 0, 0

        f = fs.open(fp, "r")
        while true do
            local line = f.readLine()
            if not line then break end
            local row = {}
            for x = 1, #line do
                local ch = line:sub(x,x)
                table.insert(row, colorMap[ch] or P.BLACK)
            end
            table.insert(pixels, row)
            imgW = math.max(imgW, #row)
            imgH = imgH + 1
        end
        f.close()
    end

    loadImage()

    local scale = 1
    local ox, oy = 0, 0

    local wx, wy, ww, wh = D.fitWin(200, 160)
    local w = D.createWindow("Image: " .. fp, wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,36,14,false)
        R.drawText(cx+2,cy+3,"Open",P.BLACK,P.GRAY)
        R.drawButton(cx+42,cy,36,14,false)
        R.drawText(cx+46,cy+3,"+",P.BLACK,P.GRAY)
        R.drawButton(cx+80,cy,36,14,false)
        R.drawText(cx+84,cy+3,"-",P.BLACK,P.GRAY)
        R.drawText(cx+120,cy+3,imgW.."x"..imgH.." @"..scale.."x",P.BLACK,P.GRAY)
        R.drawText(cx+120,cy+11,formatName,P.DBLUE,P.GRAY)

        local viewX, viewY = cx+2, cy+28
        local viewW, viewH = cw-4, ch-40

        if #pixels == 0 then
            R.drawText(viewX+10, viewY+10, "No image loaded", P.BLACK, P.GRAY)
            return
        end

        for y = 1, math.min(imgH, math.floor(viewH/scale)) do
            for x = 1, math.min(imgW, math.floor(viewW/scale)) do
                local row = pixels[y + oy]
                if row then
                    local color = row[x + ox] or P.BLACK
                    R.fillRect(viewX + (x-1)*scale, viewY + (y-1)*scale, scale, scale, color)
                end
            end
        end
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 then
            if mx>=0 and mx<36 then
                D.inputDialog("Open Image", "Enter path:", "/image.nfp", function(path)
                    if path then fp=path; pixels={}; imgW=0; imgH=0; loadImage(); D.markContentDirty(w) end
                end)
            elseif mx>=42 and mx<78 then scale=math.min(4,scale+1); D.markContentDirty(w)
            elseif mx>=80 and mx<116 then scale=math.max(1,scale-1); D.markContentDirty(w) end
        end
    end

    w.onKey = function(_,k)
        -- Image Viewer is view-only; close only via X button
    end
end

return {name = "Image View", icon = "img", run = appImageViewer}
