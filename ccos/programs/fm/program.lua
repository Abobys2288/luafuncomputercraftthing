-- CCOS Program: File Manager
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=19,RED=11,DESKTOP=30}

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or text, fg, bg) end
end

local function button(x, y, w, text)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, text, K.BLACK, K.GRAY, w - 8) end
end

local function join(base, name)
    if not base or base == "/" then return "/" .. name end
    return base .. "/" .. name
end

local function parent(path)
    if not path or path == "/" then return "/" end
    return API.getDir(path)
end

local function appFM()
    local path = "/"
    local history = {}
    local sel = 1
    local scroll = 0
    local items = {}
    local status = "Ready"

    local function selected()
        return items[sel]
    end

    local function fullPath(it)
        if not it or it.name == ".." then return parent(path) end
        return join(path, it.name)
    end

    local function refresh()
        local ok, list = pcall(fs.list, path)
        if not ok or not list then
            status = "Cannot open " .. path
            path = "/"
            list = fs.list(path) or {}
        end
        table.sort(list, function(a, b)
            local ap, bp = join(path, a), join(path, b)
            local ad, bd = fs.isDir(ap), fs.isDir(bp)
            if ad ~= bd then return ad end
            return a:lower() < b:lower()
        end)

        items = {}
        if path ~= "/" then table.insert(items, {name="..", kind="Folder", size="", up=true}) end
        for _, name in ipairs(list) do
            local fp = join(path, name)
            local isDir = fs.isDir(fp)
            local size = ""
            if not isDir then
                local okSize, got = pcall(fs.getSize, fp)
                size = okSize and tostring(got) or "?"
            end
            table.insert(items, {name=name, kind=isDir and "Folder" or "File", size=size, dir=isDir})
        end
        if #items == 0 then items = {{name="(empty)", kind="", size="", empty=true}} end
        sel = math.max(1, math.min(sel, #items))
        scroll = math.max(0, math.min(scroll, math.max(0, #items - 1)))
        status = #items .. " item(s)"
    end

    local function openFile(filePath)
        if fs.isDir(filePath) then
            table.insert(history, path)
            path = filePath
            sel, scroll = 1, 0
            refresh()
            D.markDirty()
            return
        end

        local ext = (filePath:match("%.([^%.]+)$") or ""):lower()
        local targetIcon = "edit"
        if ext == "nfp" or ext == "nfp256" then targetIcon = "img" end
        for _, prog in ipairs(D.programs) do
            if prog.icon == targetIcon then prog.run(filePath); return end
        end
        status = "No opener for " .. ext
        D.markContentDirty(D.activeWin)
    end

    refresh()
    local wx, wy, ww, wh = API.fitWindow(320, 190)
    local w = API.window("File Manager", wx, wy, ww, wh)
    if not w then return end

    local toolbar = {
        {id="back", label="Back", w=38},
        {id="up", label="Up", w=28},
        {id="new", label="New", w=34},
        {id="dir", label="Folder", w=48},
        {id="rename", label="Rename", w=52},
        {id="delete", label="Delete", w=46},
        {id="refresh", label="Refresh", w=52},
    }

    local function toolbarHit(mx, my)
        if my < 0 or my >= 14 then return nil end
        local x = 0
        for _, b in ipairs(toolbar) do
            if x + b.w <= w.cw - 6 then
                if mx >= x and mx < x + b.w then return b.id end
                x = x + b.w + 2
            end
        end
        return nil
    end

    local function goUp()
        if path ~= "/" then table.insert(history, path); path = parent(path); sel, scroll = 1, 0; refresh(); D.markDirty() end
    end

    local function goBack()
        local prev = table.remove(history)
        if prev and fs.isDir(prev) then path = prev; sel, scroll = 1, 0; refresh(); D.markDirty() end
    end

    local function createFile()
        D.inputDialog("New File", "Filename:", "newfile.txt", function(name)
            if name and name ~= "" then
                local fp = join(path, name)
                if fs.exists(fp) then status = "Already exists" else API.writeFile(fp, "") end
                refresh(); D.markDirty()
            end
        end)
    end

    local function createFolder()
        D.inputDialog("New Folder", "Folder name:", "newdir", function(name)
            if name and name ~= "" then
                local fp = join(path, name)
                if fs.exists(fp) then status = "Already exists" else fs.makeDir(fp) end
                refresh(); D.markDirty()
            end
        end)
    end

    local function renameSelected()
        local it = selected()
        if not it or it.empty or it.up then return end
        D.inputDialog("Rename", "New name:", it.name, function(name)
            if name and name ~= "" and name ~= it.name then
                local src, dst = fullPath(it), join(path, name)
                if fs.exists(dst) then status = "Target exists" else fs.move(src, dst); status = "Renamed" end
                refresh(); D.markDirty()
            end
        end)
    end

    local function deleteSelected()
        local it = selected()
        if not it or it.empty or it.up then return end
        local fp = fullPath(it)
        if fs.exists(fp) then fs.delete(fp); status = "Deleted: " .. it.name end
        sel = math.max(1, sel - 1)
        refresh(); D.markDirty()
    end

    local function activate()
        local it = selected()
        if not it or it.empty then return end
        if it.up then goUp() else openFile(fullPath(it)) end
    end

    local function selectAt(my)
        local listY = 38
        local rows = math.max(1, math.floor((w.ch - 21 - listY - 20) / 8))
        for i = 1, rows do
            local iy = listY + (i - 1) * 8
            if my >= iy and my < iy + 8 then
                sel = math.min(#items, scroll + i)
                return true
            end
        end
        return false
    end

    local function showContext(mx, my)
        selectAt(my)
        local it = selected()
        local canFile = it and not it.empty and not it.up
        local menu = {
            {"Open", function() activate() end},
            {nil, nil},
            {"New File", function() createFile() end},
            {"New Folder", function() createFolder() end},
            {nil, nil},
            {"Rename", function() if canFile then renameSelected() end end},
            {"Delete", function() if canFile then deleteSelected() end end},
            {nil, nil},
            {"Refresh", function() refresh(); D.markDirty() end},
        }
        local itemH = 14
        local mw = 104
        local mh = #menu * itemH + 4
        local ax = w.cx + 3 + mx
        local ay = w.cy + 18 + my
        local by = R.h - D.taskbarH
        if ax + mw > R.w then ax = R.w - mw end
        if ay + mh > by then ay = by - mh end
        D.contextMenu = {
            x = math.max(1, ax),
            y = math.max(1, ay),
            w = mw,
            h = mh,
            items = menu,
            itemH = itemH,
        }
        D.markDirty()
    end

    w.onDraw = function(_, cx, cy, cw, ch)
        local tx = cx
        for _, b in ipairs(toolbar) do
            if tx - cx + b.w <= cw then
                button(tx, cy, b.w, b.label)
                tx = tx + b.w + 2
            end
        end

        R.drawW95Sunken(cx, cy + 18, math.max(8, cw), 14)
        drawText(cx + 4, cy + 21, path, K.BLACK, K.GRAY, cw - 8)

        local listY = cy + 38
        local footerY = cy + ch - 10
        local rowH = 8
        local rows = math.max(1, math.floor((footerY - listY - 10) / rowH))
        local nameW = math.max(60, cw - 104)
        local typeX = cx + 6 + nameW
        local sizeX = cx + cw - 44

        R.fillRect(cx, listY - 9, cw, 9, K.LGRAY)
        drawText(cx + 6, listY - 8, "Name", K.BLACK, K.LGRAY, nameW - 2)
        if cw >= 150 then drawText(typeX, listY - 8, "Type", K.BLACK, K.LGRAY, 40) end
        if cw >= 210 then drawText(sizeX, listY - 8, "Size", K.BLACK, K.LGRAY, 40) end

        local hasHover = false
        for i = 1, rows do
            local iy = listY + (i - 1) * rowH
            if D.mouse.x >= cx + 2 and D.mouse.x < cx + cw - 2 and D.mouse.y >= iy and D.mouse.y < iy + rowH then
                hasHover = true
                break
            end
        end

        for i = 1, rows do
            local idx = scroll + i
            local it = items[idx]
            if not it then break end
            local iy = listY + (i - 1) * rowH
            local hover = D.mouse.x >= cx + 2 and D.mouse.x < cx + cw - 2 and D.mouse.y >= iy and D.mouse.y < iy + rowH
            local active = (hasHover and hover) or (not hasHover and idx == sel)
            if active then R.fillRect(cx + 2, iy, cw - 4, rowH, K.DBLUE) end
            local fg, bg = active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY
            local prefix = it.up and "^ " or (it.dir and "[] " or "   ")
            drawText(cx + 6, iy, prefix .. it.name, fg, bg, nameW - 6)
            if cw >= 150 then drawText(typeX, iy, it.kind, fg, bg, 40) end
            if cw >= 210 then drawText(sizeX, iy, it.size, fg, bg, 40) end
        end

        local maxScroll = math.max(0, #items - rows)
        if maxScroll > 0 and cw >= 12 then
            local barH = math.max(8, math.floor((rows / #items) * (rows * rowH)))
            local barY = listY + math.floor(((rows * rowH) - barH) * scroll / maxScroll)
            R.fillRect(cx + cw - 5, barY, 3, barH, K.DGRAY)
        end

        drawText(cx + 4, footerY, status .. "  Enter=open  R=rename  Del=delete", K.DGRAY, K.GRAY, cw - 8)
    end

    w.onClick = function(_, mx, my)
        local hit = toolbarHit(mx, my)
        if hit == "back" then goBack(); return
        elseif hit == "up" then goUp(); return
        elseif hit == "new" then createFile(); return
        elseif hit == "dir" then createFolder(); return
        elseif hit == "rename" then renameSelected(); return
        elseif hit == "delete" then deleteSelected(); return
        elseif hit == "refresh" then refresh(); D.markDirty(); return end

        if selectAt(my) then
            D.markContentDirty(w)
            return
        end
    end

    w.onDoubleClick = function()
        activate()
    end

    w.onRightClick = function(_, mx, my)
        showContext(mx, my)
    end

    w.onKey = function(_, k, ch)
        local rows = math.max(1, math.floor((w.ch - 21 - 58) / 8))
        if k == keys.up and sel > 1 then
            sel = sel - 1; if sel <= scroll then scroll = math.max(0, scroll - 1) end; D.markContentDirty(w)
        elseif k == keys.down and sel < #items then
            sel = sel + 1; if sel > scroll + rows then scroll = scroll + 1 end; D.markContentDirty(w)
        elseif k == keys.pageUp then
            sel = math.max(1, sel - rows); scroll = math.max(0, scroll - rows); D.markContentDirty(w)
        elseif k == keys.pageDown then
            sel = math.min(#items, sel + rows); scroll = math.min(math.max(0, #items - rows), scroll + rows); D.markContentDirty(w)
        elseif k == keys.enter then activate()
        elseif k == keys.backspace then goUp()
        elseif ch == "r" or ch == "R" or k == keys.f2 then renameSelected()
        elseif k == keys.delete then deleteSelected()
        elseif k == keys.f5 then refresh(); D.markDirty()
        elseif k == keys.escape then API.close(w) end
    end

    w.onScroll = function(_, dir)
        local rows = math.max(1, math.floor((w.ch - 21 - 58) / 8))
        local maxScroll = math.max(0, #items - rows)
        if dir < 0 then scroll = math.max(0, scroll - 3)
        else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#items, math.max(sel, scroll + 1)))
        D.markContentDirty(w)
    end
end

return {
    name = "File Manager",
    icon = "files",
    run = appFM
}
