-- CCOS Program: Image Viewer
-- View .nfp (NPaintPro) and pixel art files
-- Supports: CC 16-color (0-f) and CCOS 32-color (0-v)
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

-- Standard CC 16-color paintutils mapping
local CC16_MAP = {
    ['0'] = K.WHITE,      -- white
    ['1'] = K.GRAY,       -- orange (closest)
    ['2'] = K.GRAY,       -- magenta (closest)
    ['3'] = K.LIGHT_BLUE, -- lightBlue
    ['4'] = K.YELLOW,     -- yellow
    ['5'] = K.GREEN,      -- lime
    ['6'] = K.PINK,       -- pink
    ['7'] = K.DARK_GRAY,  -- gray
    ['8'] = K.LIGHT_GRAY, -- lightGray
    ['9'] = K.CYAN,       -- cyan
    ['a'] = K.PURPLE,     -- purple
    ['b'] = K.BLUE,       -- blue
    ['c'] = K.BROWN,      -- brown
    ['d'] = K.DARK_GREEN, -- green
    ['e'] = K.RED,        -- red
    ['f'] = K.BLACK,      -- black
}

-- CCOS 32-color extended mapping (matches convert_to_nfp.py --ccos)
local CCOS32_MAP = {
    ['0'] = K.BLACK,
    ['1'] = K.WHITE,
    ['2'] = K.GRAY,
    ['3'] = K.LIGHT_GRAY,
    ['4'] = K.DARK_GRAY,
    ['5'] = K.BLUE,
    ['6'] = K.DARK_BLUE,
    ['7'] = K.CYAN,
    ['8'] = K.LIGHT_BLUE,
    ['9'] = K.GREEN,
    ['a'] = K.DARK_GREEN,
    ['b'] = K.RED,
    ['c'] = K.DARK_RED,
    ['d'] = K.YELLOW,
    ['e'] = K.ORANGE,
    ['f'] = K.BROWN,
    ['g'] = K.PURPLE,
    ['h'] = K.PINK,
    ['i'] = K.DARK_TITLE or K.DARK_GRAY,
    ['j'] = K.W95_TITLE_BLUE or K.BLUE,
    ['k'] = K.W95_TITLE_INACTIVE or K.LIGHT_GRAY,
    ['l'] = K.PURE_BLUE or K.BLUE,
    ['m'] = K.ALMOST_WHITE or K.WHITE,
    ['n'] = K.NEAR_BLACK or K.BLACK,
    ['o'] = K.MID_GRAY or K.GRAY,
    ['p'] = K.BUTTON_FACE or K.GRAY,
    ['q'] = K.BUTTON_HI or K.LIGHT_GRAY,
    ['r'] = K.DEEP_NAVY or K.DARK_BLUE,
    ['s'] = K.BTNFACE_DARK or K.DARK_GRAY,
    ['t'] = K.DARK_GREEN_BG or K.DARK_GREEN,
    ['u'] = K.W95_DESKTOP or K.CYAN,
    ['v'] = K.LIGHT_BG or K.GRAY,
}

local function detectFormat(content)
    -- If content contains chars > 'f', it's CCOS 32-color
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
                table.insert(row, colorMap[ch] or K.BLACK)
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
        R.drawText(cx+2,cy+3,"Open",K.BLACK,K.GRAY)
        R.drawButton(cx+42,cy,36,14,false)
        R.drawText(cx+46,cy+3,"+",K.BLACK,K.GRAY)
        R.drawButton(cx+80,cy,36,14,false)
        R.drawText(cx+84,cy+3,"-",K.BLACK,K.GRAY)
        R.drawText(cx+120,cy+3,imgW.."x"..imgH.." @"..scale.."x",K.BLACK,K.GRAY)
        R.drawText(cx+120,cy+11,formatName,K.DBLUE,K.GRAY)

        local viewX, viewY = cx+2, cy+28
        local viewW, viewH = cw-4, ch-40

        if #pixels == 0 then
            R.drawText(viewX+10, viewY+10, "No image loaded", K.BLACK, K.GRAY)
            return
        end

        for y = 1, math.min(imgH, math.floor(viewH/scale)) do
            for x = 1, math.min(imgW, math.floor(viewW/scale)) do
                local row = pixels[y + oy]
                if row then
                    local color = row[x + ox] or K.BLACK
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
