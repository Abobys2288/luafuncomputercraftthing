--[[
    CCOS Desktop — Windows 95 style
    ===============================
    Taskbar, Start menu, desktop icons, mouse-driven window management.
]]

local K = _G.kernel

local desktop = {}
desktop.windows = {}
desktop.activeWin = nil
desktop.taskbarH = 24
desktop.startMenuOpen = false
desktop.startBtn = {x=1, y=0, w=60, h=20}  -- y set in draw
desktop.clock = ""
desktop.nextWinId = 1

-- ============================================================
-- WINDOW MANAGEMENT
-- ============================================================
function desktop.createWindow(title, x, y, w, h, onDraw, onKey, onClose)
    local id = desktop.nextWinId
    desktop.nextWinId = desktop.nextWinId + 1
    local win = {
        id = id,
        title = title or "Window",
        x = x or 10,
        y = y or 10,
        w = w or 40,
        h = h or 15,
        minW = 20,
        minH = 8,
        onDraw = onDraw,
        onKey = onKey,
        onClose = onClose,
        visible = true,
        maximized = false,
        prevState = nil, -- {x,y,w,h} before maximize
        dragging = false,
        dragOffX = 0,
        dragOffY = 0,
        resizing = false,
    }
    table.insert(desktop.windows, win)
    desktop.activeWin = win
    return win
end

