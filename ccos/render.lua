--[[
    CCOS Render Engine
    ==================
    All drawing functions. Separated from desktop logic.
]]

local R = {}

R.hasGraphics = term.setGraphicsMode ~= nil
R.isColor = term.isColor and term.isColor() or false
R.w, R.h = 0, 0
R.display = term
R.mode = 0  -- 0=text, 1=16col, 2=256col

-- Palette (0-based indices for graphics mode 2)
R.PAL = {
    BLACK=0, WHITE=1, GRAY=2, LIGHT_GRAY=3, DARK_GRAY=4,
    BLUE=5, DARK_BLUE=6, CYAN=7, LIGHT_BLUE=8,
    GREEN=9, DARK_GREEN=10, RED=11, DARK_RED=12,
    YELLOW=13, ORANGE=14, BROWN=15, PURPLE=16, PINK=17,
    W95_TITLE_BLUE=19, W95_TITLE_INACTIVE=20,
    W95_DESKTOP=30, LIGHT_BG=31,
}

R.PALETTE = {
    {0,0,0}, {255,255,255}, {192,192,192}, {224,224,224}, {128,128,128},
    {0,0,192}, {0,0,128}, {0,192,192}, {128,224,255},
    {0,192,0}, {0,128,0}, {255,0,0}, {128,0,0},
    {255,255,0}, {255,192,0}, {128,64,0}, {128,0,128}, {255,128,255},
    {64,64,64}, {0,84,168}, {128,158,200},
    {0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},
    {0,128,128}, {192,192,192},
}

function R.init()
    if R.hasGraphics then
        R.display.setGraphicsMode(2)
        for i, c in ipairs(R.PALETTE) do
            pcall(function() R.display.setPaletteColor(i-1, c[1]/255, c[2]/255, c[3]/255) end)
        end
        R.w, R.h = R.display.getSize(1)
        R.mode = 2
    else
        R.w, R.h = R.display.getSize()
    end
end

-- Basic pixel operations
function R.setPixel(x, y, color)
    if R.mode == 0 then return end
    pcall(function() R.display.setPixel(x-1, y-1, color) end)
end

function R.fillRect(x, y, w, h, color)
    if R.mode == 0 then return end
    for row = 0, h-1 do
        for col = 0, w-1 do
            R.setPixel(x+col, y+row, color)
        end
    end
end

function R.drawLine(x1, y1, x2, y2, color)
    if R.mode == 0 then return end
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

function R.drawRect(x, y, w, h, color)
    if R.mode == 0 then return end
    R.drawLine(x, y, x+w-1, y, color)
    R.drawLine(x, y+h-1, x+w-1, y+h-1, color)
    R.drawLine(x, y, x, y+h-1, color)
    R.drawLine(x+w-1, y, x+w-1, y+h-1, color)
end

-- W95-style 3D effects
function R.drawW95Raised(x, y, w, h)
    if R.mode == 0 then return end
    R.drawLine(x, y, x+w-1, y, R.PAL.LIGHT_GRAY)
    R.drawLine(x, y, x, y+h-1, R.PAL.LIGHT_GRAY)
    R.drawLine(x+w-1, y, x+w-1, y+h-1, R.PAL.DARK_GRAY)
    R.drawLine(x, y+h-1, x+w-1, y+h-1, R.PAL.DARK_GRAY)
end

function R.drawW95Sunken(x, y, w, h)
    if R.mode == 0 then return end
    R.drawLine(x, y, x+w-1, y, R.PAL.DARK_GRAY)
    R.drawLine(x, y, x, y+h-1, R.PAL.DARK_GRAY)
    R.drawLine(x+w-1, y, x+w-1, y+h-1, R.PAL.LIGHT_GRAY)
    R.drawLine(x, y+h-1, x+w-1, y+h-1, R.PAL.LIGHT_GRAY)
end

function R.drawButton(x, y, w, h, pressed)
    if R.mode == 0 then return end
    R.fillRect(x+2, y+2, w-4, h-4, R.PAL.GRAY)
    if pressed then
        R.drawLine(x, y, x+w-1, y, R.PAL.DARK_GRAY)
        R.drawLine(x, y, x, y+h-1, R.PAL.DARK_GRAY)
        R.drawLine(x+w-1, y, x+w-1, y+h-1, R.PAL.LIGHT_GRAY)
        R.drawLine(x, y+h-1, x+w-1, y+h-1, R.PAL.LIGHT_GRAY)
    else
        R.drawW95Raised(x, y, w, h)
    end
end

function R.drawTitleBar(x, y, w, active)
    if R.mode == 0 then return end
    R.fillRect(x, y, w, 16, active and R.PAL.W95_TITLE_BLUE or R.PAL.GRAY)
end

-- Drag outline (dashed rectangle)
function R.drawDragOutline(x, y, w, h)
    if R.mode == 0 then return end
    for i = 0, w-1 do
        if i % 4 < 2 then
            R.setPixel(x+i, y, R.PAL.BLACK)
            if y+h-1 < R.h then R.setPixel(x+i, y+h-1, R.PAL.BLACK) end
        end
    end
    for i = 0, h-1 do
        if i % 4 < 2 then
            R.setPixel(x, y+i, R.PAL.BLACK)
            if x+w-1 < R.w then R.setPixel(x+w-1, y+i, R.PAL.BLACK) end
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
    $={4,15,20,14,5,30,4},["&"]={12,18,20,8,21,18,13},
    ["^"]={4,10,17,0,0,0,0},["~"]={0,0,8,21,2,0,0},
    ["`"]={8,4,2,0,0,0,0},["{"]={6,8,8,16,8,8,6},
    ["}"]={12,2,2,1,2,2,12},
}

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

function R.clear()
    if R.mode > 0 then R.display.clear() else R.display.clear(); R.display.setCursorPos(1,1) end
end

return R
