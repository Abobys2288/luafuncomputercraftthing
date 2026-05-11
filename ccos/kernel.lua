--[[
    CCOS Kernel — Graphics + Mouse
    ==============================
    Windows 95-style GUI using CC:Graphics addon.
    Falls back to text mode if CC:Graphics is not installed.
]]

local kernel = {}

-- Detect capabilities
kernel.hasGraphics = term.setGraphicsMode ~= nil
kernel.isColor = term.isColor and term.isColor() or false

-- W95 palette indices (for graphics mode 2)
kernel.PAL = {
    BLACK = 0, WHITE = 1,
    GRAY = 2, LIGHT_GRAY = 3,
    DARK_GRAY = 4,
    BLUE = 5, DARK_BLUE = 6,
    CYAN = 7, LIGHT_BLUE = 8,
    GREEN = 9, DARK_GREEN = 10,
    RED = 11, DARK_RED = 12,
    YELLOW = 13, ORANGE = 14,
    BROWN = 15, PURPLE = 16,
    PINK = 17,
}

-- W95 style colors (RGB for palette mode 2)
kernel.PALETTE = {
    {0, 0, 0},           -- 0  BLACK
    {255, 255, 255},     -- 1  WHITE
    {192, 192, 192},     -- 2  GRAY (W95 window bg)
    {224, 224, 224},     -- 3  LIGHT_GRAY
    {128, 128, 128},     -- 4  DARK_GRAY
    {0, 0, 192},         -- 5  BLUE
    {0, 0, 128},         -- 6  DARK_BLUE (W95 title bar active)
    {0, 192, 192},       -- 7  CYAN
    {128, 224, 255},     -- 8  LIGHT_BLUE
    {0, 192, 0},         -- 9  GREEN
    {0, 128, 0},         -- 10 DARK_GREEN
    {255, 0, 0},         -- 11 RED
    {128, 0, 0},         -- 12 DARK_RED
    {255, 255, 0},       -- 13 YELLOW
    {255, 192, 0},       -- 14 ORANGE
    {128, 64, 0},        -- 15 BROWN
    {128, 0, 128},       -- 16 PURPLE
    {255, 128, 255},     -- 17 PINK
    {64, 64, 64},        -- 18 DARK_TITLE
    {0, 84, 168},        -- 19 W95_TITLE_BLUE (active title)
    {128, 158, 200},     -- 20 W95_TITLE_INACTIVE
    {0, 0, 255},         -- 21 PURE_BLUE
    {240, 240, 240},     -- 22 ALMOST_WHITE
    {32, 32, 32},        -- 23 NEAR_BLACK
    {160, 160, 160},     -- 24 MID_GRAY
    {200, 200, 200},     -- 25 W95_BUTTON_FACE
    {248, 248, 248},     -- 26 W95_BUTTON_HIGHLIGHT
    {0, 0, 64},          -- 27 DEEP_NAVY
    {48, 48, 48},        -- 28 W95_BTNFACE_DARK
}

kernel.w, kernel.h = 0, 0
kernel.display = term
kernel.mode = 0  -- 0=text, 1=16col, 2=256col

-- ============================================================
-- DISPLAY INIT
-- ============================================================
function kernel.initDisplay()
    if kernel.hasGraphics then
        local best = term
        local bw, bh = term.getSize(1)
        local sides = {"top","bottom","left","right","front","back"}
        for _, s in ipairs(sides) do
            local ok, m = pcall(peripheral.wrap, s)
            if ok and m and m.setGraphicsMode then
                pcall(function() m.setTextScale(1) end)
                local w, h = m.getSize(1)
                if w * h > bw * bh then
                    best = m; bw = w; bh = h
                end
            end
        end
        kernel.display = best
        kernel.setGraphicsMode(2)
        kernel.applyPalette()
        kernel.w, kernel.h = kernel.display.getSize(1)
    else
        local sides = {"top","bottom","left","right","front","back"}
        local best = term
        local bw, bh = term.getSize()
        for _, s in ipairs(sides) do
            local ok, m = pcall(peripheral.wrap, s)
            if ok and m and m.getSize then
                pcall(function() m.setTextScale(1) end)
                local w, h = m.getSize()
                if w * h > bw * bh then
                    best = m; bw = w; bh = h
                end
            end
        end
        kernel.display = best
        kernel.w = bw
        kernel.h = bh
    end
end

function kernel.setGraphicsMode(mode)
    if not kernel.hasGraphics then return end
    local ok = pcall(function() kernel.display.setGraphicsMode(mode) end)
    if ok then
        kernel.mode = mode
        if mode > 0 then
            local w, h = kernel.display.getSize(1)
            kernel.w = w
            kernel.h = h
        end
    end
end

