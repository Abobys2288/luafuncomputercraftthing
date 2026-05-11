--[[
    Desktop / Home Screen for CCOS
    ===============================
    Main menu with app launcher, system info, quick actions.
]]

local gui = _G.gui

local desktop = {}

function desktop.getLogo()
    return {
        "  ######   ######   ######  ",
        "  #     #  #     #  #     # ",
        "  #     #  #     #  #     # ",
        "  #     #  #     #  #     # ",
        "  #     #  #     #  #     # ",
        "  #     #  #     #  #     # ",
        "  ######   ######   ######  ",
    }
end

function desktop.getSysInfo()
    local info = {}
    info.os = "CC:Tweaked"
    local v = pcall(function() return os.version() end)
    if v then info.os = v end

    local t = os.time and os.time() or 0
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    info.time = string.format("%02d:%02d", h, m)
    info.day = os.day and os.day() or 0
    info.id = os.getComputerID and os.getComputerID() or "N/A"

    local label = pcall(function() return os.getComputerLabel() end)
    info.label = label or "No Label"

    -- Disk usage
    local totalSpace = 0
    local usedSpace = 0
    local sides = {"top","bottom","left","right","front","back"}
    for _, s in ipairs(sides) do
        local ok, p = pcall(peripheral.wrap, s)
        if ok and p and p.getDiskSpaceLimit then
            local ok2, limit = pcall(function() return p.getDiskSpaceLimit() end)
            if ok2 and limit then
                totalSpace = totalSpace + limit
                local ok3, used = pcall(function() return p.getDiskSpaceUsed() end)
                if ok3 and used then usedSpace = usedSpace + used end
            end
        end
    end
    info.diskTotal = totalSpace
    info.diskUsed = usedSpace

    -- Peripherals count
    local pcount = 0
    for _, s in ipairs(sides) do
        local ok, ptype = pcall(peripheral.getType, s)
        if ok and ptype then pcount = pcount + 1 end
    end
    info.peripherals = pcount

    -- Modem count
    local mcount = 0
    for _, s in ipairs(sides) do
        local ok, p = pcall(peripheral.wrap, s)
        if ok and p and p.open then mcount = mcount + 1 end
    end
    info.modems = mcount

    return info
end

function desktop.formatBytes(bytes)
    if bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return bytes .. " B"
    end
end

function desktop.show()
    local w, h = gui.w, gui.h
    local d = gui.display or term

    -- Clear and set black background
    if gui.isColor then d.setBackgroundColor(gui.C.BLACK) end
    d.clear()

    local logo = desktop.getLogo()
    local logoW = #logo[1]
    local logoH = #logo
    local info = desktop.getSysInfo()

    -- Draw logo top-left
    for i, line in ipairs(logo) do
        d.setCursorPos(2, 1 + i)
        gui.setColors(gui.C.CYAN, gui.C.BLACK)
        d.write(line)
    end
    gui.resetColors()

    -- System info to the right of logo
    local infoX = logoW + 5
    local infoY = 2

    local function writeInfo(label, value, color)
        d.setCursorPos(infoX, infoY)
        gui.setColors(color or gui.C.WHITE, gui.C.BLACK)
        d.write(label .. ": " .. value)
        gui.resetColors()
        infoY = infoY + 1
    end

    writeInfo("OS", info.os, gui.C.CYAN)
    writeInfo("ID", tostring(info.id), gui.C.CYAN)
    writeInfo("Label", info.label, gui.C.CYAN)
    writeInfo("Time", info.time, gui.C.CYAN)
    writeInfo("Day", tostring(info.day), gui.C.CYAN)
    writeInfo("Peripherals", tostring(info.peripherals), gui.C.GREEN)
    writeInfo("Modems", tostring(info.modems), gui.C.GREEN)
    if info.diskTotal > 0 then
        writeInfo("Disk", desktop.formatBytes(info.diskUsed) .. " / " .. desktop.formatBytes(info.diskTotal), gui.C.YELLOW)
    end

    -- Separator
    infoY = infoY + 1
    d.setCursorPos(2, infoY)
    gui.setColors(gui.C.GRAY, gui.C.BLACK)
    d.write(string.rep("-", w - 2))
    gui.resetColors()

    -- Menu
    infoY = infoY + 2
    local menuItems = {
        "1. File Manager",
        "2. Text Editor",
        "3. Settings",
        "4. Shell (Lua)",
        "5. Reboot",
        "6. Shutdown",
    }

    for i, item in ipairs(menuItems) do
        d.setCursorPos(4, infoY + i - 1)
        gui.setColors(gui.C.WHITE, gui.C.BLACK)
        d.write(item)
    end
    gui.resetColors()

    -- Footer
    d.setCursorPos(1, h)
    gui.setColors(gui.C.GRAY, gui.C.BLACK)
    d.write(" CCOS v1.0 | 1-6=Select | Q=Quit ")
    gui.resetColors()

    -- Input loop
    while true do
        local event = os.pullEvent()
        if event[1] == "key" then
            local key = event[2]
            if key == keys.q then
                return "quit"
            elseif key == keys["1"] then
                return "files"
            elseif key == keys["2"] then
                return "edit"
            elseif key == keys["3"] then
                return "settings"
            elseif key == keys["4"] then
                return "shell"
            elseif key == keys["5"] then
                return "reboot"
            elseif key == keys["6"] then
                return "shutdown"
            end
        end
    end
