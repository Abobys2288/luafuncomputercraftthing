local R = {}

R.hasGraphics = term.setGraphicsMode ~= nil
R.hasDrawPixels = term.drawPixels ~= nil
R.hasFrozen = term.setFrozen ~= nil
R.isColor = term.isColor and term.isColor() or false
R.w, R.h = 0, 0
R.display = term
R.mode = 0
R.PAL = {}

-- Full 32-color W95 palette (indices 0-31)
local PALETTE = {
    {0,0,0},           -- 0  BLACK
    {255,255,255},     -- 1  WHITE
    {192,192,192},     -- 2  GRAY (window bg)
    {223,223,223},     -- 3  LIGHT_GRAY
    {128,128,128},     -- 4  DARK_GRAY
    {0,0,192},         -- 5  BLUE
    {0,0,128},         -- 6  DARK_BLUE (active title)
    {0,192,192},       -- 7  CYAN
    {128,224,255},     -- 8  LIGHT_BLUE
    {0,192,0},         -- 9  GREEN
    {0,128,0},         -- 10 DARK_GREEN
    {255,0,0},         -- 11 RED
    {128,0,0},         -- 12 DARK_RED
    {255,255,0},       -- 13 YELLOW
    {255,192,0},       -- 14 ORANGE
    {128,64,0},        -- 15 BROWN
    {128,0,128},       -- 16 PURPLE
    {255,128,255},     -- 17 PINK
    {64,64,64},        -- 18 DARK_TITLE_INACTIVE
    {0,84,168},        -- 19 W95_TITLE_BLUE (active title)
    {128,158,200},     -- 20 W95_TITLE_INACTIVE
    {0,0,255},         -- 21 PURE_BLUE
    {240,240,240},     -- 22 ALMOST_WHITE
    {32,32,32},        -- 23 NEAR_BLACK
    {160,160,160},     -- 24 MID_GRAY
    {200,200,200},     -- 25 BUTTON_FACE
    {248,248,248},     -- 26 BUTTON_HIGHLIGHT
    {0,0,64},          -- 27 DEEP_NAVY
    {48,48,48},        -- 28 BTNFACE_DARK
    {0,128,0},         -- 29 DARK_GREEN_BG
    {0,128,128},       -- 30 W95_DESKTOP (teal)
    {192,192,192},     -- 31 LIGHT_BG (same as GRAY)
}

function R.init()
    if R.hasGraphics then
        R.display.setGraphicsMode(2)
        for i, c in ipairs(PALETTE) do
            pcall(function()
                R.display.setPaletteColor(i-1, c[1]/255, c[2]/255, c[3]/255)
            end)
        end
        R.w, R.h = R.display.getSize(1)
        R.mode = 2
        R.hasDrawPixels = R.display.drawPixels ~= nil
        R.hasFrozen = R.display.setFrozen ~= nil
    else
        R.w, R.h = R.display.getSize()
    end

    R.PAL = {
        BLACK=0, WHITE=1, GRAY=2, LIGHT_GRAY=3, DARK_GRAY=4,
        BLUE=5, DARK_BLUE=6, CYAN=7, LIGHT_BLUE=8,
        GREEN=9, DARK_GREEN=10, RED=11, DARK_RED=12,
        YELLOW=13, ORANGE=14, BROWN=15, PURPLE=16, PINK=17,
        DARK_TITLE=18, W95_TITLE_BLUE=19, W95_TITLE_INACTIVE=20,
        PURE_BLUE=21, ALMOST_WHITE=22, NEAR_BLACK=23, MID_GRAY=24,
        BUTTON_FACE=25, BUTTON_HI=26, DEEP_NAVY=27, BTNFACE_DARK=28,
        DARK_GREEN_BG=29, W95_DESKTOP=30, LIGHT_BG=2,
    }

    if R.hasDrawPixels then
        R._charBuf = {}
        for row = 1, 8 do
            R._charBuf[row] = {0, 0, 0, 0, 0, 0}
        end
    end
end

-- Freeze/unfreeze display during batch drawing
function R.beginDraw()
    if R.mode > 0 and R.hasFrozen then
        pcall(function() R.display.setFrozen(true) end)
    end
end

function R.endDraw()
    if R.mode > 0 and R.hasFrozen then
        pcall(function() R.display.setFrozen(false) end)
    end
end

-- Basic pixel operations
function R.setPixel(x, y, color)
    if R.mode == 0 then return end
    if x < 1 or y < 1 or x > R.w or y > R.h then return end
    R.display.setPixel(x-1, y-1, color)
end

-- fillRect optimized with drawPixels (1 API call instead of w*h setPixel calls)
function R.fillRect(x, y, w, h, color)
    if R.mode == 0 or w <= 0 or h <= 0 then return end
    if x < 1 then w = w + x - 1; x = 1 end
    if y < 1 then h = h + y - 1; y = 1 end
    if x + w - 1 > R.w then w = R.w - x + 1 end
    if y + h - 1 > R.h then h = R.h - y + 1 end
    if w <= 0 or h <= 0 then return end
    if R.hasDrawPixels then
        R.display.drawPixels(x-1, y-1, color, w, h)
    else
        for row = 0, h-1 do
            for col = 0, w-1 do
                R.setPixel(x+col, y+row, color)
            end
        end
    end
