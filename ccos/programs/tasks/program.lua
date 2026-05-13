-- CCOS Program: Task Manager
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appTasks()
    local sel = 1
    local scroll = 0
    local wx, wy, ww, wh = D.fitWin(200, 140)
    local w = D.createWindow("Task Manager", wx, wy, ww, wh)

    local function visibleWindows()
        local visible = {}
        for _, win2 in ipairs(D.windows) do
            if win2.visible and not win2.minimized then table.insert(visible, win2) end
        end
        return visible
    end

    w.onDraw = function(win, cx, cy, cw, ch)
        local visible = visibleWindows()

        local lh = math.floor((ch-20)/8)
        for i = 1, lh do
            local idx = scroll + i
            local win2 = visible[idx]
            if not win2 then break end
            local iy = cy + 4 + (i-1)*8
            local active = D.activeWin and D.activeWin.id == win2.id
            local text = win2.title .. " (ID:" .. win2.id .. ")"
            if idx == sel then
                R.fillRect(cx+2, iy-1, cw-4, 9, K.DBLUE)
                R.drawText(cx+4, iy, text, K.WHITE, K.DBLUE)
            else
                R.drawText(cx+4, iy, text, active and K.DBLUE or K.BLACK, K.GRAY)
            end
        end

        R.drawText(cx+2, cy+ch-10, "Enter=focus  Del=close  Esc=exit", K.BLACK, K.GRAY)
    end

    w.onClick = function(win, mx, my)
        local visible = visibleWindows()

        local lh = math.floor((win.ch-20)/8)
        for i = 1, lh do
            local idx = scroll + i
            local iy = 4 + (i-1)*8
            if my >= iy-1 and my < iy+8 then
                sel = idx
                local win2 = visible[sel]
                if win2 then D.bringToFront(win2) end
                D.markContentDirty(win)
                return
            end
        end
    end

    w.onKey = function(win, k, ch)
        local visible = visibleWindows()

        if k == keys.up and sel > 1 then
            sel = sel - 1
            if sel <= scroll then scroll = scroll - 1 end
            D.markContentDirty(win)
        elseif k == keys.down and sel < #visible then
            sel = sel + 1
            local lh = math.floor((win.ch-20)/8)
            if sel > scroll + lh then scroll = scroll + 1 end
            D.markContentDirty(win)
        elseif k == keys.enter then
            local win2 = visible[sel]
            if win2 then D.bringToFront(win2) end
            D.markContentDirty(win)
        elseif k == keys.delete then
            local win2 = visible[sel]
            if win2 then D.destroyWindow(win2) end
            sel = math.min(sel, #visible)
            D.markDirty()
        end
    end

    w.onScroll = function(win, dir)
        local visible = visibleWindows()
        local lh = math.max(1, math.floor((win.ch - 20) / 8))
        local maxScroll = math.max(0, #visible - lh)
        if dir < 0 then scroll = math.max(0, scroll - 3)
        else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#visible, math.max(sel, scroll + 1)))
        D.markContentDirty(win)
    end
end

return {
    name = "Task Manager",
    icon = "tasks",
    run = appTasks
}