end

function desktop.runShell()
    local d = gui.display or term
    if gui.isColor then d.setBackgroundColor(gui.C.BLACK) end
    d.clear()
    d.setCursorPos(1, 1)
    gui.resetColors()
    print("CCOS Lua Shell")
    print("Type 'exit' to return to desktop")
    print("")

    local running = true
    while running do
        write("> ")
        local input = read()
        if input == "exit" or input == "quit" then
            running = false
        elseif input and #input > 0 then
            local fn, err = load(input, "shell", "t", _G)
            if fn then
                local ok, result = pcall(fn)
                if ok then
                    if result ~= nil then
                        print(tostring(result))
                    end
                else
                    print("Error: " .. tostring(result))
                end
            else
                print("Error: " .. tostring(err))
            end
        end
    end
end

function desktop.runEditor()
    local path = gui.inputBox("Text Editor", "File path (or empty for new):", "")
    if path == nil then return end
    if path == "" then path = "/untitled.txt" end

    local content = ""
    if fs.exists(path) then
        local f = fs.open(path, "r")
        if f then content = f.readAll(); f.close() end
    end

    -- Use file manager's edit function
    local fm = _G.fm
    if not fm then
        _G.kernel.clear()
        print("Error: files module not loaded")
        return
    end
    fm.editFile(path, content)
end

function desktop.showSettings()
    local w, h = gui.w, gui.h
    local winW = 40
    local winH = 14
    local winX = math.floor((w - winW) / 2) + 1
    local winY = math.floor((h - winH) / 2) + 1

    local win = gui.createWindow(winX, winY, winW, winH, "Settings")

    gui.addLabel(win, 2, 2, "System Settings", gui.C.CYAN)
    gui.addSeparator(win, 2, 3, winW - 4)

    local labelText = os.getComputerLabel and os.getComputerLabel() or "No Label"
    gui.addLabel(win, 2, 5, "Computer Label: " .. labelText)

    local colorText = gui.isColor and "Yes" or "No"
    gui.addLabel(win, 2, 6, "Color Display: " .. colorText)

    local wText = tostring(gui.w) .. "x" .. tostring(gui.h)
    gui.addLabel(win, 2, 7, "Resolution: " .. wText)

    local sides = {"top","bottom","left","right","front","back"}
    local pcount = 0
    for _, s in ipairs(sides) do
        local ok, ptype = pcall(peripheral.getType, s)
        if ok and ptype then pcount = pcount + 1 end
    end
    gui.addLabel(win, 2, 8, "Peripherals: " .. pcount)

    local mcount = 0
    for _, s in ipairs(sides) do
        local ok, p = pcall(peripheral.wrap, s)
        if ok and p and p.open then mcount = mcount + 1 end
    end
    gui.addLabel(win, 2, 9, "Modems: " .. mcount)

    -- Buttons
    local function setLabel()
        local newLabel = gui.inputBox("Set Label", "New computer label:", labelText)
        if newLabel and #newLabel > 0 then
            os.setComputerLabel(newLabel)
            gui.messageBox("Settings", "Label set to: " .. newLabel)
        end
    end

    local function setModem()
        local sidesList = {}
        for _, s in ipairs(sides) do
            local ok, p = pcall(peripheral.wrap, s)
            if ok and p and p.open then
                table.insert(sidesList, s)
            end
        end
        if #sidesList == 0 then
            gui.messageBox("Modem", "No modems found!")
            return
        end
        local choice = gui.chooseBox("Modem", "Select modem side:", sidesList)
        if choice then
            local side = sidesList[choice]
            local channelStr = gui.inputBox("Modem", "Open channel (0-65535):", "")
            if channelStr then
                local channel = tonumber(channelStr)
                if channel then
                    local p = peripheral.wrap(side)
                    if p then
                        p.open(channel)
                        gui.messageBox("Modem", "Opened channel " .. channel .. " on " .. side)
                    end
                end
            end
        end
    end

    gui.addButton(win, 2, 11, 14, "Set Label", gui.C.WHITE, gui.C.GRAY, setLabel)
    gui.addButton(win, 18, 11, 14, "Modem", gui.C.WHITE, gui.C.GRAY, setModem)

    -- Modal loop
    while win.visible do
        gui.drawAll()
        local event = os.pullEvent()
        if event[1] == "mouse_click" then
            gui.handleClick(win, event[3], event[4])
        elseif event[1] == "key" then
            if event[2] == keys.escape or event[2] == keys.q then
                gui.destroyWindow(win)
            end
            gui.handleKey(win, event[2], nil)
        end
    end
end

return desktop
