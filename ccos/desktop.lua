--[[
    CCOS Desktop — Windows 95 style v3
    ===================================
    Single event loop, no modal blocks, proper window management
]]

local K = _G.kernel

local desktop = {}
desktop.windows = {}
desktop.activeWin = nil
desktop.taskbarH = 20
desktop.startMenuOpen = false
desktop.startBtn = {x = 0, y = 0, w = 54, h = 16}
desktop.clock = ""
desktop.nextWinId = 1
desktop.dirty = true
desktop.mode = "desktop"  -- "desktop" or app name
desktop.appState = {}     -- per-app state

-- ============================================================
-- WINDOW MANAGEMENT
-- ============================================================
function desktop.createWindow(title, cx, cy, cw, ch, onDraw, onKey, onClose)
    local id = desktop.nextWinId
    desktop.nextWinId = desktop.nextWinId + 1
    local win = {
        id = id, title = title or "Window",
        cx = cx or 30, cy = cy or 20,
        cw = cw or 200, ch = ch or 120,
        minW = 80, minH = 60,
        onDraw = onDraw, onKey = onKey, onClose = onClose,
        visible = true, maximized = false, prevState = nil,
        dragging = false, dragOffX = 0, dragOffY = 0, resizing = false,
    }
    table.insert(desktop.windows, win)
    desktop.activeWin = win
    desktop.dirty = true
    return win
end