function desktop.destroyWindow(win)
    for i, w in ipairs(desktop.windows) do
        if w.id == win.id then
            table.remove(desktop.windows, i)
            break
        end
    end
    if desktop.activeWin and desktop.activeWin.id == win.id then
        desktop.activeWin = desktop.windows[#desktop.windows]
    end
    if win.onClose then pcall(win.onClose) end
end

function desktop.bringToFront(win)
    for i, w in ipairs(desktop.windows) do
        if w.id == win.id then
            table.remove(desktop.windows, i)
            table.insert(desktop.windows, win)
            desktop.activeWin = win
            return
        end
    end
end

function desktop.getWindowAt(mx, my)
    -- Check from top (last in table = topmost)
    for i = #desktop.windows, 1, -1 do
        local w = desktop.windows[i]
        if w.visible then
            if mx >= w.x and mx < w.x + w.w and my >= w.y and my < w.y + w.h then
                return w
            end
        end
    end
    return nil
end

-- ============================================================
-- DRAWING
-- ============================================================
function desktop.drawWindow(win)
    if not win.visible then return end
    local x, y, w, h = win.x, win.y, win.w, win.h
    local active = (desktop.activeWin and desktop.activeWin.id == win.id)
    local by = K.h - desktop.taskbarH

    -- Clip to screen
    if y > by then y = by end

    -- Window background
    K.fillRect(x, y, w, h, K.PAL.GRAY)

    -- Title bar
    K.drawW95TitleBar(x, y, w, active)

    -- Title text
    local titleColor = active and K.PAL.WHITE or K.PAL.LIGHT_GRAY
    K.drawPixelText(x + 4, y + 4, win.title, titleColor)

    -- Close button
    K.drawW95CloseButton(x + w - 20, y + 2, false)

    -- Min button
    K.drawW95MinButton(x + w - 38, y + 2, false)

    -- Max button
    K.drawW95MaxButton(x + w - 56, y + 2, false)

    -- 3D border
    K.drawW95Raised(x, y, w, h)

    -- Client area background
    K.fillRect(x + 2, y + 20, w - 4, h - 22, K.PAL.GRAY)

    -- Call window's draw callback
    if win.onDraw then
        pcall(win.onDraw, win, x + 2, y + 20, w - 4, h - 22)
    end
end

function desktop.drawTaskbar()
    local by = K.h - desktop.taskbarH
    local w = K.w

    -- Taskbar background
    K.fillRect(0, by, w, desktop.taskbarH, K.PAL.GRAY)
    -- Top border
    K.drawLine(0, by, w - 1, by, K.PAL.WHITE)
    K.drawLine(0, by + 1, w - 1, by + 1, K.PAL.LIGHT_GRAY)

    -- Start button
    desktop.startBtn.y = by + 2
    local pressed = desktop.startMenuOpen
    K.drawW95Button(desktop.startBtn.x + 1, desktop.startBtn.y, desktop.startBtn.w, desktop.startBtn.h, pressed)
    K.drawPixelText(desktop.startBtn.x + 5, desktop.startBtn.y + 6, "Start", K.PAL.BLACK)

    -- Clock
    local clockW = 50
    local clockX = w - clockW - 4
    K.drawW95Sunken(clockX, by + 3, clockW, 18)
    K.drawPixelText(clockX + 4, by + 7, desktop.clock, K.PAL.BLACK)

    -- Running windows in taskbar
    local btnX = desktop.startBtn.x + desktop.startBtn.w + 4
    for _, win in ipairs(desktop.windows) do
        if not win.visible then goto continue end
        local bw = math.min(w - btnX - clockW - 8, 120)
        if bw < 20 then break end
        local isActive = (desktop.activeWin and desktop.activeWin.id == win.id)
        K.drawW95Button(btnX, by + 3, bw, 18, isActive)
        local titleText = win.title
        if #titleText > 14 then titleText = titleText:sub(1, 12) .. ".." end
        K.drawPixelText(btnX + 4, by + 7, titleText, isActive and K.PAL.WHITE or K.PAL.BLACK)
        btnX = btnX + bw + 2
        ::continue::
    end
end

function desktop.drawStartMenu()
    if not desktop.startMenuOpen then return end
    local mx = desktop.startBtn.x + 1
    local my = K.h - desktop.taskbarH - 120
    local mw = 160
    local mh = 116

    -- Menu background
    K.fillRect(mx, my, mw, mh, K.PAL.GRAY)
    K.drawW95Raised(mx, my, mw, mh)

    -- Sidebar
    K.fillRect(mx + 2, my + 2, 24, mh - 4, K.PAL.DARK_GRAY)
    K.drawPixelText(mx + 4, my + 40, "CCOS", K.PAL.WHITE)

    -- Menu items
    local items = {
        {"File Manager", "files"},
        {"Text Editor", "edit"},
        {"Settings", "settings"},
        {"Shell", "shell"},
        {"Reboot", "reboot"},
        {"Shutdown", "shutdown"},
    }

    local iy = my + 4
    for i, item in ipairs(items) do
        local hover = false
        if K.mouse.x >= mx + 28 and K.mouse.x < mx + mw - 4 and
           K.mouse.y >= iy and K.mouse.y < iy + 14 then
            hover = true
            K.fillRect(mx + 28, iy, mw - 32, 14, K.PAL.DARK_BLUE)
        end
        K.drawPixelText(mx + 32, iy + 3, item[1], hover and K.PAL.WHITE or K.PAL.BLACK)
        iy = iy + 16
    end
end

function desktop.drawDesktop()
    K.clear()

    -- Desktop background (teal W95 style)
    K.fillRect(0, 0, K.w, K.h - desktop.taskbarH, K.PAL.W95_DESKTOP)

    -- Draw desktop icons
    local icons = {
        {name = "File Manager", action = "files", icon = "[F]"},
        {name = "Text Editor", action = "edit", icon = "[E]"},
        {name = "Settings", action = "settings", icon = "[S]"},
        {name = "Shell", action = "shell", icon = "[>]"},
    }

    local ix, iy = 10, 10
    for _, icon in ipairs(icons) do
        -- Icon background
        if K.mouse.x >= ix - 2 and K.mouse.x < ix + 34 and
           K.mouse.y >= iy - 2 and K.mouse.y < iy + 40 then
            K.fillRect(ix - 2, iy - 2, 36, 42, K.PAL.DARK_BLUE)
        end
        -- Icon symbol
        K.fillRect(ix, iy, 32, 24, K.PAL.LIGHT_GRAY)
        K.drawW95Sunken(ix, iy, 32, 24)
        K.drawPixelText(ix + 8, iy + 8, icon.icon, K.PAL.DARK_BLUE)
        -- Label
        K.drawPixelText(ix, iy + 28, icon.name, K.PAL.WHITE)
        iy = iy + 50
    end

    -- Draw windows (bottom to top)
    for _, win in ipairs(desktop.windows) do
        if win.visible then
            desktop.drawWindow(win)
        end
    end

    -- Draw taskbar
    desktop.drawTaskbar()

    -- Draw start menu on top
    desktop.drawStartMenu()
end

-- ============================================================
-- MOUSE HANDLING
-- ============================================================
function desktop.handleClick(mx, my, button)
    -- Start button
    if desktop.startMenuOpen then
        -- Check menu item clicks
        local mx2 = desktop.startBtn.x + 1
        local my2 = K.h - desktop.taskbarH - 120
        local items = {"files", "edit", "settings", "shell", "reboot", "shutdown"}
        local iy = my2 + 4
        for i, action in ipairs(items) do
            if mx >= mx2 + 28 and mx < mx2 + 156 and my >= iy and my < iy + 14 then
                desktop.startMenuOpen = false
                return action
            end
            iy = iy + 16
        end
        -- Click outside menu — close it
        desktop.startMenuOpen = false
        return nil
    end

    if mx >= desktop.startBtn.x + 1 and mx < desktop.startBtn.x + desktop.startBtn.w + 1 and
       my >= desktop.startBtn.y and my < desktop.startBtn.y + desktop.startBtn.h then
        desktop.startMenuOpen = not desktop.startMenuOpen
        return nil
    end

    -- Desktop icons
    local icons = {
        {name = "File Manager", action = "files"},
        {name = "Text Editor", action = "edit"},
        {name = "Settings", action = "settings"},
        {name = "Shell", action = "shell"},
    }
    local ix, iy = 10, 10
    for _, icon in ipairs(icons) do
        if mx >= ix - 2 and mx < ix + 34 and my >= iy - 2 and my < iy + 40 then
            return icon.action
        end
        iy = iy + 50
    end

    -- Check windows (top to bottom)
    local win = desktop.getWindowAt(mx, my)
    if win then
        desktop.bringToFront(win)

        -- Title bar buttons
        local inTitle = (my >= win.y and my < win.y + 20)
        if inTitle then
            -- Close button
            if mx >= win.x + win.w - 20 and mx < win.x + win.w - 4 then
                desktop.destroyWindow(win)
                return nil
            end
            -- Max button
            if mx >= win.x + win.w - 56 and mx < win.x + win.w - 40 then
                if win.maximized then
                    -- Restore
                    if win.prevState then
                        win.x = win.prevState.x
                        win.y = win.prevState.y
                        win.w = win.prevState.w
                        win.h = win.prevState.h
                        win.prevState = nil
                    end
                    win.maximized = false
                else
                    -- Maximize
                    win.prevState = {x = win.x, y = win.y, w = win.w, h = win.h}
                    win.x = 1
                    win.y = 1
                    win.w = K.w
                    win.h = K.h - desktop.taskbarH - 1
                    win.maximized = true
                end
                return nil
            end
            -- Min button (just hide)
            if mx >= win.x + win.w - 38 and mx < win.x + win.w - 22 then
                win.visible = false
                return nil
            end
            -- Drag start
            if not win.maximized then
                win.dragging = true
                win.dragOffX = mx - win.x
                win.dragOffY = my - win.y
            end
            return nil
        end

        -- Resize handle (bottom-right corner)
        if mx >= win.x + win.w - 8 and my >= win.y + win.h - 8 and not win.maximized then
            win.resizing = true
            return nil
        end

        -- Client area click — forward to window
        if win.onClick then
            pcall(win.onClick, win, mx - win.x - 2, my - win.y - 20)
        end
    end

    return nil
end

function desktop.handleDrag(mx, my)
    for _, win in ipairs(desktop.windows) do
        if win.dragging then
            win.x = mx - win.dragOffX
            win.y = my - win.dragOffY
            if win.y < 1 then win.y = 1 end
            local by = K.h - desktop.taskbarH
            if win.y + win.h > by + 1 then win.y = by - win.h + 2 end
            if win.y < 1 then win.y = 1 end
        end
        if win.resizing then
            local newW = mx - win.x + 1
            local newH = my - win.y + 1
            if newW >= win.minW then win.w = newW end
            if newH >= win.minH then win.h = newH end
            local maxW = K.w - win.x
            local maxH = K.h - desktop.taskbarH - win.y
            if win.w > maxW then win.w = maxW end
            if win.h > maxH then win.h = maxH end
        end
    end
end

function desktop.handleMouseUp()
    for _, win in ipairs(desktop.windows) do
        win.dragging = false
        win.resizing = false
    end
end

function desktop.handleKey(key, char)
    if desktop.activeWin and desktop.activeWin.onKey then
        pcall(desktop.activeWin.onKey, desktop.activeWin, key, char)
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
function desktop.run()
    local running = true
    local needsRedraw = true
    local lastMX, lastMY = 0, 0
    local lastClickTime = 0
    local lastClickX, lastClickY = 0, 0

    local function shouldRedraw()
        local mx, my = K.getMousePos()
        if mx ~= lastMX or my ~= lastMY then
            lastMX = mx
            lastMY = my
            return true
        end
        return false
    end

    -- Initial draw
    desktop.drawDesktop()

    -- Timer for periodic redraw (cursor blink, clock)
    local timer = os.startTimer(0.5)

    while running do
        -- Redraw periodically or on mouse move
        if needsRedraw or shouldRedraw() then
            -- Update clock
            local timeUpdated = false
            local t = os.time and os.time() or 0
            local h = math.floor(t)
            local m = math.floor((t - h) * 60)
            local newClock = string.format("%02d:%02d", h, m)
            if newClock ~= desktop.clock then
                desktop.clock = newClock
                timeUpdated = true
            end

            desktop.drawDesktop()
            needsRedraw = false
        end

        local event, p1, p2, p3, p4 = os.pullEvent()

        if event == "mouse_click" then
            K.mouse.x = p2
            K.mouse.y = p3
            local mx, my = p2, p3
            -- Double-click detection
            local now = os.clock and os.clock() or 0
            local isDouble = (now - lastClickTime < 0.4) and math.abs(mx - lastClickX) <= 2 and math.abs(my - lastClickY) <= 2
            lastClickTime = now
            lastClickX = mx
            lastClickY = my

            local action = desktop.handleClick(mx, my, p4)
            needsRedraw = true

            if action == "reboot" then
                K.clear()
                K.drawPixelText(10, 10, "Rebooting...", K.PAL.WHITE)
                sleep(0.5)
                os.reboot()
            elseif action == "shutdown" then
                running = false
            elseif action == "desktop_click" then
                -- Context menu or selection on desktop
            elseif action then
                -- Open apps (mouse action already handled in handleClick)
                if action == "files" then
                    desktop.runFileManager()
                elseif action == "edit" then
                    desktop.runEditor()
                elseif action == "settings" then
                    desktop.runSettings()
                elseif action == "shell" then
                    desktop.runShell()
                end
            end

        elseif event == "mouse_drag" then
            K.mouse.x = p2
            K.mouse.y = p3
            desktop.handleDrag(p2, p3)
            needsRedraw = true

        elseif event == "mouse_up" then
            desktop.handleMouseUp()
            needsRedraw = true

        elseif event == "mouse_scroll" then
            -- Scroll in active window
            if desktop.activeWin and desktop.activeWin.onScroll then
                pcall(desktop.activeWin.onScroll, desktop.activeWin, p2)
            end
            needsRedraw = true

        elseif event == "key" then
            if p1 == keys.q and desktop.startMenuOpen then
                desktop.startMenuOpen = false
                needsRedraw = true
            elseif p1 == keys.f5 then
                needsRedraw = true
            else
                desktop.handleKey(p1, nil)
            end

        elseif event == "char" then
            desktop.handleKey(nil, p1)

        elseif event == "timer" then
            timer = os.startTimer(0.5)
            needsRedraw = true
        end
    end

    K.clear()
    K.fillRect(0, 0, K.w, K.h, K.PAL.BLACK)
    K.drawPixelText(10, 10, "CCOS shutdown. Goodbye!", K.PAL.WHITE)
end

        local event = os.pullEvent()

        if event[1] == "mouse_click" then
            local action = desktop.handleClick(event[3], event[4], event[5])
            needsRedraw = true

            if action == "reboot" then
                K.clear()
                K.drawPixelText(10, 10, "Rebooting...", K.PAL.WHITE)
                sleep(0.5)
                os.reboot()
            elseif action == "shutdown" then
                running = false
            elseif action == "files" then
                desktop.runFileManager()
            elseif action == "edit" then
                desktop.runEditor()
            elseif action == "settings" then
                desktop.runSettings()
            elseif action == "shell" then
                desktop.runShell()
            end

        elseif event[1] == "mouse_drag" then
            desktop.handleDrag(event[3], event[4])
            needsRedraw = true

        elseif event[1] == "mouse_up" then
            desktop.handleMouseUp()
            needsRedraw = true

        elseif event[1] == "key" then
            if event[2] == keys.q and desktop.startMenuOpen then
                desktop.startMenuOpen = false
                needsRedraw = true
            else
                desktop.handleKey(event[2], nil)
            end

        elseif event[1] == "char" then
            desktop.handleKey(nil, event[2])

        elseif event[1] == "timer" then
            needsRedraw = true
        end
    end

    K.clear()
    K.fillRect(0, 0, K.w, K.h, K.PAL.BLACK)
    K.drawPixelText(10, 10, "CCOS shutdown.", K.PAL.WHITE)
end

-- ============================================================
-- APPS
-- ============================================================

function desktop.runFileManager()
    local path = "/"
    local selected = 1
    local scroll = 0
    local items = {}

    local function refresh()
        local list = fs.list(path)
        table.sort(list)
        items = {}
        if path ~= "/" then
            table.insert(items, "..")
        end
        for _, item in ipairs(list) do
            local fullPath = path == "/" and ("/" .. item) or (path .. "/" .. item)
            if fs.isDir(fullPath) then
                table.insert(items, "/" .. item)
            else
                table.insert(items, item)
            end
        end
        if #items == 0 then items = {"(empty)"} end
        if selected > #items then selected = #items end
        if selected < 1 then selected = 1 end
    end

    refresh()

    local win = desktop.createWindow("File Manager - " .. path, 10, 10, 50, 20,
        function(w, cx, cy, cw, ch)
            -- Draw file list
            local listH = ch - 2
            for i = 1, listH do
                local idx = scroll + i
                local item = items[idx]
                if not item then break end
                local iy = cy + i * 8 - 6
                if iy + 6 > cy + ch then break end
                if idx == selected then
                    K.fillRect(cx, iy - 1, cw, 10, K.PAL.DARK_BLUE)
                    K.drawPixelText(cx + 2, iy + 1, item, K.PAL.WHITE)
                else
                    K.drawPixelText(cx + 2, iy + 1, item, K.PAL.BLACK)
                end
            end
            -- Path bar
            K.fillRect(cx, cy + ch - 10, cw, 10, K.PAL.LIGHT_GRAY)
            K.drawPixelText(cx + 2, cy + ch - 8, " " .. path, K.PAL.BLACK)
        end,
        function(w, key, char)
            if key == keys.up then
                if selected > 1 then
                    selected = selected - 1
                    if selected <= scroll then scroll = math.max(0, selected - 1) end
                end
            elseif key == keys.down then
                if selected < #items then
                    selected = selected + 1
                    local listH = (w.h - 22) / 8
                    if selected > scroll + listH then scroll = selected - listH end
                end
            elseif key == keys.enter then
                local item = items[selected]
                if not item then return end
                if item == ".." then
                    path = K.getDir(path)
                    selected = 1
                    scroll = 0
                    refresh()
                elseif item:sub(1, 1) == "/" then
                    local newPath = path == "/" and item or (path .. item)
                    if fs.isDir(newPath) then
                        path = newPath
                        selected = 1
                        scroll = 0
                        refresh()
                    end
                else
                    -- Open file in editor
                    local filePath = path == "/" and ("/" .. item) or (path .. "/" .. item)
                    desktop.runEditor(filePath)
                end
            elseif key == keys.backspace then
                path = K.getDir(path)
                selected = 1
                scroll = 0
                refresh()
            elseif key == keys.f5 then
                refresh()
            end
        end
    )
end

function desktop.runEditor(filePath)
    filePath = filePath or "/untitled.txt"
    local lines = {}
    local content = K.readFile(filePath)
    if content then
        for line in content:gmatch("[^\n]*") do
            table.insert(lines, line)
        end
    end
    if #lines == 0 then table.insert(lines, "") end

    local cursorLine = 1
    local cursorCol = 1
    local scrollY = 0
    local modified = false

    local win = desktop.createWindow("Edit: " .. K.getFileName(filePath), 15, 8, 55, 18,
        function(w, cx, cy, cw, ch)
            local editH = ch - 2
            for i = 1, editH do
                local lineIdx = scrollY + i
                local lineText = lines[lineIdx] or ""
                local iy = cy + (i - 1) * 8
                if iy + 7 > cy + ch then break end
                K.drawPixelText(cx + 2, iy + 1, lineText, K.PAL.BLACK)
            end
            -- Cursor
            if cursorLine > scrollY and cursorLine <= scrollY + editH then
                local cy2 = cy + (cursorLine - scrollY - 1) * 8
                local cx2 = cx + 1 + (cursorCol - 1) * 6
                if cx2 >= cx and cx2 < cx + cw then
                    K.fillRect(cx2, cy2, 6, 8, K.PAL.DARK_BLUE)
                    local ch2 = (lines[cursorLine] or ""):sub(cursorCol, cursorCol)
                    if ch2 == "" then ch2 = " " end
                    K.drawPixelText(cx2 + 1, cy2 + 1, ch2, K.PAL.WHITE)
                end
            end
            -- Status
            K.fillRect(cx, cy + ch - 10, cw, 10, K.PAL.LIGHT_GRAY)
            local modStr = modified and " [modified]" or ""
            K.drawPixelText(cx + 2, cy + ch - 8, "Ln " .. cursorLine .. modStr .. " | Ctrl+S=Save Ctrl+Q=Quit", K.PAL.BLACK)
        end,
        function(w, key, char)
            if char then
                local line = lines[cursorLine] or ""
                lines[cursorLine] = line:sub(1, cursorCol - 1) .. char .. line:sub(cursorCol)
                cursorCol = cursorCol + 1
                modified = true
            elseif key == keys.backspace then
                if cursorCol > 1 then
                    local line = lines[cursorLine] or ""
                    lines[cursorLine] = line:sub(1, cursorCol - 2) .. line:sub(cursorCol)
                    cursorCol = cursorCol - 1
                    modified = true
                elseif cursorLine > 1 then
                    local prevLen = #lines[cursorLine - 1]
                    lines[cursorLine - 1] = lines[cursorLine - 1] .. (lines[cursorLine] or "")
                    table.remove(lines, cursorLine)
                    cursorLine = cursorLine - 1
                    cursorCol = prevLen + 1
                    modified = true
                end
            elseif key == keys.enter then
                local line = lines[cursorLine] or ""
                lines[cursorLine] = line:sub(1, cursorCol - 1)
                table.insert(lines, cursorLine, line:sub(cursorCol))
                cursorLine = cursorLine + 1
                cursorCol = 1
                modified = true
            elseif key == keys.up then
                if cursorLine > 1 then
                    cursorLine = cursorLine - 1
                    cursorCol = math.min(cursorCol, #(lines[cursorLine] or "") + 1)
                    if cursorLine <= scrollY then scrollY = math.max(0, cursorLine - 1) end
                end
            elseif key == keys.down then
                if cursorLine < #lines then
                    cursorLine = cursorLine + 1
                    cursorCol = math.min(cursorCol, #(lines[cursorLine] or "") + 1)
                    local editH = (w.h - 22) / 8
                    if cursorLine > scrollY + editH then scrollY = cursorLine - editH end
                end
            elseif key == keys.left then
                if cursorCol > 1 then cursorCol = cursorCol - 1
                elseif cursorLine > 1 then cursorLine = cursorLine - 1; cursorCol = #(lines[cursorLine] or "") + 1 end
            elseif key == keys.right then
                if cursorCol <= #(lines[cursorLine] or "") then cursorCol = cursorCol + 1
                elseif cursorLine < #lines then cursorLine = cursorLine + 1; cursorCol = 1 end
            elseif key == keys.home then cursorCol = 1
            elseif key == keys["end"] then cursorCol = #(lines[cursorLine] or "") + 1
            elseif key == keys.tab then
                local line = lines[cursorLine] or ""
                lines[cursorLine] = line:sub(1, cursorCol - 1) .. "  " .. line:sub(cursorCol)
                cursorCol = cursorCol + 2
                modified = true
            elseif key == keys.s then -- Ctrl+S simplified
                local f = fs.open(filePath, "w")
                if f then f.write(table.concat(lines, "\n")); f.close(); modified = false end
            elseif key == keys.q then
                if modified then
                    local f = fs.open(filePath, "w")
                    if f then f.write(table.concat(lines, "\n")); f.close() end
                end
                desktop.destroyWindow(w)
            end
        end
    )
end

function desktop.runSettings()
    local labelText = os.getComputerLabel and os.getComputerLabel() or "No Label"

    local win = desktop.createWindow("Settings", 20, 12, 40, 14,
        function(w, cx, cy, cw, ch)
            K.drawPixelText(cx + 2, cy + 2, "Computer Label:", K.PAL.BLACK)
            K.drawW95Sunken(cx + 2, cy + 12, cw - 4, 10)
            K.drawPixelText(cx + 4, cy + 14, labelText, K.PAL.BLACK)

            K.drawPixelText(cx + 2, cy + 28, "Display: " .. K.w .. "x" .. K.h, K.PAL.BLACK)
            K.drawPixelText(cx + 2, cy + 38, "Color: " .. (K.isColor and "Yes" or "No"), K.PAL.BLACK)
            K.drawPixelText(cx + 2, cy + 48, "Graphics: " .. (K.hasGraphics and "Yes" or "No"), K.PAL.BLACK)
        end,
        function(w, key, char)
            if key == keys.escape or key == keys.q then
                desktop.destroyWindow(w)
            end
        end
    )
end

function desktop.runShell()
    -- Simple shell in a window
    local output = {"> "}
    local inputLine = ""
    local scrollY = 0

    local win = desktop.createWindow("Shell", 10, 8, 55, 18,
        function(w, cx, cy, cw, ch)
            local lineH = 8
            local maxLines = math.floor(ch / lineH) - 1
            for i = 1, maxLines do
                local idx = scrollY + i
                local line = output[idx] or ""
                local iy = cy + (i - 1) * lineH
                if iy + 7 > cy + ch then break end
                K.drawPixelText(cx + 2, iy + 1, line, K.PAL.BLACK)
            end
            -- Input line
            K.fillRect(cx, cy + ch - 10, cw, 10, K.PAL.LIGHT_GRAY)
            K.drawPixelText(cx + 2, cy + ch - 8, "> " .. inputLine, K.PAL.BLACK)
        end,
        function(w, key, char)
            if char then
                inputLine = inputLine .. char
            elseif key == keys.backspace then
                inputLine = inputLine:sub(1, -2)
            elseif key == keys.enter then
                table.insert(output, "> " .. inputLine)
                if inputLine == "exit" then
                    desktop.destroyWindow(w)
                    return
                end
                -- Try to execute
                local fn, err = load(inputLine, "shell", "t", _G)
                if fn then
                    local ok, result = pcall(fn)
                    if ok then
                        if result ~= nil then table.insert(output, tostring(result)) end
                    else
                        table.insert(output, "Error: " .. tostring(result))
                    end
                else
                    table.insert(output, "Error: " .. tostring(err))
                end
                inputLine = ""
                local lineH = 8
                local maxLines = math.floor((w.h - 22) / lineH) - 1
                if #output > maxLines then scrollY = #output - maxLines end
            elseif key == keys.q then
                desktop.destroyWindow(w)
            end
        end
    )
end

return desktop
