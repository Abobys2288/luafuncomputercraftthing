local R = {}

R.hasGraphics = term.setGraphicsMode ~= nil
R.hasDrawPixels = term.drawPixels ~= nil
R.hasFrozen = term.setFrozen ~= nil
R.isColor = term.isColor and term.isColor() or false
R.w, R.h = 0, 0
R.display = term.native() or term
R.mode = 0
R.PAL = {}

-- ============================================================
-- 256-color CCOS palette (indices 0-255)
-- ============================================================
local PALETTE = {}

-- 0-31: Original W95 palette
local W95 = {
    {0,0,0}, {255,255,255}, {192,192,192}, {223,223,223},
    {128,128,128}, {0,0,192}, {0,0,128}, {0,192,192},
    {128,224,255}, {0,192,0}, {0,128,0}, {255,0,0},
    {128,0,0}, {255,255,0}, {255,192,0}, {128,64,0},
    {128,0,128}, {255,128,255}, {64,64,64}, {0,84,168},
    {128,158,200}, {0,0,255}, {240,240,240}, {32,32,32},
    {160,160,160}, {200,200,200}, {248,248,248}, {0,0,64},
    {48,48,48}, {0,128,0}, {0,128,128}, {192,192,192},
}
for i, c in ipairs(W95) do
    PALETTE[i-1] = c
end

-- 32-215: 6×6×6 RGB color cube (indices 32-215)
-- R, G, B each: 0, 51, 102, 153, 204, 255
local idx = 32
for r = 0, 5 do
    for g = 0, 5 do
        for b = 0, 5 do
            PALETTE[idx] = {r*51, g*51, b*51}
            idx = idx + 1
        end
    end
end

-- 216-255: 40 grayscale + extra
for i = 0, 39 do
    local v = math.floor(i * 255 / 39)
    PALETTE[216 + i] = {v, v, v}
end

function R.init()
    if R.hasGraphics then
        R.display.setGraphicsMode(2)
        for i = 0, 255 do
            local c = PALETTE[i]
            if c then
                pcall(function()
                    R.display.setPaletteColor(i, c[1]/255, c[2]/255, c[3]/255)
                end)
            end
        end
        R.w, R.h = R.display.getSize(1)
        R.mode = 2
        R.hasDrawPixels = R.display.drawPixels ~= nil
        R.hasFrozen = R.display.setFrozen ~= nil
    else
        R.w, R.h = R.display.getSize()
    end

    -- Named shortcuts for common colors (0-31 still valid)
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
    -- Make any palette index accessible as PAL[32], PAL[100], etc.
    setmetatable(R.PAL, {
        __index = function(t, k)
            if type(k) == "number" and k >= 0 and k <= 255 then
                return k
            end
            return nil
        end
    })
end

-- ============================================================
-- Default 16-color CC palette (restored when leaving graphics)
-- ============================================================
local DEFAULT_CC_COLORS = {
    [colors.white]     = {240/255, 240/255, 240/255},
    [colors.orange]    = {242/255, 178/255,  51/255},
    [colors.magenta]   = {229/255, 127/255, 216/255},
    [colors.lightBlue] = {153/255, 217/255, 234/255},
    [colors.yellow]    = {222/255, 222/255, 108/255},
    [colors.lime]      = {127/255, 204/255,  25/255},
    [colors.pink]      = {242/255, 178/255, 204/255},
    [colors.gray]      = { 76/255,  76/255,  76/255},
    [colors.lightGray] = {153/255, 153/255, 153/255},
    [colors.cyan]      = { 76/255, 153/255, 178/255},
    [colors.purple]    = {127/255,  63/255, 178/255},
    [colors.blue]      = { 51/255, 102/255, 204/255},
    [colors.brown]     = {127/255, 102/255,  76/255},
    [colors.green]     = { 87/255, 166/255,  78/255},
    [colors.red]       = {204/255,  76/255,  76/255},
    [colors.black]     = { 25/255,  25/255,  25/255},
}

function R.resetPalette()
    local t = term.native() or term
    if not t.setPaletteColor then return end
    for col, rgb in pairs(DEFAULT_CC_COLORS) do
        pcall(function() t.setPaletteColor(col, rgb[1], rgb[2], rgb[3]) end)
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

function R.shutdown()
    if R.hasGraphics then
        pcall(function() (term.native() or term).setGraphicsMode(0) end)
    end
    R.resetPalette()
end

-- ============================================================
-- BSOD (Blue Screen of Death)
-- ============================================================
function R.bsod(errorCode, message)
    if R.hasGraphics then
        pcall(function() (term.native() or term).setGraphicsMode(0) end)
    end
    R.resetPalette()
    local t = term.native() or term
    t.setBackgroundColor(colors.blue)
    t.setTextColor(colors.white)
    t.clear()
    t.setCursorPos(1, 1)
    print("")
    print("  *** STOP: " .. tostring(errorCode or "0x0000001E"))
    print("")
    print("  " .. tostring(message or "A fatal exception has occurred."))
    print("")
    print("  The current application will be terminated.")
    print("")
    print("  * Press any key to reboot your computer.")
    print("")
    print("  * Press CTRL+ALT+DEL to restart (if available).")
end

-- Basic pixel operations
function R.setPixel(x, y, color)
    if R.mode == 0 then return end
    if x < 1 or y < 1 or x > R.w or y > R.h then return end
    R.display.setPixel(x-1, y-1, color)
end

-- fillRect optimized with drawPixels
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

-- drawLine optimized
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

-- drawRect
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

-- Pixel font 5x7 drawing
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
