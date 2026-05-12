-- CCOS Program: File Manager
local D = _G._desktop
local R = _G.ccos_render
local API = _G.ccos_api
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appFM()
    local path = "/"
    local sel = 1
    local scroll = 0
    local items = {}

    local function refresh()
        local l = fs.list(path)
        if not l then l = {} end
        table.sort(l)
        items = {}
        if path ~= "/" then table.insert(items,"..") end
        for _,it in ipairs(l) do
            local fp = path=="/" and ("/"..it) or (path.."/"..it)
            table.insert(items, fs.isDir(fp) and ("/"..it) or it)
        end
        if #items==0 then items={"(empty)"} end
        sel = math.max(1, math.min(sel, #items))
    end

    refresh()
    local wx, wy, ww, wh = D.fitWin(260, 160)
    local w = D.createWindow("File Manager", wx, wy, ww, wh)

    w.onDraw = function(win, cx, cy, cw, ch)
        R.drawButton(cx, cy, 40, 14, false)
        R.drawText(cx+4, cy+3, "New", K.BLACK, K.GRAY)
        R.drawButton(cx+42, cy, 52, 14, false)
        R.drawText(cx+46, cy+3, "New Dir", K.BLACK, K.GRAY)
        R.drawButton(cx+96, cy, 40, 14, false)
        R.drawText(cx+100, cy+3, "Delete", K.BLACK, K.GRAY)
        local lh = math.floor((ch-24)/8)
        -- Pre-scan hover to avoid dual highlight with keyboard selection
        local hasHover = false
        for i=1, lh do
            local idx = scroll + i
            local it = items[idx]
            if not it then break end
            local iy = cy + 16 + (i-1)*8
            if D.mouse.x>=cx+2 and D.mouse.x<cx+cw-2 and D.mouse.y>=iy-1 and D.mouse.y<iy+8 then
                hasHover = true; break
            end
        end
        for i=1, lh do
            local idx = scroll + i
            local it = items[idx]
            if not it then break end
            local iy = cy + 16 + (i-1)*8
            local hover = D.mouse.x>=cx+2 and D.mouse.x<cx+cw-2 and D.mouse.y>=iy-1 and D.mouse.y<iy+8
            local active = (hasHover and hover) or (not hasHover and idx==sel)
            if active then
                R.fillRect(cx+2, iy-1, cw-4, 9, K.DBLUE)
                R.drawText(cx+4, iy, it, K.WHITE, K.DBLUE)
            else
                R.drawText(cx+4, iy, it, K.BLACK, K.GRAY)
            end
        end
        R.drawText(cx+2, cy+ch-10, " "..path, K.BLACK, K.GRAY)
    end

    w.onClick = function(win, mx, my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 40 then
                D.inputDialog("New File", "Enter filename:", "newfile.txt", function(name)
                    if name then
                        local fp = path=="/" and ("/"..name) or (path.."/"..name)
                        API.writeFile(fp, "")
                        refresh()
                        D.markDirty()
                    end
                end)
            elseif mx >= 42 and mx < 94 then
                D.inputDialog("New Folder", "Enter folder name:", "newdir", function(name)
                    if name then
                        local fp = path=="/" and ("/"..name) or (path.."/"..name)
                        fs.makeDir(fp)
                        refresh()
                        D.markDirty()
                    end
                end)
            elseif mx >= 96 and mx < 136 then
                local it = items[sel]
                if it and it ~= ".." then
                    local fp = path=="/" and ("/"..it) or (path.."/"..it)
                    if fs.exists(fp) then fs.delete(fp) end
                    refresh()
                    D.markDirty()
                end
            end
            return
        end
        local lh = math.floor((win.ch-24)/8)
        for i=1, lh do
            local idx = scroll + i
            local iy = 16 + (i-1)*8
            if my >= iy-1 and my < iy+8 then
                sel = idx
                D.markContentDirty(win)
                return
            end
        end
    end

    w.onDoubleClick = function(win, mx, my)
        local lh = math.floor((win.ch-24)/8)
        for i=1, lh do
            local idx = scroll + i
            local iy = 16 + (i-1)*8
            if my >= iy-1 and my < iy+8 then
                local it = items[idx]
                if it then
                    if it == ".." then
                        path = API.getDir(path)
                        sel = 1
                        scroll = 0
                        refresh()
                        D.markDirty()
                    elseif it:sub(1,1)=="/" then
                        local np = path=="/" and it or (path..it)
                        if fs.isDir(np) then
                            path = np
                            sel = 1
                            scroll = 0
                            refresh()
                            D.markDirty()
                        end
                    else
                        for _, prog in ipairs(D.programs) do
                            if prog.icon == "edit" then
                                prog.run(path=="/" and ("/"..it) or (path.."/"..it))
                                break
                            end
                        end
                    end
                end
                return
            end
        end
    end

    w.onKey = function(win, k, ch)
        if k==keys.up and sel>1 then
            sel = sel - 1
            if sel <= scroll then scroll = scroll - 1 end
            D.markContentDirty(win)
        elseif k==keys.down and sel<#items then
            sel = sel + 1
            local lh = math.floor((win.ch-24)/8)
            if sel > scroll + lh then scroll = scroll + 1 end
            D.markContentDirty(win)
        elseif k==keys.enter then
            local it = items[sel]
            if it then
                if it==".." then
                    path = API.getDir(path)
                elseif it:sub(1,1)=="/" then
                    local np = path=="/" and it or (path..it)
                    if fs.isDir(np) then path = np end
                else
                    for _, prog in ipairs(D.programs) do
                        if prog.icon == "edit" then
                            prog.run(path=="/" and ("/"..it) or (path.."/"..it))
                            break
                        end
                    end
                end
                sel = 1
                scroll = 0
                refresh()
                D.markDirty()
            end
        elseif k==keys.backspace then
            path = API.getDir(path)
            sel = 1
            scroll = 0
            refresh()
            D.markDirty()
        elseif k==keys.f5 then
            refresh()
            D.markDirty()
        elseif k==keys.escape then
            D.destroyWindow(win)
        end
    end
end

return {
    name = "File Manager",
    icon = "files",
    run = appFM
}
