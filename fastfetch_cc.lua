--[[
    fastfetch for CC:Tweaked v3
    - black background, colored text (like real fastfetch)
    - ASCII logo on the left, info on the right
    - adaptive terminal / monitor
    - safe pcall on every peripheral call
    - watch mode with Q to quit
]]

local C = {}
C.WHITE = 1
C.BLACK = 8
C.GRAY = 256
C.LIGHT_GRAY = 2
C.RED = 16384
C.YELLOW = 32
C.GREEN = 8192
C.CYAN = 512
C.BLUE = 2048
C.ORANGE = 4
C.PINK = 16384
C.LIME = 8192
C.PURPLE = 1024
C.BROWN = 4096
C.MAGENTA = 32

local function pcallWrap(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function safeTurtleCall(name)
    if not turtle then return nil end
    return pcallWrap(function() return turtle[name](turtle) end)
end

local function getDisplay()
    local best = term
    local bw, bh = term.getSize()
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, s in ipairs(sides) do
        local ok, m = pcall(peripheral.wrap, s)
        if ok and m and m.getSize then
            pcall(function() m.setTextScale(1) end)
            local w, h = m.getSize()
            if w * h > bw * bh then
                best = m
                bw = w
                bh = h
            end
        end
    end
    return best, bw, bh
end

local function isColorDisplay(d)
    if d.isColor then
        local ok, v = pcall(function() return d.isColor() end)
        if ok and v then return true end
    end
    return term.isColor and term.isColor() or false
end

local function setColors(d, fg, bg)
    if isColorDisplay(d) then
        if d.setTextColor then d.setTextColor(fg) end
        if d.setBackgroundColor then d.setBackgroundColor(bg) end
    end
end

local function resetColors(d)
    setColors(d, C.WHITE, C.BLACK)
end

-- CC logo (like fastfetch distro logos)
local LOGO = {
    "         ######  ######  ",
    "         #     # #     # ",
    "         #     # #     # ",
    "         #     # #     # ",
    "         #     # #     # ",
    "         #     # #     # ",
    "         ######  ######  ",
}

local LOGO_W = 25
local LOGO_H = #LOGO

local function collectInfo()
    local info = {}

    info.os = "CC:Tweaked"
    local v = pcallWrap(os.version)
    if v then info.os = v end

    local t = pcallWrap(os.time) or 0
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    info.time = string.format("%02d:%02d", h, m)

    info.day = pcallWrap(os.day) or 0
    info.id = pcallWrap(os.getComputerID) or "N/A"

    local label = pcallWrap(os.getComputerLabel)
    info.label = label or "No Label"

    info.fuel = safeTurtleCall("getFuelLevel") or 0
    info.fuelMax = safeTurtleCall("getFuelLimit") or 0
    info.isTurtle = turtle ~= nil

    info.peripherals = {}
    local pnames = pcallWrap(peripheral.getNames) or {}
    for _, name in ipairs(pnames) do
        local ptype = pcallWrap(function() return peripheral.getType(name) end)
        if ptype then
            table.insert(info.peripherals, {name = name, type = ptype})
        end
    end

    info.invUsed = 0
    info.invTotal = 0
    info.invItems = {}
    if turtle then
        for i = 1, 16 do
            local detail = pcallWrap(function() return turtle.getItemDetail(i) end)
            if detail then
                info.invUsed = info.invUsed + 1
                info.invTotal = info.invTotal + detail.count
                table.insert(info.invItems, string.format("[%d] %s x%d", i, detail.name, detail.count))
            end
        end
    end

    info.disks = {}
    for _, name in ipairs(pnames) do
        local ptype = pcallWrap(function() return peripheral.getType(name) end)
        if ptype == "drive" then
            local d = pcallWrap(function() return peripheral.wrap(name) end)
            if d then
                local present = pcallWrap(function() return d.isDiskPresent() end)
                if present then
                    local diskLabel = pcallWrap(function() return d.getDiskLabel() end)
                    local diskID = pcallWrap(function() return d.getDiskID() end)
                    table.insert(info.disks, {
                        side = name,
                        label = diskLabel or "N/A",
                        id = diskID or "N/A"
                    })
                end
            end
        end
    end

    info.isColor = term.isColor and term.isColor() or false

    return info
end

local function draw(d, w, h, info)
    -- Fill background black
    if isColorDisplay(d) then
        d.setBackgroundColor(C.BLACK)
    end
    d.clear()

    local y = 1
    local infoX = LOGO_W + 3  -- start info after logo + gap

    -- Draw logo (left side)
    local logoColors = {C.CYAN, C.CYAN, C.CYAN, C.CYAN, C.CYAN, C.CYAN}
    for i = 1, LOGO_H do
        if y + i - 1 > h then break end
        d.setCursorPos(1, y + i - 1)
        if info.isColor then
            setColors(d, logoColors[i] or C.CYAN, C.BLACK)
        end
        d.write(LOGO[i])
    end
    resetColors(d)

    -- Draw info (right side, aligned with logo top)
    local iy = y

    -- Title
    if info.isColor then setColors(d, C.CYAN, C.BLACK) end
    d.setCursorPos(infoX, iy)
    d.write(info.label .. "@CC")
    resetColors(d)
    iy = iy + 1

    -- Separator
    if info.isColor then setColors(d, C.GRAY, C.BLACK) end
    d.setCursorPos(infoX, iy)
    local sep = string.rep("-", math.min(w - infoX + 1, 40))
    d.write(sep)
    resetColors(d)
    iy = iy + 1

    -- System info lines
    local function writeInfo(label, value, color)
        if iy > h - 2 then return end
        if info.isColor then setColors(d, color or C.WHITE, C.BLACK) end
        d.setCursorPos(infoX, iy)
        local line = label .. ": " .. value
        if #line > w - infoX + 1 then
            line = line:sub(1, w - infoX + 1)
        end
        d.write(line)
        resetColors(d)
        iy = iy + 1
    end

    writeInfo("OS", info.os, C.CYAN)
    writeInfo("ID", tostring(info.id), C.CYAN)
    writeInfo("Time", info.time, C.CYAN)
    writeInfo("Day", tostring(info.day), C.CYAN)
    writeInfo("Color", info.isColor and "Yes" or "No", C.CYAN)

    if info.isTurtle then
        iy = iy + 1
        writeInfo("Fuel", tostring(info.fuel), C.YELLOW)
        if info.fuelMax > 0 then
            local pct = math.floor((info.fuel / info.fuelMax) * 100)
            local barLen = math.max(10, w - infoX - 10)
            local filled = math.floor(barLen * pct / 100)
            local bar = "[" .. string.rep("=", filled) .. string.rep("-", barLen - filled) .. "] " .. pct .. "%"
            writeInfo("Fuel", bar, C.YELLOW)
        end
    end

    -- Peripherals
    if #info.peripherals > 0 then
        iy = iy + 1
        if info.isColor then setColors(d, C.GRAY, C.BLACK) end
        d.setCursorPos(infoX, iy)
        d.write(sep)
        resetColors(d)
        iy = iy + 1
        writeInfo("Peripherals", "#" .. #info.peripherals, C.GREEN)
        for _, p in ipairs(info.peripherals) do
            if iy > h - 3 then break end
            writeInfo("  " .. p.name, p.type, C.GREEN)
        end
    end

    -- Inventory
    if info.isTurtle and #info.invItems > 0 then
        iy = iy + 1
        if info.isColor then setColors(d, C.GRAY, C.BLACK) end
        d.setCursorPos(infoX, iy)
        d.write(sep)
        resetColors(d)
        iy = iy + 1
        writeInfo("Inventory", info.invUsed .. "/16, " .. info.invTotal .. " items", C.GREEN)
        for _, s in ipairs(info.invItems) do
            if iy > h - 3 then break end
            writeInfo("", s, C.GREEN)
        end
    end

    -- Disks
    if #info.disks > 0 then
        iy = iy + 1
        if info.isColor then setColors(d, C.GRAY, C.BLACK) end
        d.setCursorPos(infoX, iy)
        d.write(sep)
        resetColors(d)
        iy = iy + 1
        writeInfo("Disks", "#" .. #info.disks, C.GREEN)
        for _, disk in ipairs(info.disks) do
            if iy > h - 3 then break end
            writeInfo("  " .. disk.side, disk.label .. " (ID:" .. tostring(disk.id) .. ")", C.GREEN)
        end
    end

    -- Footer
    if info.isColor then setColors(d, C.GRAY, C.BLACK) end
    d.setCursorPos(1, h)
    d.clearLine()
    local footer = "Press Q to exit | R to refresh"
    d.setCursorPos(math.max(1, math.floor((w - #footer) / 2) + 1), h)
    d.write(footer)
    resetColors(d)
end

local function main()
    local d, w, h = getDisplay()

    -- If screen too small for logo+info side by side, hide logo
    if w < LOGO_W + 30 then
        LOGO = {}
        LOGO_W = 0
        LOGO_H = 0
    end

    local running = true
    local refresh = true

    while running do
        if refresh then
            local info = collectInfo()
            draw(d, w, h, info)
            refresh = false
        end

        local event, param = os.pullEvent()
        if event == "key" then
            if param == keys.q then
                running = false
            else
                refresh = true
            end
        elseif event == "timer" then
            refresh = true
        end
    end

    if isColorDisplay(d) then
        d.setBackgroundColor(C.BLACK)
    end
    d.clear()
    d.setCursorPos(1, 1)
    resetColors(d)
    print("Fastfetch exited.")
end

main()