function kernel.applyPalette()
    if not kernel.hasGraphics or kernel.mode ~= 2 then return end
    for i, color in ipairs(kernel.PALETTE) do
        pcall(function()
            kernel.display.setPaletteColor(i - 1, color[1] / 255, color[2] / 255, color[3] / 255)
        end)
    end
end

-- ============================================================
-- PIXEL DRAWING (graphics mode)
-- ============================================================
function kernel.setPixel(x, y, color)
    if kernel.mode == 0 then return end
    pcall(function() kernel.display.setPixel(x - 1, y - 1, color) end)
end

function kernel.drawLine(x1, y1, x2, y2, color)
    if kernel.mode == 0 then return end
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    while true do
        kernel.setPixel(x1, y1, color)
        if x1 == x2 and y1 == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x1 = x1 + sx end
        if e2 < dx then err = err + dx; y1 = y1 + sy end
    end
end

function kernel.fillRect(x, y, w, h, color)
    if kernel.mode == 0 then return end
    for row = 0, h - 1 do
        for col = 0, w - 1 do
            kernel.setPixel(x + col, y + row, color)
        end
    end
end

function kernel.drawRect(x, y, w, h, color)
    if kernel.mode == 0 then return end
    kernel.drawLine(x, y, x + w - 1, y, color)
    kernel.drawLine(x, y + h - 1, x + w - 1, y + h - 1, color)
    kernel.drawLine(x, y, x, y + h - 1, color)
    kernel.drawLine(x + w - 1, y, x + w - 1, y + h - 1, color)
end

-- ============================================================
-- W95-STYLE 3D EFFECTS
-- ============================================================
function kernel.drawW95Raised(x, y, w, h)
    if kernel.mode == 0 then return end
    -- Top/left: light
    kernel.drawLine(x, y, x + w - 1, y, kernel.PAL.LIGHT_GRAY)
    kernel.drawLine(x, y, x, y + h - 1, kernel.PAL.LIGHT_GRAY)
    -- Inner light
    kernel.drawLine(x + 1, y + 1, x + w - 2, y + 1, kernel.PAL.WHITE)
    kernel.drawLine(x + 1, y + 1, x + 1, y + h - 2, kernel.PAL.WHITE)
    -- Bottom/right: dark
    kernel.drawLine(x + w - 1, y, x + w - 1, y + h - 1, kernel.PAL.DARK_GRAY)
    kernel.drawLine(x, y + h - 1, x + w - 1, y + h - 1, kernel.PAL.DARK_GRAY)
    -- Inner dark
    kernel.drawLine(x + w - 2, y + 1, x + w - 2, y + h - 2, kernel.PAL.GRAY)
    kernel.drawLine(x + 1, y + h - 2, x + w - 2, y + h - 2, kernel.PAL.GRAY)
end

function kernel.drawW95Sunken(x, y, w, h)
    if kernel.mode == 0 then return end
    kernel.drawLine(x, y, x + w - 1, y, kernel.PAL.DARK_GRAY)
    kernel.drawLine(x, y, x, y + h - 1, kernel.PAL.DARK_GRAY)
    kernel.drawLine(x + w - 1, y, x + w - 1, y + h - 1, kernel.PAL.WHITE)
    kernel.drawLine(x, y + h - 1, x + w - 1, y + h - 1, kernel.PAL.WHITE)
end

function kernel.drawW95Button(x, y, w, h, pressed)
    if kernel.mode == 0 then return end
    kernel.fillRect(x + 2, y + 2, w - 4, h - 4, kernel.PAL.GRAY)
    if pressed then
        kernel.drawLine(x, y, x + w - 1, y, kernel.PAL.DARK_GRAY)
        kernel.drawLine(x, y, x, y + h - 1, kernel.PAL.DARK_GRAY)
        kernel.drawLine(x + 1, y + 1, x + w - 2, y + 1, kernel.PAL.GRAY)
        kernel.drawLine(x + 1, y + 1, x + 1, y + h - 2, kernel.PAL.GRAY)
        kernel.drawLine(x + w - 1, y, x + w - 1, y + h - 1, kernel.PAL.LIGHT_GRAY)
        kernel.drawLine(x, y + h - 1, x + w - 1, y + h - 1, kernel.PAL.LIGHT_GRAY)
    else
        kernel.drawW95Raised(x, y, w, h)
    end
end

function kernel.drawW95TitleBar(x, y, w, active)
    if kernel.mode == 0 then return end
    local color = active and kernel.PAL.DARK_BLUE or kernel.PAL.GRAY
    kernel.fillRect(x, y, w, 18, color)
    -- Blue stripe on active
    if active then
        for i = 0, w - 1 do
            if i % 4 < 2 then
                kernel.setPixel(x + i, y, kernel.PAL.BLUE)
            end
        end
    end
