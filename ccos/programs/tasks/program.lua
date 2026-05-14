-- CCOS Program: Task Manager
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,GREEN=9,CYAN=7}

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, tostring(text or ""), fg, bg) end
end

local function button(x, y, w, label)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, label, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, label, K.BLACK, K.GRAY, w - 8) end
end

local function appTasks()
    local sel, scroll = 1, 0
    local status = "Ready"
    local startClock = os.clock()
    local rowsCache = {}
    local wx, wy, ww, wh = API.fitWindow(300, 180)
    local w = API.window("Task Manager", wx, wy, ww, wh)
    if not w then return end

    local function buildRows()
        local rows = {}
        for _, win2 in ipairs(D.windows or {}) do
            local state = win2.minimized and "Min" or (win2.visible and "Run" or "Hide")
            if D.activeWin and D.activeWin.id == win2.id then state = "Active" end
            rows[#rows + 1] = {
                kind = "win",
                win = win2,
                id = win2.id,
                title = win2.title or "Window",
                state = state,
                detail = tostring(win2.cw or 0) .. "x" .. tostring(win2.ch or 0) .. " err:" .. tostring(win2.errors or 0),
            }
        end
        for i, _ in ipairs(D.bgTasks or {}) do
            rows[#rows + 1] = {kind="task", id=i, title="Background task " .. i, state="BG", detail="event listener"}
        end
        if #rows == 0 then rows[1] = {kind="empty", id="-", title="No tasks", state="", detail=""} end
        rowsCache = rows
        sel = math.max(1, math.min(sel, #rowsCache))
        return rows
    end

    local function selected()
        return rowsCache[sel]
    end

    local function focusSelected()
        local row = selected()
        if row and row.kind == "win" and row.win then
            row.win.minimized = false
            row.win.visible = true
            D.bringToFront(row.win)
            status = "Focused " .. row.title
        end
        D.markDirty()
    end

    local function closeSelected()
        local row = selected()
        if row and row.kind == "win" and row.win then
            D.destroyWindow(row.win)
            status = "Closed " .. row.title
            if API and API.notify then API.notify("Task Manager", status, "ok", 3) end
        elseif row and row.kind == "task" then
            table.remove(D.bgTasks, row.id)
            status = "Stopped background task " .. row.id
        end
        sel = math.max(1, sel - 1)
        D.markDirty()
    end

    local function toggleMinimize()
        local row = selected()
        if row and row.kind == "win" and row.win then
            row.win.minimized = not row.win.minimized
            status = row.win.minimized and "Minimized" or "Restored"
            D.markDirty()
        end
    end

    local toolbar = {
        {id="focus", label="Focus", w=44},
        {id="min", label="Min/Res", w=56},
        {id="kill", label="Close", w=44},
        {id="gc", label="GC", w=28},
    }

    local function toolbarHit(mx, my)
        if my < 0 or my >= 14 then return nil end
        local x = 0
        for _, b in ipairs(toolbar) do
            if mx >= x and mx < x + b.w then return b.id end
            x = x + b.w + 2
        end
        return nil
    end

    local function runToolbar(id)
        if id == "focus" then focusSelected()
        elseif id == "min" then toggleMinimize()
        elseif id == "kill" then closeSelected()
        elseif id == "gc" then
            collectgarbage("collect")
            status = "GC complete"
            D.markContentDirty(w)
        end
    end

    w.onDraw = function(_, cx, cy, cw, ch)
        local rows = buildRows()
        local tx = cx
        for _, b in ipairs(toolbar) do
            if tx - cx + b.w <= cw then button(tx, cy, b.w, b.label); tx = tx + b.w + 2 end
        end

        local mem = collectgarbage("count")
        local uptime = math.floor(os.clock() - startClock)
        local top = "Win:" .. tostring(#(D.windows or {})) .. " BG:" .. tostring(#(D.bgTasks or {})) .. " Lua:" .. string.format("%.0fKB", mem) .. " Up:" .. uptime .. "s"
        drawText(cx + 4, cy + 18, top, K.BLACK, K.GRAY, cw - 8)

        local listY = cy + 32
        local footerY = cy + ch - 10
        local rowH = 9
        local visible = math.max(1, math.floor((footerY - listY - 4) / rowH))
        drawText(cx + 4, listY - 9, "ID", K.BLACK, K.LGRAY, 26)
        drawText(cx + 34, listY - 9, "State", K.BLACK, K.LGRAY, 44)
        drawText(cx + 82, listY - 9, "Task", K.BLACK, K.LGRAY, math.max(30, cw - 86))

        for i = 1, visible do
            local idx = scroll + i
            local row = rows[idx]
            if not row then break end
            local iy = listY + (i - 1) * rowH
            local active = idx == sel
            if active then R.fillRect(cx + 2, iy, cw - 4, rowH, K.DBLUE) end
            local fg, bg = active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY
            drawText(cx + 4, iy + 1, tostring(row.id), fg, bg, 26)
            drawText(cx + 34, iy + 1, row.state, fg, bg, 44)
            drawText(cx + 82, iy + 1, row.title .. "  " .. row.detail, fg, bg, cw - 86)
        end

        drawText(cx + 4, footerY, status .. "  Enter=focus  M=min  Del=close", K.DGRAY, K.GRAY, cw - 8)
    end

    w.onClick = function(_, mx, my)
        local hit = toolbarHit(mx, my)
        if hit then runToolbar(hit); return end
        local listY = 32
        local footerY = w.ch - 21 - 10
        local rowH = 9
        local visible = math.max(1, math.floor((footerY - listY - 4) / rowH))
        for i = 1, visible do
            local iy = listY + (i - 1) * rowH
            if my >= iy and my < iy + rowH then
                sel = math.min(#rowsCache, scroll + i)
                D.markContentDirty(w)
                return
            end
        end
    end

    w.onDoubleClick = function() focusSelected() end

    w.onKey = function(_, k, ch)
        local rows = buildRows()
        local visible = math.max(1, math.floor((w.ch - 21 - 46) / 9))
        if k == keys.up and sel > 1 then
            sel = sel - 1; if sel <= scroll then scroll = math.max(0, scroll - 1) end; D.markContentDirty(w)
        elseif k == keys.down and sel < #rows then
            sel = sel + 1; if sel > scroll + visible then scroll = scroll + 1 end; D.markContentDirty(w)
        elseif k == keys.enter then focusSelected()
        elseif ch == "m" or ch == "M" then toggleMinimize()
        elseif k == keys.delete then closeSelected()
        elseif ch == "g" or ch == "G" then collectgarbage("collect"); status = "GC complete"; D.markContentDirty(w)
        elseif k == keys.escape then API.close(w) end
    end

    w.onScroll = function(_, dir)
        local rows = buildRows()
        local visible = math.max(1, math.floor((w.ch - 21 - 46) / 9))
        local maxScroll = math.max(0, #rows - visible)
        if dir < 0 then scroll = math.max(0, scroll - 3) else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#rows, math.max(sel, scroll + 1)))
        D.markContentDirty(w)
    end
end

return {name = "Task Manager", icon = "tasks", run = appTasks}
