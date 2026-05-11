--[[
    fastfetch for CC:Tweaked v2
    - adaptive terminal / monitor
    - safe pcall on every peripheral call
    - color when available
    - watch mode with Q to quit
    - compact aligned output
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

local function writeCenter(d, y, text, w)
    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end
    d.setCursorPos(x, y)
    d.write(text)
end

local function writeLine(d, y, label, value, w)
    local line = ""
    if label and #label > 0 then
        line = label .. ": " .. value
    else
        line = value
    end
    if #line > w then
        line = line:sub(1, w)
    end
    d.setCursorPos(1, y)
    d.clearLine()
    d.write(line)
end

local function writeSeparator(d, y, w)
    d.setCursorPos(1, y)
    d.clearLine()
    local sep = string.rep("-", w)
    d.write(sep)
end

local function collectInfo()
    local info = {}

    -- OS
    info.os = "CC:Tweaked"
    local v = pcallWrap(os.version)
    if v then info.os = v end

    -- Time
    local t = pcallWrap(os.time) or 0
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    info.time = string.format("%02d:%02d", h, m)

    -- Day
    info.day = pcallWrap(os.day) or 0

    -- Computer ID
    info.id = pcallWrap(os.getComputerID) or "N/A"

    -- Label
    local label = pcallWrap(os.getComputerLabel)
    info.label = label or "No Label"

    -- Fuel
    info.fuel = safeTurtleCall("getFuelLevel") or 0
    info.fuelMax = safeTurtleCall("getFuelLimit") or 0
    info.isTurtle = turtle ~= nil

    -- Peripherals
    info.peripherals = {}
    local pnames = pcallWrap(peripheral.getNames) or {}
    for _, name in ipairs(pnames) do
        local ptype = pcallWrap(function() return peripheral.getType(name) end)
        if ptype then
            table.insert(info.peripherals, {name = name, type = ptype})
        end
    end

    -- Inventory
    info.invUsed = 0
    info.invTotal = 0
    info.invItems = {}
    if turtle then
        for i = 1, 16 do
            local detail = pcallWrap(function() return turtle.getItemDetail(i) end)
            if detail then
                info.invUsed = info.invUsed + 1
                info.invTotal = info.invTotal + detail.count
                table.insert(info.invItems, string.format("  [%d] %s x%d", i, detail.name, detail.count))
            end
        end
    end

    -- Disk
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

    -- Color support
    info.isColor = term.isColor and term.isColor() or false

    return info
end

local function draw(d, w, h, info)
    d.clear()
    d.setCursorPos(1, 1)

    local y = 1

    -- Header
    if info.isColor then
        setColors(d, C.WHITE, C.BLACK)
    end
    writeCenter(d, y, "===========================", w)
    y = y + 1
    writeCenter(d, y, "   FASTFETCH CC:TWEAKED   ", w)
    y = y + 1
    writeCenter(d, y, "===========================", w)
    y = y + 1
    resetColors(d)

    y = y + 1

    -- System info
    if info.isColor then setColors(d, C.YELLOW, C.BLACK) end
    writeLine(d, y, "OS", info.os, w)
    y = y + 1
    writeLine(d, y, "ID", tostring(info.id), w)
    y = y + 1
    writeLine(d, y, "Label", info.label, w)
    y = y + 1
    writeLine(d, y, "Time", info.time, w)
    y = y + 1
    writeLine(d, y, "Day", tostring(info.day), w)
    y = y + 1
    writeLine(d, y, "Color", info.isColor and "Yes" or "No", w)
    y = y + 1
    resetColors(d)

    -- Fuel
    if info.isTurtle then
        y = y + 1
        if info.isColor then setColors(d, C.YELLOW, C.BLACK) end
        writeLine(d, y, "Fuel", tostring(info.fuel), w)
        y = y + 1
        if info.fuelMax > 0 then
            local pct = math.floor((info.fuel / info.fuelMax) * 100)
            local barLen = math.floor(w * 0.3)
            local filled = math.floor(barLen * pct / 100)
            local bar = "[" .. string.rep("=", filled) .. string.rep(" ", barLen - filled) .. "]"
            writeLine(d, y, "Fuel Bar", bar .. " " .. pct .. "%", w)
            y = y + 1
        end
        resetColors(d)
    end

    -- Peripherals
    y = y + 1
    if info.isColor then setColors(d, C.GREEN, C.BLACK) end
    writeSeparator(d, y, w)
    y = y + 1
    writeLine(d, y, "Peripherals", "#" .. #info.peripherals, w)
    y = y + 1
    resetColors(d)
    for _, p in ipairs(info.peripherals) do
        writeLine(d, y, "  " .. p.name, p.type, w)
        y = y + 1
        if y >= h - 3 then break end
    end

    -- Inventory
    if info.isTurtle then
        y = y + 1
        if info.isColor then setColors(d, C.GREEN, C.BLACK) end
        writeSeparator(d, y, w)
        y = y + 1
        writeLine(d, y, "Inventory", info.invUsed .. "/16 slots, " .. info.invTotal .. " items", w)
        y = y + 1
        resetColors(d)
        for _, s in ipairs(info.invItems) do
            writeLine(d, y, "", s, w)
            y = y + 1
            if y >= h - 3 then break end
        end
    end

    -- Disks
    if #info.disks > 0 then
        y = y + 1
        if info.isColor then setColors(d, C.GREEN, C.BLACK) end
        writeSeparator(d, y, w)
        y = y + 1
        writeLine(d, y, "Disks", "#" .. #info.disks, w)
        y = y + 1
        resetColors(d)
        for _, disk in ipairs(info.disks) do
            writeLine(d, y, "  " .. disk.side, disk.label .. " (ID: " .. tostring(disk.id) .. ")", w)
            y = y + 1
            if y >= h - 3 then break end
        end
    end

    -- Footer
    y = h - 1
    if info.isColor then setColors(d, C.GRAY, C.BLACK) end
    writeCenter(d, y, "Press Q to exit | R to refresh", w)
    resetColors(d)
end

local function main()
    local d, w, h = getDisplay()
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

    d.clear()
    d.setCursorPos(1, 1)
    resetColors(d)
    print("Fastfetch exited.")
end

main()