end

-- drawLine optimized: horizontal/vertical lines use fillRect
function R.drawLine(x1, y1, x2, y2, color)
    if R.mode == 0 then return end
    if y1 == y2 then
        local x = math.min(x1, x2)
        R.fillRect(x, y1, math.abs(x2-x1)+1, 1, color)
    elseif x1 == x2 then
        local y = math.min(y1, y2)
        R.fillRect(x1, y, 1, math.abs(y2-y1)+1, color)
    else
        local dx, dy = math.abs(x2-x1), math.abs(y2-y1)
        local sx, sy = x1<x2 and 1 or -1, y1<y2 and 1 or -1
        local err = dx - dy
        while true do
            R.setPixel(x1, y1, color)
            if x1==x2 and y1==y2 then break end
            local e2 = 2*err
            if e2 > -dy then err = err-dy; x1 = x1+sx end
            if e2 < dx then err = err+dx; y1 = y1+sy end
        end
    end
end

-- drawRect optimized: 4 fillRect calls
function R.drawRect(x, y, w, h, color)
    if R.mode == 0 or w <= 0 or h <= 0 then return end
    R.fillRect(x, y, w, 1, color)
    R.fillRect(x, y+h-1, w, 1, color)
    R.fillRect(x, y, 1, h, color)
    R.fillRect(x+w-1, y, 1, h, color)
end

function R.drawW95Raised(x, y, w, h)
    if R.mode == 0 then return end
    local LG = R.PAL.LIGHT_GRAY
    local DG = R.PAL.DARK_GRAY
    R.drawLine(x, y, x+w-1, y, LG)
    R.drawLine(x, y, x, y+h-1, LG)
    R.drawLine(x+w-1, y, x+w-1, y+h-1, DG)
    R.drawLine(x, y+h-1, x+w-1, y+h-1, DG)
end

function R.drawW95Sunken(x, y, w, h)
    if R.mode == 0 then return end
    local LG = R.PAL.LIGHT_GRAY
    local DG = R.PAL.DARK_GRAY
    R.drawLine(x, y, x+w-1, y, DG)
    R.drawLine(x, y, x, y+h-1, DG)
    R.drawLine(x+w-1, y, x+w-1, y+h-1, LG)
    R.drawLine(x, y+h-1, x+w-1, y+h-1, LG)
end

function R.drawButton(x, y, w, h, pressed)
    if R.mode == 0 then return end
    local G = R.PAL.GRAY
    local DG = R.PAL.DARK_GRAY
    local LG = R.PAL.LIGHT_GRAY
    R.fillRect(x+2, y+2, w-4, h-4, G)
    if pressed then
        R.drawLine(x, y, x+w-1, y, DG)
        R.drawLine(x, y, x, y+h-1, DG)
        R.drawLine(x+w-1, y, x+w-1, y+h-1, LG)
        R.drawLine(x, y+h-1, x+w-1, y+h-1, LG)
    else
        R.drawW95Raised(x, y, w, h)
    end
end

function R.drawTitleBar(x, y, w, active)
    if R.mode == 0 then return end
    R.fillRect(x, y, w, 16, active and R.PAL.W95_TITLE_BLUE or R.PAL.GRAY)
end

function R.drawDragOutline(x, y, w, h)
    if R.mode == 0 then return end
    local BK = R.PAL.BLACK
    for i = 0, w-1 do
        if i % 4 < 2 then
            R.setPixel(x+i, y, BK)
            if y+h-1 < R.h then R.setPixel(x+i, y+h-1, BK) end
        end
    end
    for i = 0, h-1 do
        if i % 4 < 2 then
            R.setPixel(x, y+i, BK)
            if x+w-1 < R.w then R.setPixel(x+w-1, y+i, BK) end
        end
    end
end

