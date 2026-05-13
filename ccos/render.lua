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
    {8,10,14}, {248,249,252}, {202,206,214}, {232,235,240},
    {108,116,128}, {42,82,146}, {28,56,110}, {0,154,162},
    {135,211,232}, {36,160,90}, {24,112,66}, {218,64,64},
    {132,35,35}, {236,215,76}, {222,160,58}, {128,82,42},
    {118,72,156}, {230,138,210}, {70,76,86}, {35,92,154},
    {126,153,194}, {66,112,220}, {241,243,246}, {28,31,36},
    {158,165,176}, {216,220,226}, {252,253,255}, {20,36,74},
    {52,58,68}, {30,122,72}, {25,120,126}, {198,203,212},
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
    if w <= 0 or h <= 0 then return end
    local G = R.PAL.BUTTON_FACE or R.PAL.GRAY
    local DG = R.PAL.DARK_GRAY
    local LG = R.PAL.BUTTON_HI or R.PAL.LIGHT_GRAY
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

R.CYR_UPPER = {
    ["а"]="А", ["б"]="Б", ["в"]="В", ["г"]="Г", ["д"]="Д", ["е"]="Е", ["ё"]="Ё",
    ["ж"]="Ж", ["з"]="З", ["и"]="И", ["й"]="Й", ["к"]="К", ["л"]="Л", ["м"]="М",
    ["н"]="Н", ["о"]="О", ["п"]="П", ["р"]="Р", ["с"]="С", ["т"]="Т", ["у"]="У",
    ["ф"]="Ф", ["х"]="Х", ["ц"]="Ц", ["ч"]="Ч", ["ш"]="Ш", ["щ"]="Щ", ["ъ"]="Ъ",
    ["ы"]="Ы", ["ь"]="Ь", ["э"]="Э", ["ю"]="Ю", ["я"]="Я",
}

local CYR_FONT = {
    ["А"]={14,17,17,31,17,17,17}, ["Б"]={31,16,16,30,17,17,30},
    ["В"]={30,17,17,30,17,17,30}, ["Г"]={31,16,16,16,16,16,16},
    ["Д"]={14,17,17,17,17,31,17}, ["Е"]={31,16,16,30,16,16,31},
    ["Ё"]={10,0,31,16,30,16,31},  ["Ж"]={21,21,14,4,14,21,21},
    ["З"]={30,1,1,14,1,1,30},    ["И"]={17,19,21,21,21,25,17},
    ["Й"]={10,4,17,19,21,25,17}, ["К"]={17,18,20,24,20,18,17},
    ["Л"]={7,9,17,17,17,17,17},  ["М"]={17,27,21,21,17,17,17},
    ["Н"]={17,17,17,31,17,17,17}, ["О"]={14,17,17,17,17,17,14},
    ["П"]={31,17,17,17,17,17,17}, ["Р"]={30,17,17,30,16,16,16},
    ["С"]={14,17,16,16,16,17,14}, ["Т"]={31,4,4,4,4,4,4},
    ["У"]={17,17,10,4,8,16,14},  ["Ф"]={4,14,21,21,14,4,4},
    ["Х"]={17,17,10,4,10,17,17}, ["Ц"]={17,17,17,17,17,31,1},
    ["Ч"]={17,17,17,15,1,1,1},   ["Ш"]={17,17,17,21,21,21,31},
    ["Щ"]={17,17,17,21,21,31,1}, ["Ъ"]={24,8,8,14,9,9,14},
    ["Ы"]={17,17,17,25,21,21,25}, ["Ь"]={16,16,16,30,17,17,30},
    ["Э"]={14,17,1,7,1,17,14},   ["Ю"]={17,18,20,28,20,18,17},
    ["Я"]={15,17,17,15,5,9,17},
}
for ch, glyph in pairs(CYR_FONT) do R.FONT[ch] = glyph end

function R.utf8Chars(text)
    text = tostring(text or "")
    local chars = {}
    local i = 1
    while i <= #text do
        local b = text:byte(i) or 0
        local len = 1
        if b >= 240 then len = 4
        elseif b >= 224 then len = 3
        elseif b >= 192 then len = 2 end
        table.insert(chars, text:sub(i, i + len - 1))
        i = i + len
    end
    return chars
end

function R.utf8Len(text)
    return #R.utf8Chars(text)
end

function R.utf8Sub(text, first, last)
    local chars = R.utf8Chars(text)
    first = first or 1
    last = last or #chars
    local out = {}
    for i = first, math.min(last, #chars) do out[#out + 1] = chars[i] end
    return table.concat(out)
end

function R.utf8Pop(text)
    local chars = R.utf8Chars(text)
    table.remove(chars)
    return table.concat(chars)
end

function R.fontKey(ch)
    if not ch or ch == "" then return "?" end
    if #ch == 1 then return ch:upper() end
    return R.CYR_UPPER[ch] or ch
end

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
    for _, raw in ipairs(R.utf8Chars(text)) do
        local ch = R.fontKey(raw)
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

function R.textWidth(text)
    return R.utf8Len(text) * 6
end

function R.clipText(text, maxW)
    text = tostring(text or "")
    local maxChars = math.max(0, math.floor((maxW or 0) / 6))
    local chars = R.utf8Chars(text)
    if #chars <= maxChars then return text end
    if maxChars <= 0 then return "" end
    if maxChars <= 2 then return string.rep(".", maxChars) end
    local out = {}
    for i = 1, maxChars - 2 do out[#out + 1] = chars[i] end
    return table.concat(out) .. ".."
end

function R.drawTextClipped(x, y, text, fg, bg, maxW)
    R.drawText(x, y, R.clipText(text, maxW), fg, bg)
end

function R.drawButtonText(x, y, w, h, text, pressed, fg, bg)
    if w <= 0 or h <= 0 then return end
    R.drawButton(x, y, w, h, pressed)
    local label = R.clipText(text, math.max(0, w - 8))
    if label ~= "" then
        local tx = x + math.max(3, math.floor((w - R.textWidth(label)) / 2))
        local ty = y + math.max(2, math.floor((h - 7) / 2))
        R.drawText(tx, ty, label, fg or R.PAL.BLACK, bg or (R.PAL.BUTTON_FACE or R.PAL.GRAY))
    end
end

function R.clear()
    if R.mode > 0 then R.display.clear() else R.display.clear(); R.display.setCursorPos(1,1) end
end

return R