end

function kernel.drawW95CloseButton(x, y, pressed)
    if kernel.mode == 0 then return end
    kernel.drawW95Button(x, y, 16, 14, pressed)
    -- X symbol
    local cx, cy = x + 4, y + 3
    for i = 0, 7 do
        kernel.setPixel(cx + i, cy + i, kernel.PAL.BLACK)
        kernel.setPixel(cx + i + 1, cy + i, kernel.PAL.BLACK)
        kernel.setPixel(cx + 7 - i, cy + i, kernel.PAL.BLACK)
        kernel.setPixel(cx + 8 - i, cy + i, kernel.PAL.BLACK)
    end
end

function kernel.drawW95MinButton(x, y, pressed)
    if kernel.mode == 0 then return end
    kernel.drawW95Button(x, y, 16, 14, pressed)
    -- Minus symbol
    kernel.fillRect(x + 4, y + 6, 8, 2, kernel.PAL.BLACK)
end

function kernel.drawW95MaxButton(x, y, pressed)
    if kernel.mode == 0 then return end
    kernel.drawW95Button(x, y, 16, 14, pressed)
    -- Square symbol
    kernel.drawRect(x + 4, y + 3, 8, 8, kernel.PAL.BLACK)
    kernel.fillRect(x + 4, y + 3, 8, 1, kernel.PAL.BLACK)
end

-- ============================================================
-- TEXT (pixel-based for graphics mode)
-- ============================================================
function kernel.drawText(x, y, text, fg, bg)
    if kernel.mode == 0 then
        -- Text mode fallback
        kernel.display.setCursorPos(x, y)
        if kernel.isColor then
            if fg then kernel.display.setTextColor(fg) end
            if bg then kernel.display.setBackgroundColor(bg) end
        end
        kernel.display.write(text)
        if kernel.isColor then
            kernel.display.setTextColor(colors.white)
            kernel.display.setBackgroundColor(colors.black)
        end
    else
        -- Graphics mode — draw pixel text
        kernel.drawPixelText(x, y, text, fg or kernel.PAL.WHITE, bg)
    end
end

-- Simple 5x7 pixel font
kernel.FONT = {
    ["A"] = {0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001},
    ["B"] = {0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110},
    ["C"] = {0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110},
    ["D"] = {0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110},
    ["E"] = {0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111},
    ["F"] = {0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000},
    ["G"] = {0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110},
    ["H"] = {0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001},
    ["I"] = {0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110},
    ["J"] = {0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100},
    ["K"] = {0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001},
    ["L"] = {0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111},
    ["M"] = {0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001},
    ["N"] = {0b10001, 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001},
    ["O"] = {0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110},
    ["P"] = {0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000},
    ["Q"] = {0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101},
    ["R"] = {0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001},
    ["S"] = {0b01110, 0b10001, 0b10000, 0b01110, 0b00001, 0b10001, 0b01110},
    ["T"] = {0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100},
    ["U"] = {0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110},
    ["V"] = {0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100},
    ["W"] = {0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001},
    ["X"] = {0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001},
    ["Y"] = {0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100},
    ["Z"] = {0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111},
    ["0"] = {0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110},
    ["1"] = {0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110},
    ["2"] = {0b01110, 0b10001, 0b00001, 0b00110, 0b01000, 0b10000, 0b11111},
    ["3"] = {0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110},
    ["4"] = {0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010},
    ["5"] = {0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110},
    ["6"] = {0b01110, 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110},
    ["7"] = {0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000},
    ["8"] = {0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110},
    ["9"] = {0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110},
    [" "] = {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000},
    ["."] = {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100},
    [":"] = {0b00000, 0b00100, 0b00000, 0b00000, 0b00000, 0b00100, 0b00000},
    ["-"] = {0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000},
    ["/"] = {0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000},
    ["\\"] = {0b10000, 0b01000, 0b01000, 0b00100, 0b00010, 0b00010, 0b00001},
    ["("] = {0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010},
    [")"] = {0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000},
    ["["] = {0b01110, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110},
    ["]"] = {0b01110, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110},
    ["+"] = {0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000},
    ["="] = {0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000},
    ["_"] = {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111},
    ["!"] = {0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100},
    ["?"] = {0b01110, 0b10001, 0b00001, 0b00110, 0b00100, 0b00000, 0b00100},
    [","] = {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b01000},
    [";"] = {0b00000, 0b00100, 0b00000, 0b00000, 0b00000, 0b00100, 0b01000},
    ["'"] = {0b00100, 0b00100, 0b01000, 0b00000, 0b00000, 0b00000, 0b00000},
    ['"'] = {0b01010, 0b01010, 0b10100, 0b00000, 0b00000, 0b00000, 0b00000},
    ["#"] = {0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010},
    ["%"] = {0b11001, 0b11010, 0b00010, 0b00100, 0b01000, 0b01011, 0b10011},
    ["*"] = {0b00000, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0b00000},
    ["<"] = {0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010},
    [">"] = {0b01000, 0b00100, 0b00010, 0b00001, 0b00010, 0b00100, 0b01000},
    ["|"] = {0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100},
    ["@"] = {0b01110, 0b10001, 0b10111, 0b10101, 0b10110, 0b10000, 0b01110},
    ["$"] = {0b00100, 0b01111, 0b10100, 0b01110, 0b00101, 0b11110, 0b00100},
    ["&"] = {0b01100, 0b10010, 0b10100, 0b01000, 0b10101, 0b10010, 0b01101},
    ["^"] = {0b00100, 0b01010, 0b10001, 0b00000, 0b00000, 0b00000, 0b00000},
    ["~"] = {0b00000, 0b00000, 0b01000, 0b10101, 0b00010, 0b00000, 0b00000},
    ["`"] = {0b01000, 0b00100, 0b00010, 0b00000, 0b00000, 0b00000, 0b00000},
    ["{"] = {0b00110, 0b01000, 0b01000, 0b10000, 0b01000, 0b01000, 0b00110},
    ["}"] = {0b01100, 0b00010, 0b00010, 0b00001, 0b00010, 0b00010, 0b01100},
}