-- Pixel font 5x7
R.FONT = {
    A={14,17,17,31,17,17,17},B={30,17,17,30,17,17,30},C={14,17,16,16,16,17,14},
    D={30,17,17,17,17,17,30},E={31,16,16,30,16,16,31},F={31,16,16,30,16,16,16},
    G={14,17,16,23,17,17,14},H={17,17,17,31,17,17,17},I={14,4,4,4,4,4,14},
    J={7,2,2,2,2,18,12},K={17,18,20,24,20,18,17},L={16,16,16,16,16,16,31},
    M={17,27,21,21,17,17,17},N={17,17,25,21,19,17,17},O={14,17,17,17,17,17,14},
    P={30,17,17,30,16,16,16},Q={14,17,17,17,21,18,13},R={30,17,17,30,20,18,17},
    S={14,17,16,14,1,17,14},T={31,4,4,4,4,4,4},U={17,17,17,17,17,17,14},
    V={17,17,17,17,17,10,4},W={17,17,17,21,21,27,17},X={17,17,10,4,10,17,17},
    Y={17,17,10,4,4,4,4},Z={31,1,2,4,8,16,31},
    ["0"]={14,17,19,21,25,17,14},["1"]={4,12,4,4,4,4,14},
    ["2"]={14,17,1,6,8,16,31},["3"]={14,17,1,6,1,17,14},
    ["4"]={2,6,10,18,31,2,2},["5"]={31,16,30,1,1,17,14},
    ["6"]={14,16,16,30,17,17,14},["7"]={31,1,2,4,8,8,8},
    ["8"]={14,17,17,14,17,17,14},["9"]={14,17,17,15,1,1,14},
    [" "]={0,0,0,0,0,0,0},["."]={0,0,0,0,0,0,4},[":"]={0,4,0,0,0,4,0},
    ["-"]={0,0,0,31,0,0,0},["/"]={1,2,2,4,8,8,16},
    ["("]={2,4,8,8,8,4,2},[")"]={8,4,2,2,2,4,8},
    ["["]={14,8,8,8,8,8,14},["]"]={14,2,2,2,2,2,14},
    ["+"]={0,4,4,31,4,4,0},["="]={0,0,31,0,31,0,0},
    ["_"]={0,0,0,0,0,0,31},["!"]={4,4,4,4,4,0,4},
    ["?"]={14,17,1,6,4,0,4},[","]={0,0,0,0,0,4,8},
    [";"]={0,4,0,0,0,4,8},["'"]={4,4,8,0,0,0,0},
    ['"']={10,10,20,0,0,0,0},["#"]={10,10,31,10,31,10,10},
    ["%"]={19,20,2,4,8,11,19},["*"]={0,21,14,31,14,21,0},
    ["<"]={2,4,8,16,8,4,2},[">"]={8,4,2,1,2,4,8},
    ["|"]={4,4,4,4,4,4,4},["@"]={14,17,23,21,22,16,14},
    ["$"]={4,15,20,14,5,30,4},["&"]={12,18,20,8,21,18,13},
    ["^"]={4,10,17,0,0,0,0},["~"]={0,0,8,21,2,0,0},
    ["`"]={8,4,2,0,0,0,0},["{"]={6,8,8,16,8,8,6},
    ["}"]={12,2,2,1,2,2,12},
}

-- drawText optimized with drawPixels per character (1 call per char instead of 35 setPixel calls)
function R.drawText(x, y, text, fg, bg)
    if R.mode == 0 then
        R.display.setCursorPos(x, y)
        if R.isColor then
            if fg then R.display.setTextColor(fg) end
            if bg then R.display.setBackgroundColor(bg) end
        end
        R.display.write(text)
        if R.isColor then R.display.setTextColor(colors.white); R.display.setBackgroundColor(colors.black) end
        return
    end
        if R.hasDrawPixels and R._charBuf and bg ~= nil then
        local cx = x
        local buf = R._charBuf
        for i = 1, #text do
            local ch = text:sub(i,i):upper()
            local glyph = R.FONT[ch] or R.FONT["?"]
            for row = 1, 7 do
                local bits = glyph[row]
                local rd = buf[row]
                for col = 4, 0, -1 do
                    local mask = 2^col
                    rd[5-col] = (math.floor(bits / mask) % 2 == 1) and fg or bg
                end
                rd[6] = bg
            end
            buf[8][1]=bg; buf[8][2]=bg; buf[8][3]=bg
            buf[8][4]=bg; buf[8][5]=bg; buf[8][6]=bg
            R.display.drawPixels(cx-1, y-1, buf)
            cx = cx + 6
        end
                rd[6] = bg
            end
            buf[8][1]=bg; buf[8][2]=bg; buf[8][3]=bg
            buf[8][4]=bg; buf[8][5]=bg; buf[8][6]=bg
            R.display.drawPixels(cx-1, y-1, buf)
            cx = cx + 6
        end
    else
        local cx = x
        for i = 1, #text do
            local ch = text:sub(i,i):upper()
            local glyph = R.FONT[ch] or R.FONT["?"]
            for row = 1, 7 do
                local bits = glyph[row]
                for col = 4, 0, -1 do
                    local mask = 2^col
                    if math.floor(bits / mask) % 2 == 1 then
                        R.setPixel(cx+(4-col), y+row-1, fg)
                    elseif bg then
                        R.setPixel(cx+(4-col), y+row-1, bg)
                    end
                end
            end
            cx = cx + 6
        end
                end
            end
            cx = cx + 6
        end
                end
            end
            cx = cx + 6
        end
    end
end

function R.clear()
    if R.mode > 0 then R.display.clear() else R.display.clear(); R.display.setCursorPos(1,1) end
end

return R
