-- CCOS Program: Text Editor
local D = _G._desktop
local R = _G.ccos_render
local API = _G.ccos_api
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appEdit(fp)
    fp = fp or "/untitled.txt"
    local lines = {}
    local c = API.readFile(fp)
    if c then for l in c:gmatch("[^\n]*") do table.insert(lines,l) end end
    if #lines==0 then lines={""} end
    local cl, cc, sy, sx = 1, 1, 0, 0
    local mod = false
    local wx, wy, ww, wh = D.fitWin(260, 150)
    local w = D.createWindow("Edit: " .. API.getFileName(fp), wx, wy, ww, wh)

    local function ensureHScroll()
        local visibleChars = math.floor((w.cw - 6) / 6)
        if cc > sx + visibleChars then
            sx = cc - visibleChars
        elseif cc <= sx then
            sx = math.max(0, cc - 1)
        end
    end

    w.onDraw = function(win, cx, cy, cw, ch)
        R.drawButton(cx, cy, 36, 14, false)
        R.drawText(cx+2, cy+3, "Save", K.BLACK, K.GRAY)
        local eh = math.floor((ch - 24) / 8)
        local visibleChars = math.floor((cw - 6) / 6)
        for i=1, eh do
            local line = lines[sy + i] or ""
            local display = line:sub(sx + 1, sx + visibleChars)
            R.drawText(cx + 2, cy + 16 + (i-1)*8, display, K.BLACK, K.GRAY)
        end
        if cl > sy and cl <= sy + eh then
            local cy2 = cy + 16 + (cl - sy - 1) * 8
            local cx2 = cx + 2 + (cc - 1 - sx) * 6
            if cx2 >= cx + 2 and cx2 < cx + cw - 4 then
                R.fillRect(cx2, cy2, 6, 8, K.DBLUE)
                local c2 = (lines[cl] or ""):sub(cc, cc)
                R.drawText(cx2, cy2, c2=="" and " " or c2, K.WHITE, K.DBLUE)
            end
        end
        R.drawText(cx + 2, cy + ch - 10, API.getFileName(fp) .. (mod and " *" or ""), K.BLACK, K.GRAY)
    end

    w.onClick = function(win, mx, my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 36 then
                API.writeFile(fp, table.concat(lines, "\n"))
                mod = false
                D.markContentDirty(win)
            end
        end
    end

    w.onKey = function(win, k, ch)
        if ch then
            local l = lines[cl] or ""
            lines[cl] = l:sub(1, cc - 1) .. ch .. l:sub(cc)
            cc = cc + 1
            mod = true
            ensureHScroll()
            D.markContentDirty(win)
        elseif k == keys.backspace then
            if cc > 1 then
                local l = lines[cl] or ""
                lines[cl] = l:sub(1, cc - 2) .. l:sub(cc)
                cc = cc - 1
            elseif cl > 1 then
                local pl = #(lines[cl - 1] or "")
                lines[cl - 1] = (lines[cl - 1] or "") .. (lines[cl] or "")
                table.remove(lines, cl)
                cl = cl - 1
                cc = pl + 1
            end
            mod = true
            ensureHScroll()
            D.markContentDirty(win)
        elseif k == keys.enter then
            local l = lines[cl] or ""
            lines[cl] = l:sub(1, cc - 1)
            table.insert(lines, cl + 1, l:sub(cc))
            cl = cl + 1
            cc = 1
            sx = 0
            mod = true
            D.markContentDirty(win)
        elseif k == keys.up and cl > 1 then
            cl = cl - 1
            cc = math.min(cc, #(lines[cl] or "") + 1)
            if cl <= sy then sy = sy - 1 end
            ensureHScroll()
            D.markContentDirty(win)
        elseif k == keys.down and cl < #lines then
            cl = cl + 1
            cc = math.min(cc, #(lines[cl] or "") + 1)
            local eh = math.floor((win.ch - 16) / 8)
            if cl > sy + eh then sy = sy + 1 end
            ensureHScroll()
            D.markContentDirty(win)
        elseif k == keys.left then
            if cc > 1 then cc = cc - 1
            elseif cl > 1 then cl = cl - 1; cc = #(lines[cl] or "") + 1 end
            ensureHScroll()
            D.markContentDirty(win)
        elseif k == keys.right then
            if cc <= #(lines[cl] or "") then cc = cc + 1
            elseif cl < #lines then cl = cl + 1; cc = 1; sx = 0 end
            ensureHScroll()
            D.markContentDirty(win)
        elseif k == keys.home then
            cc = 1
            sx = 0
            D.markContentDirty(win)
        elseif k == keys["end"] then
            cc = #(lines[cl] or "") + 1
            ensureHScroll()
            D.markContentDirty(win)
        elseif k == keys.escape then
            if mod then API.writeFile(fp, table.concat(lines, "\n")) end
            D.destroyWindow(win)
        end
    end
end

return {
    name = "Editor",
    icon = "edit",
    run = appEdit
}