function kernel.drawPixelText(x, y, text, fg, bg)
    if kernel.mode == 0 then return end
    local cx = x
    for i = 1, #text do
        local ch = text:sub(i, i):upper()
        local glyph = kernel.FONT[ch] or kernel.FONT["?"]
        for row = 1, 7 do
            local bits = glyph[row]
            for col = 4, 0, -1 do
                if bit32 then
                    if bit32.band(bit32.rshift(bits, col), 1) == 1 then
                        kernel.setPixel(cx + (4 - col), y + row - 1, fg)
                    elseif bg then
                        kernel.setPixel(cx + (4 - col), y + row - 1, bg)
                    end
                else
                    -- Fallback without bit32
                    local mask = 2 ^ col
                    if math.floor(bits / mask) % 2 == 1 then
                        kernel.setPixel(cx + (4 - col), y + row - 1, fg)
                    elseif bg then
                        kernel.setPixel(cx + (4 - col), y + row - 1, bg)
                    end
                end
            end
        end
        cx = cx + 6
    end
end

-- ============================================================
-- CLEAR / FLIP
-- ============================================================
function kernel.clear()
    if kernel.mode > 0 then
        kernel.display.clear()
    else
        kernel.display.clear()
        kernel.display.setCursorPos(1, 1)
    end
end

-- ============================================================
-- MOUSE SUPPORT
-- ============================================================
kernel.mouse = {x = 0, y = 0, down = false}

function kernel.getMousePos()
    return kernel.mouse.x, kernel.mouse.y
end

function kernel.isMouseDown()
    return kernel.mouse.down
end

function kernel.handleMouseEvent(event)
    if event[1] == "mouse_click" then
        kernel.mouse.x = event[3]
        kernel.mouse.y = event[4]
        kernel.mouse.down = true
        return true
    elseif event[1] == "mouse_up" then
        kernel.mouse.down = false
        return true
    elseif event[1] == "mouse_drag" then
        kernel.mouse.x = event[3]
        kernel.mouse.y = event[4]
        return true
    end
    return false
end

-- ============================================================
-- FS HELPERS
-- ============================================================
function kernel.listFiles(path)
    path = path or "/"
    local ok, list = pcall(fs.list, path)
    if ok then return list end
    return {}
end

function kernel.fileExists(path)
    return fs.exists(path)
end

function kernel.isDir(path)
    return fs.isDir(path)
end

function kernel.readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    return content
end

function kernel.writeFile(path, content)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

function kernel.deleteFile(path)
    if fs.exists(path) then fs.delete(path); return true end
    return false
end

function kernel.makeDir(path)
    if not fs.exists(path) then fs.makeDir(path); return true end
    return false
end

function kernel.getDir(path)
    if not path or path == "/" then return "/" end
    local parts = {}
    for part in path:gmatch("[^/]+") do table.insert(parts, part) end
    if #parts <= 1 then return "/" end
    table.remove(parts)
    return "/" .. table.concat(parts, "/")
end

function kernel.getFileName(path)
    if not path or path == "/" then return "" end
    local parts = {}
    for part in path:gmatch("[^/]+") do table.insert(parts, part) end
    return parts[#parts] or ""
end

function kernel.joinPath(base, name)
    if base == "/" then return "/" .. name end
    return base .. "/" .. name
end

return kernel