function desktop.destroyWindow(win)
    for i, w in ipairs(desktop.windows) do
        if w.id == win.id then table.remove(desktop.windows, i); break end
    end
    if desktop.activeWin and desktop.activeWin.id == win.id then
        desktop.activeWin = desktop.windows[#desktop.windows]
    end
    if win.onClose then pcall(win.onClose) end
    desktop.dirty = true
end

function desktop.bringToFront(win)
    for i, w in ipairs(desktop.windows) do
        if w.id == win.id then
            table.remove(desktop.windows, i)
            table.insert(desktop.windows, win)
            desktop.activeWin = win
            desktop.dirty = true
            return
        end
    end
end

function desktop.getWindowAt(mx, my)
    for i = #desktop.windows, 1, -1 do
        local w = desktop.windows[i]
        if w.visible and mx >= w.cx and mx < w.cx + w.cw and my >= w.cy and my < w.cy + w.ch then
            return w
        end
    end
    return nil
end

-- ============================================================
-- DRAWING HELPERS
-- ============================================================
local function drawW95Raised(x, y, w, h)
    if not K.hasGraphics then return end
    K.drawLine(x, y, x+w-1, y, K.PAL.LIGHT_GRAY)
    K.drawLine(x, y, x, y+h-1, K.PAL.LIGHT_GRAY)
    K.drawLine(x+w-1, y, x+w-1, y+h-1, K.PAL.DARK_GRAY)
    K.drawLine(x, y+h-1, x+w-1, y+h-1, K.PAL.DARK_GRAY)
end

local function drawW95Sunken(x, y, w, h)
    if not K.hasGraphics then return end
    K.drawLine(x, y, x+w-1, y, K.PAL.DARK_GRAY)
    K.drawLine(x, y, x, y+h-1, K.PAL.DARK_GRAY)
    K.drawLine(x+w-1, y, x+w-1, y+h-1, K.PAL.LIGHT_GRAY)
    K.drawLine(x, y+h-1, x+w-1, y+h-1, K.PAL.LIGHT_GRAY)
end

local function drawButton(x, y, w, h, pressed)
    if not K.hasGraphics then return end
    K.fillRect(x+2, y+2, w-4, h-4, K.PAL.GRAY)
    if pressed then
        K.drawLine(x, y, x+w-1, y, K.PAL.DARK_GRAY)
        K.drawLine(x, y, x, y+h-1, K.PAL.DARK_GRAY)
        K.drawLine(x+w-1, y, x+w-1, y+h-1, K.PAL.LIGHT_GRAY)
        K.drawLine(x, y+h-1, x+w-1, y+h-1, K.PAL.LIGHT_GRAY)
    else
        drawW95Raised(x, y, w, h)
    end
end

-- ============================================================
-- DRAW WINDOW
-- ============================================================
function desktop.drawWindow(win)
    if not win.visible then return end
    local x, y, w, h = win.cx, win.cy, win.cw, win.ch
    local by = K.h - desktop.taskbarH
    if y + h > by then h = math.max(20, by - y) end

    K.fillRect(x, y, w, h, K.PAL.LIGHT_BG)

    local active = (desktop.activeWin and desktop.activeWin.id == win.id)
    local tcolor = active and K.PAL.W95_TITLE_BLUE or K.PAL.GRAY
    K.fillRect(x, y, w, 16, tcolor)

    K.drawPixelText(x+4, y+4, win.title, active and K.PAL.WHITE or K.PAL.GRAY)

    -- Close [X]
    drawButton(x+w-18, y+1, 16, 14, false)
    K.drawPixelText(x+w-13, y+4, "X", K.PAL.BLACK)
    -- Max []
    drawButton(x+w-36, y+1, 16, 14, false)
    K.drawRect(x+w-32, y+4, 8, 8, K.PAL.BLACK)
    -- Min [-]
    drawButton(x+w-54, y+1, 16, 14, false)
    K.fillRect(x+w-49, y+6, 6, 2, K.PAL.BLACK)

    drawW95Raised(x, y, w, h)
    K.fillRect(x+2, y+17, w-4, h-19, K.PAL.LIGHT_BG)

    if win.onDraw then pcall(win.onDraw, win, x+3, y+18, w-6, h-21) end
end

-- ============================================================
-- DRAW TASKBAR
-- ============================================================
function desktop.drawTaskbar()
    local by = K.h - desktop.taskbarH
    K.fillRect(0, by, K.w, desktop.taskbarH, K.PAL.GRAY)
    K.drawLine(0, by, K.w-1, by, K.PAL.WHITE)

    desktop.startBtn.x = 2; desktop.startBtn.y = by + 2
    drawButton(2, by+2, 54, 16, desktop.startMenuOpen)
    K.drawPixelText(6, by+6, "Start", K.PAL.BLACK)

    local btnX = 60
    for _, win in ipairs(desktop.windows) do
        if not win.visible then goto continue end
        local bw = math.min(100, K.w - btnX - 55)
        if bw < 25 then break end
        local ia = (desktop.activeWin and desktop.activeWin.id == win.id)
        drawButton(btnX, by+3, bw, 14, ia)
        local tt = #win.title > 12 and win.title:sub(1,10)..".." or win.title
        K.drawPixelText(btnX+4, by+6, tt, ia and K.PAL.WHITE or K.PAL.BLACK)
        btnX = btnX + bw + 2
        ::continue::
    end

    local clockW = 44
    drawW95Sunken(K.w-clockW-4, by+3, clockW, 14)
    K.drawPixelText(K.w-clockW, by+6, desktop.clock, K.PAL.BLACK)
end

-- ============================================================
-- DRAW START MENU
-- ============================================================
function desktop.drawStartMenu()
    if not desktop.startMenuOpen then return end
    local mx, my = 2, desktop.startBtn.y - 100
    if my < 1 then my = 1 end
    local mw, mh = 140, 96
    K.fillRect(mx, my, mw, mh, K.PAL.GRAY)
    drawW95Raised(mx, my, mw, mh)
    K.fillRect(mx+2, my+2, 20, mh-4, K.PAL.DARK_BLUE)
    K.drawPixelText(mx+3, my+30, "CC", K.PAL.WHITE)

    local items = {{"File Manager","files"},{"Text Editor","edit"},{"Settings","settings"},{"Shell","shell"},{"Reboot","reboot"},{"Shutdown","shutdown"}}
    local iy = my + 4
    for _, item in ipairs(items) do
        local hover = K.mouse.x >= mx+24 and K.mouse.x < mx+mw-4 and K.mouse.y >= iy and K.mouse.y < iy+12
        if hover then K.fillRect(mx+24, iy, mw-28, 12, K.PAL.DARK_BLUE) end
        K.drawPixelText(mx+28, iy+2, item[1], hover and K.PAL.WHITE or K.PAL.BLACK)
        iy = iy + 14
    end
end

-- ============================================================
-- DRAW DESKTOP
-- ============================================================
function desktop.drawDesktop()
    K.clear()
    local by = K.h - desktop.taskbarH
    K.fillRect(0, 0, K.w, by, K.PAL.W95_DESKTOP)

    -- Desktop icons in grid
    local icons = {{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw, ih = 48, 40
    local cols = math.max(1, math.floor((K.w - 10) / (iw + 10)))
    for i, icon in ipairs(icons) do
        local col = (i-1) % cols
        local row = math.floor((i-1) / cols)
        local ix = 8 + col * (iw+10)
        local iy = 8 + row * (ih+8)
        if iy + ih > by - 4 then break end
        if K.mouse.x >= ix-2 and K.mouse.x < ix+iw+2 and K.mouse.y >= iy-2 and K.mouse.y < iy+ih+2 then
            K.fillRect(ix-2, iy-2, iw+4, ih+4, K.PAL.DARK_BLUE)
        end
        K.fillRect(ix, iy, iw, 24, K.PAL.LIGHT_GRAY)
        drawW95Sunken(ix, iy, iw, 24)
        K.drawPixelText(ix+16, iy+7, icon[1]:sub(1,1), K.PAL.DARK_BLUE)
        K.drawPixelText(ix, iy+28, icon[1], K.PAL.WHITE)
    end

    for _, win in ipairs(desktop.windows) do
        if win.visible then desktop.drawWindow(win) end
    end

    desktop.drawTaskbar()
    desktop.drawStartMenu()
    desktop.dirty = false
end

-- ============================================================
-- MOUSE HANDLING
-- ============================================================
function desktop.handleClick(mx, my, button)
    -- Start menu
    if desktop.startMenuOpen then
        local my2 = desktop.startBtn.y - 100
        if my2 < 1 then my2 = 1 end
        local items = {"files","edit","settings","shell","reboot","shutdown"}
        local iy = my2 + 4
        for i, action in ipairs(items) do
            if mx >= 26 and mx < 138 and my >= iy and my < iy+12 then
                desktop.startMenuOpen = false
                return action
            end
            iy = iy + 14
        end
        desktop.startMenuOpen = false
        return nil
    end

    -- Start button
    if mx >= 2 and mx < 56 and my >= desktop.startBtn.y and my < desktop.startBtn.y+16 then
        desktop.startMenuOpen = true
        return nil
    end

    -- Desktop icons
    local icons = {{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw, ih = 48, 40
    local cols = math.max(1, math.floor((K.w-10)/(iw+10)))
    for i, icon in ipairs(icons) do
        local col = (i-1) % cols
        local row = math.floor((i-1)/cols)
        local ix = 8 + col*(iw+10)
        local iy = 8 + row*(ih+8)
        if mx >= ix-2 and mx < ix+iw+2 and my >= iy-2 and my < iy+ih+2 then
            return icon[2]
        end
    end

    -- Windows
    local win = desktop.getWindowAt(mx, my)
    if win then
        desktop.bringToFront(win)
        if my >= win.cy and my < win.cy+16 then
            if mx >= win.cx+win.cw-18 then desktop.destroyWindow(win); return nil end
            if mx >= win.cx+win.cw-36 and mx < win.cx+win.cw-20 then
                if win.maximized then
                    if win.prevState then win.cx=win.prevState.x; win.cy=win.prevState.y; win.cw=win.prevState.w; win.ch=win.prevState.h; win.prevState=nil end
                    win.maximized = false
                else
                    win.prevState={x=win.cx,y=win.cy,w=win.cw,h=win.ch}
                    win.cx=1; win.cy=1; win.cw=K.w; win.ch=K.h-desktop.taskbarH-1; win.maximized=true
                end
                desktop.dirty = true; return nil
            end
            if mx >= win.cx+win.cw-54 and mx < win.cx+win.cw-38 then
                win.visible = false; desktop.dirty = true; return nil
            end
            if not win.maximized then win.dragging = true; win.dragOffX = mx-win.cx; win.dragOffY = my-win.cy end
            return nil
        end
        if mx >= win.cx+win.cw-8 and my >= win.cy+win.ch-8 and not win.maximized then
            win.resizing = true; return nil
        end
        if win.onClick then pcall(win.onClick, win, mx-win.cx-3, my-win.cy-18) end
    end
    return nil
end

function desktop.handleDrag(mx, my)
    for _, win in ipairs(desktop.windows) do
        if win.dragging then
            win.cx = mx - win.dragOffX; win.cy = my - win.dragOffY
            if win.cy < 1 then win.cy = 1 end
            local by = K.h - desktop.taskbarH
            if win.cy + win.ch > by+1 then win.cy = by - win.ch + 2 end
        end
        if win.resizing then
            local nw = mx - win.cx + 1; local nh = my - win.cy + 1
            if nw >= win.minW then win.cw = nw end
            if nh >= win.minH then win.ch = nh end
            if win.cw > K.w - win.cx then win.cw = K.w - win.cx end
            if win.ch > K.h - desktop.taskbarH - win.cy then win.ch = K.h - desktop.taskbarH - win.cy end
        end
    end
end

function desktop.handleMouseUp()
    for _, win in ipairs(desktop.windows) do win.dragging = false; win.resizing = false end
end

function desktop.handleKey(key, char)
    if desktop.activeWin and desktop.activeWin.onKey then
        pcall(desktop.activeWin.onKey, desktop.activeWin, key, char)
    end
end

-- ============================================================
-- MAIN LOOP — single event loop, no modal blocks
-- ============================================================
function desktop.run()
    local running = true
    local timer = os.startTimer(1)
    desktop.drawDesktop()

    while running do
        local event, p1, p2, p3, p4 = os.pullEvent()

        if event == "mouse_click" then
            K.mouse.x = p2; K.mouse.y = p3
            local action = desktop.handleClick(p2, p3, p1)
            desktop.dirty = true

            if action == "reboot" then
                K.clear(); K.drawPixelText(10,10,"Rebooting...",K.PAL.WHITE); sleep(0.5); os.reboot()
            elseif action == "shutdown" then
                running = false
            elseif action == "files" then
                desktop.app_fm_open()
            elseif action == "edit" then
                desktop.app_editor_open()
            elseif action == "settings" then
                desktop.app_settings_open()
            elseif action == "shell" then
                desktop.app_shell_open()
            end

        elseif event == "mouse_drag" then
            K.mouse.x = p2; K.mouse.y = p3
            desktop.handleDrag(p2, p3)
            for _, w in ipairs(desktop.windows) do
                if w.dragging or w.resizing then desktop.dirty = true; break end
            end

        elseif event == "mouse_up" then
            desktop.handleMouseUp()

        elseif event == "key" then
            if p1 == keys.q and desktop.startMenuOpen then
                desktop.startMenuOpen = false; desktop.dirty = true
            else
                desktop.handleKey(p1, nil)
            end

        elseif event == "char" then
            desktop.handleKey(nil, p1)

        elseif event == "timer" then
            local t = os.time and os.time() or 0
            local h = math.floor(t); local m = math.floor((t-h)*60)
            local nc = string.format("%02d:%02d", h, m)
            if nc ~= desktop.clock then desktop.clock = nc; desktop.dirty = true end
            timer = os.startTimer(1)
        end

        if desktop.dirty then desktop.drawDesktop() end
    end

    K.clear(); K.fillRect(0, 0, K.w, K.h, K.PAL.BLACK)
    K.drawPixelText(10, 10, "CCOS shutdown.", K.PAL.WHITE)
end

-- ============================================================
-- APPS — register windows, no modal loops
-- ============================================================

function desktop.app_fm_open()
    local path = "/"
    local selected = 1
    local scroll = 0
    local items = {}

    local function refresh()
        local list = fs.list(path)
        table.sort(list)
        items = {}
        if path ~= "/" then table.insert(items, "..") end
        for _, item in ipairs(list) do
            local fp = path == "/" and ("/" .. item) or (path .. "/" .. item)
            table.insert(items, fs.isDir(fp) and ("/" .. item) or item)
        end
        if #items == 0 then items = {"(empty)"} end
        if selected > #items then selected = #items end
        if selected < 1 then selected = 1 end
    end
    refresh()

    desktop.createWindow("File Manager", 30, 25, 220, 130,
        function(w, cx, cy, cw, ch)
            local listH = math.floor((ch-20)/8)
            for i = 1, listH do
                local idx = scroll + i
                local item = items[idx]
                if not item then break end
                local iy = cy + (i-1)*8
                if idx == selected then
                    K.fillRect(cx, iy-1, cw, 9, K.PAL.DARK_BLUE)
                    K.drawPixelText(cx+2, iy, item, K.PAL.WHITE)
                else
                    K.drawPixelText(cx+2, iy, item, K.PAL.BLACK)
                end
            end
            K.fillRect(cx, cy+ch-12, cw, 10, K.PAL.GRAY)
            K.drawPixelText(cx+2, cy+ch-10, " " .. path, K.PAL.BLACK)
        end,
        function(w, key, char)
            if key == keys.up and selected > 1 then
                selected = selected - 1
                if selected <= scroll then scroll = scroll - 1 end
            elseif key == keys.down and selected < #items then
                selected = selected + 1
                local lh = math.floor((w.ch-20)/8)
                if selected > scroll + lh then scroll = scroll + 1 end
            elseif key == keys.enter then
                local item = items[selected]
                if not item then return end
                if item == ".." then path = K.getDir(path); selected = 1; scroll = 0; refresh()
                elseif item:sub(1,1) == "/" then
                    local np = path == "/" and item or (path..item)
                    if fs.isDir(np) then path = np; selected = 1; scroll = 0; refresh() end
                else
                    local fp = path=="/" and ("/"..item) or (path.."/"..item)
                    desktop.app_editor_open(fp)
                end
            elseif key == keys.backspace then path = K.getDir(path); selected = 1; scroll = 0; refresh()
            elseif key == keys.f5 then refresh()
            elseif key == keys.escape or key == keys.q then desktop.destroyWindow(w)
            end
        end
    )
end

function desktop.app_editor_open(filePath)
    filePath = filePath or "/untitled.txt"
    local lines = {}
    local content = K.readFile(filePath)
    if content then for line in content:gmatch("[^\n]*") do table.insert(lines, line) end end
    if #lines == 0 then table.insert(lines, "") end
    local cursorLine, cursorCol, scrollY = 1, 1, 0
    local modified = false

    desktop.createWindow("Edit: " .. K.getFileName(filePath), 40, 20, 250, 140,
        function(w, cx, cy, cw, ch)
            local eh = math.floor((ch-16)/8)
            for i = 1, eh do
                local li = scrollY + i
                K.drawPixelText(cx+2, cy+(i-1)*8, lines[li] or "", K.PAL.BLACK)
            end
            if cursorLine > scrollY and cursorLine <= scrollY+eh then
                local cy2 = cy+(cursorLine-scrollY-1)*8
                local cx2 = cx+(cursorCol-1)*6
                if cx2 >= cx and cx2 < cx+cw then
                    K.fillRect(cx2, cy2, 6, 8, K.PAL.DARK_BLUE)
                    local c = (lines[cursorLine] or ""):sub(cursorCol, cursorCol)
                    K.drawPixelText(cx2, cy2, c=="" and " " or c, K.PAL.WHITE)
                end
            end
            K.fillRect(cx, cy+ch-12, cw, 10, K.PAL.GRAY)
            local ms = modified and " [modified]" or ""
            K.drawPixelText(cx+2, cy+ch-10, "Ln "..cursorLine..ms.." | S=Save Q=Quit", K.PAL.BLACK)
        end,
        function(w, key, char)
            if char then
                local l = lines[cursorLine] or ""
                lines[cursorLine] = l:sub(1,cursorCol-1)..char..l:sub(cursorCol)
                cursorCol = cursorCol+1; modified = true
            elseif key == keys.backspace then
                if cursorCol > 1 then
                    local l = lines[cursorLine] or ""
                    lines[cursorLine] = l:sub(1,cursorCol-2)..l:sub(cursorCol)
                    cursorCol = cursorCol-1; modified = true
                elseif cursorLine > 1 then
                    local pl = #lines[cursorLine-1]
                    lines[cursorLine-1] = lines[cursorLine-1]..(lines[cursorLine] or "")
                    table.remove(lines, cursorLine); cursorLine = cursorLine-1; cursorCol = pl+1; modified = true
                end
            elseif key == keys.enter then
                local l = lines[cursorLine] or ""
                lines[cursorLine] = l:sub(1,cursorCol-1)
                table.insert(lines, cursorLine, l:sub(cursorCol))
                cursorLine = cursorLine+1; cursorCol = 1; modified = true
            elseif key == keys.up and cursorLine > 1 then
                cursorLine = cursorLine-1; cursorCol = math.min(cursorCol, #(lines[cursorLine] or "")+1)
                if cursorLine <= scrollY then scrollY = scrollY-1 end
            elseif key == keys.down and cursorLine < #lines then
                cursorLine = cursorLine+1; cursorCol = math.min(cursorCol, #(lines[cursorLine] or "")+1)
                local eh = math.floor((w.ch-16)/8)
                if cursorLine > scrollY+eh then scrollY = scrollY+1 end
            elseif key == keys.left then
                if cursorCol > 1 then cursorCol = cursorCol-1
                elseif cursorLine > 1 then cursorLine = cursorLine-1; cursorCol = #(lines[cursorLine] or "")+1 end
            elseif key == keys.right then
                if cursorCol <= #(lines[cursorLine] or "") then cursorCol = cursorCol+1
                elseif cursorLine < #lines then cursorLine = cursorLine+1; cursorCol = 1 end
            elseif key == keys.home then cursorCol = 1
            elseif key == keys["end"] then cursorCol = #(lines[cursorLine] or "")+1
            elseif key == keys.tab then
                local l = lines[cursorLine] or ""
                lines[cursorLine] = l:sub(1,cursorCol-1).."  "..l:sub(cursorCol)
                cursorCol = cursorCol+2; modified = true
            elseif key == keys.s then
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

function desktop.app_settings_open()
    local lt = os.getComputerLabel and os.getComputerLabel() or "No Label"
    desktop.createWindow("Settings", 50, 30, 180, 100,
        function(w, cx, cy, cw, ch)
            K.drawPixelText(cx+4, cy+4, "Computer Label:", K.PAL.BLACK)
            drawW95Sunken(cx+4, cy+16, cw-8, 12)
            K.drawPixelText(cx+6, cy+18, lt, K.PAL.BLACK)
            K.drawPixelText(cx+4, cy+36, "Display: "..K.w.."x"..K.h, K.PAL.BLACK)
            K.drawPixelText(cx+4, cy+48, "Color: "..(K.isColor and "Yes" or "No"), K.PAL.BLACK)
            K.drawPixelText(cx+4, cy+60, "Graphics: "..(K.hasGraphics and "Yes" or "No"), K.PAL.BLACK)
        end,
        function(w, key)
            if key == keys.escape or key == keys.q then desktop.destroyWindow(w) end
        end
    )
end

function desktop.app_shell_open()
    local output = {"> "}
    local inputLine = ""
    local scrollY = 0

    desktop.createWindow("Shell", 30, 25, 250, 130,
        function(w, cx, cy, cw, ch)
            local ml = math.floor((ch-16)/8)
            for i = 1, ml do
                K.drawPixelText(cx+2, cy+(i-1)*8, output[scrollY+i] or "", K.PAL.BLACK)
            end
            K.fillRect(cx, cy+ch-12, cw, 10, K.PAL.GRAY)
            K.drawPixelText(cx+2, cy+ch-10, "> "..inputLine, K.PAL.BLACK)
        end,
        function(w, key, char)
            if char then inputLine = inputLine .. char
            elseif key == keys.backspace then inputLine = inputLine:sub(1,-2)
            elseif key == keys.enter then
                table.insert(output, "> "..inputLine)
                if inputLine == "exit" then desktop.destroyWindow(w); return end
                local fn, err = load(inputLine, "shell", "t", _G)
                if fn then
                    local ok, res = pcall(fn)
                    if ok then if res ~= nil then table.insert(output, tostring(res)) end
                    else table.insert(output, "Error: "..tostring(res)) end
                else table.insert(output, "Error: "..tostring(err)) end
                inputLine = ""
                local ml = math.floor((w.ch-16)/8)
                if #output > ml then scrollY = #output - ml end
            elseif key == keys.q then desktop.destroyWindow(w)
            end
        end
    )
end

return desktop
