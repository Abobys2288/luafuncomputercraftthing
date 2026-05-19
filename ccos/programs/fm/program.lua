-- CCOS Program: File Explorer 2.0
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,GREEN=9,CYAN=7}

local LARGE_WARN = 5 * 1024 * 1024
local IMAGE_EXT = {nfp=true, nfp256=true, nfpc=true, nfpa=true}
local TEXT_EXT = {txt=true, lua=true, cfg=true, log=true, json=true, md=true, ccpkg=true}
local PROTECTED_PATHS = {["/"]=true, ["/rom"]=true, ["/ccos"]=true, ["/www"]=true}

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or tostring(text or ""), fg, bg) end
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
    if API and API.getDir then return API.getDir(path) end
    return path:match("(.+)/[^/]+") or "/"
end

local function fileName(path)
    if API and API.getFileName then return API.getFileName(path) end
    return tostring(path or ""):match("([^/]+)$") or ""
end

local function isProtectedPath(path)
    path = tostring(path or "")
    if PROTECTED_PATHS[path] == true then return true end
    for protected in pairs(PROTECTED_PATHS) do
        if protected ~= "/" and path:sub(1, #protected + 1) == protected .. "/" then
            return true
        end
    end
    return false
end

local function extOf(name)
    return (tostring(name or ""):match("%.([^%.]+)$") or ""):lower()
end

local function formatSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < 1024 then return tostring(bytes) .. " B" end
    if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.2f MB", bytes / (1024 * 1024))
end

local function safeSize(path)
    local ok, size = pcall(fs.getSize, path)
    return ok and tonumber(size) or 0
end

local function typeFor(name, isDir)
    if isDir then return "Folder" end
    local ext = extOf(name)
    if IMAGE_EXT[ext] then return "Image" end
    if TEXT_EXT[ext] then return "Text" end
    if ext == "dfpwm" or ext == "nbs" then return "Audio" end
    if ext == "" then return "File" end
    return ext:upper()
end

local function openProgram(icon, path)
    for _, prog in ipairs(D.programs or {}) do
        if prog.icon == icon then D.safeRun(function() prog.run(path) end); return true end
    end
    return false
end

local function readFirstLine(path)
    local f = fs.open(path, "r")
    if not f then return nil end
    local line = f.readLine()
    f.close()
    return line
end

local function imageInfo(path)
    local first = readFirstLine(path) or ""
    local ext = extOf(path)
    if first:match("^!NFPA") then
        local _, _, w, h, mode, delay, loop, frames, codec = first:find("^!NFPA%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(%S*)")
        if w then return "NFPA " .. w .. "x" .. h .. " x" .. frames .. " " .. mode .. "c " .. (codec ~= "" and codec or "RLE") end
    elseif first:match("^!NFPC") then
        local _, _, w, h, mode, codec = first:find("^!NFPC%s+(%d+)%s+(%d+)%s+(%d+)%s*(%S*)")
        if w then return "NFPC " .. w .. "x" .. h .. " " .. mode .. "c " .. (codec ~= "" and codec or "RLE") end
    elseif ext == "nfp256" and first:match("^[0-9a-fA-F]+$") then
        return "NFP256 width " .. math.floor(#first / 2)
    elseif ext == "nfp" and first ~= "" then
        return "NFP width " .. tostring(#first)
    end
    return IMAGE_EXT[ext] and "CCOS image" or ""
end

local function textPreview(path, limit)
    local lines = {}
    local f = fs.open(path, "r")
    if not f then return lines end
    for _ = 1, limit or 4 do
        local line = f.readLine()
        if not line then break end
        lines[#lines + 1] = line
    end
    f.close()
    return lines
end

local function appFM()
    local path = "/"
    local history = {}
    local sel, scroll = 1, 0
    local items = {}
    local status = "Ready"
    local sortMode = "name"

    local function selected()
        return items[sel]
    end

    local function fullPath(it)
        if not it or it.name == ".." then return parent(path) end
        return join(path, it.name)
    end

    local function setStatus(msg, tone)
        status = tostring(msg or "")
        if tone == "ok" and API and API.notify then API.notify("File Explorer", status, "ok", 3) end
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
            if sortMode == "type" then
                local at, bt = typeFor(a, ad), typeFor(b, bd)
                if at ~= bt then return at < bt end
            elseif sortMode == "size" and not ad and not bd then
                local as, bs = safeSize(ap), safeSize(bp)
                if as ~= bs then return as > bs end
            end
            return a:lower() < b:lower()
        end)

        items = {}
        if path ~= "/" then table.insert(items, {name="..", kind="Folder", size="", up=true, dir=true}) end
        for _, name in ipairs(list) do
            local fp = join(path, name)
            local isDir = fs.isDir(fp)
            local size = isDir and 0 or safeSize(fp)
            table.insert(items, {
                name = name,
                kind = typeFor(name, isDir),
                size = size,
                sizeText = isDir and "" or formatSize(size),
                dir = isDir,
                ext = extOf(name),
            })
        end
        if #items == 0 then items = {{name="(empty)", kind="", sizeText="", empty=true}} end
        sel = math.max(1, math.min(sel, #items))
        scroll = math.max(0, math.min(scroll, math.max(0, #items - 1)))
        status = #items .. " item(s)  sort:" .. sortMode
    end

    local function openFile(filePath, forceEdit)
        if fs.isDir(filePath) then
            table.insert(history, path)
            path = filePath
            sel, scroll = 1, 0
            refresh()
            D.markDirty()
            return
        end

        local ext = extOf(filePath)
        local size = safeSize(filePath)
        if not forceEdit and ext == "ccpkg" then
            if not openProgram("pkg", filePath) then setStatus("No package manager") end
            return
        end
        if not forceEdit and IMAGE_EXT[ext] then
            if size >= LARGE_WARN and API and API.notify then
                API.notify("Image Viewer", "Large file opens in safe preview mode", "info", 5)
            end
            if not openProgram("img", filePath) then setStatus("No image viewer") end
            return
        end
        if not openProgram("edit", filePath) then setStatus("No opener for " .. ext) end
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
                if fs.exists(fp) then setStatus("Already exists") else API.writeFile(fp, ""); setStatus("Created " .. name, "ok") end
                refresh(); D.markDirty()
            end
        end)
    end

    local function createFolder()
        D.inputDialog("New Folder", "Folder name:", "newdir", function(name)
            if name and name ~= "" then
                local fp = join(path, name)
                if fs.exists(fp) then setStatus("Already exists") else fs.makeDir(fp); setStatus("Folder created", "ok") end
                refresh(); D.markDirty()
            end
        end)
    end

    local function renameSelected()
        local it = selected()
        if not it or it.empty or it.up then return end
        if isProtectedPath(fullPath(it)) then setStatus("Protected folder"); return end
        D.inputDialog("Rename", "New name:", it.name, function(name)
            if name and name ~= "" and name ~= it.name then
                local src, dst = fullPath(it), join(path, name)
                if fs.exists(dst) then setStatus("Target exists")
                else fs.move(src, dst); setStatus("Renamed", "ok") end
                refresh(); D.markDirty()
            end
        end)
    end

    local function deleteSelected()
        local it = selected()
        if not it or it.empty or it.up then return end
        local fp = fullPath(it)
        if isProtectedPath(fp) then
            setStatus("Protected folder")
            if API and API.notify then API.notify("File Explorer", fp .. " is protected", "error", 4) end
            return
        end
        local prompt = it.dir and ("Type folder name: " .. it.name) or "Type DELETE to remove:"
        D.inputDialog("Delete", prompt, it.dir and "" or "DELETE", function(answer)
            local confirmed = (it.dir and answer == it.name) or ((not it.dir) and answer == "DELETE")
            if confirmed and fs.exists(fp) then
                local ok, err = pcall(function() fs.delete(fp) end)
                if ok and not fs.exists(fp) then
                    setStatus("Deleted: " .. it.name, "ok")
                    sel = math.max(1, sel - 1)
                    refresh(); D.markDirty()
                else
                    setStatus("Delete failed: " .. tostring(err))
                end
            elseif confirmed then
                setStatus("Already gone")
                refresh(); D.markDirty()
            else
                setStatus("Delete cancelled")
            end
        end)
    end

    local function copySelected(cut)
        local it = selected()
        if not it or it.empty or it.up then return end
        if cut and isProtectedPath(fullPath(it)) then setStatus("Protected folder"); return end
        D.fileClipboard = {path=fullPath(it), cut=cut}
        setStatus((cut and "Cut: " or "Copied: ") .. it.name, "ok")
        D.markContentDirty(D.activeWin)
    end

    local function pasteClipboard()
        local cb = D.fileClipboard
        if not cb or not cb.path or not fs.exists(cb.path) then setStatus("Clipboard empty"); return end
        local name = fileName(cb.path)
        local dst = join(path, name)
        if fs.exists(dst) then
            local base, ext = name:match("^(.*)(%.[^%.]+)$")
            base, ext = base or name, ext or ""
            local n = 2
            repeat
                dst = join(path, base .. "_" .. n .. ext)
                n = n + 1
            until not fs.exists(dst)
        end
        local ok, err = pcall(function()
            if cb.cut then fs.move(cb.path, dst); D.fileClipboard = nil else fs.copy(cb.path, dst) end
        end)
        setStatus(ok and "Pasted" or tostring(err), ok and "ok" or nil)
        refresh(); D.markDirty()
    end

    local function activate()
        local it = selected()
        if not it or it.empty then return end
        if it.up then goUp() else openFile(fullPath(it)) end
    end

    local function cycleSort()
        sortMode = sortMode == "name" and "type" or (sortMode == "type" and "size" or "name")
        refresh(); D.markDirty()
    end

    refresh()
    local wx, wy, ww, wh = API.fitWindow(390, 210)
    local w = API.window("File Explorer", wx, wy, ww, wh)
    if not w then return end

    local toolbar = {
        {id="back", label="<", w=22},
        {id="up", label="Up", w=28},
        {id="new", label="New", w=34},
        {id="dir", label="Dir", w=30},
        {id="copy", label="Copy", w=42},
        {id="cut", label="Cut", w=34},
        {id="paste", label="Paste", w=44},
        {id="delete", label="Del", w=34},
        {id="sort", label="Sort", w=38},
        {id="refresh", label="Rfr", w=32},
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

    local function layout(cw, ch)
        local previewW = cw >= 300 and math.max(94, math.floor(cw * 0.34)) or 0
        local listW = previewW > 0 and (cw - previewW - 6) or cw
        local listY = 44
        local footerY = ch - 10
        local rowH = 8
        local rows = math.max(1, math.floor((footerY - listY - 8) / rowH))
        return listW, previewW, listY, footerY, rowH, rows
    end

    local function selectAt(mx, my)
        local listW, _, listY, _, rowH, rows = layout(w.cw - 6, w.ch - 21)
        if mx < 0 or mx >= listW then return false end
        for i = 1, rows do
            local iy = listY + (i - 1) * rowH
            if my >= iy and my < iy + rowH then
                sel = math.min(#items, scroll + i)
                return true
            end
        end
        return false
    end

    local function showProperties()
        local it = selected()
        if not it or it.empty then return end
        local fp = fullPath(it)
        local msg = it.name .. " | " .. it.kind
        if not it.dir and not it.up then msg = msg .. " | " .. formatSize(it.size) end
        if API and API.notify then API.notify("Properties", msg, "info", 6) end
        setStatus(msg)
    end

    local function showContext(mx, my)
        local hit = selectAt(mx, my)
        local it = hit and selected() or nil
        local canFile = it and not it.empty and not it.up
        local menu = {
            {"Open", function() if canFile then activate() end end},
            {"Edit", function() if canFile then openFile(fullPath(it), true) end end},
            {nil, nil},
            {"Copy", function() if canFile then copySelected(false) end end},
            {"Cut", function() if canFile then copySelected(true) end end},
            {"Paste", function() pasteClipboard() end},
            {nil, nil},
            {"Rename", function() if canFile then renameSelected() end end},
            {"Delete", function() if canFile then deleteSelected() end end},
            {"Properties", function() showProperties() end},
            {nil, nil},
            {"Refresh", function() refresh(); D.markDirty() end},
        }
        local itemH, mw = 14, 118
        local mh = #menu * itemH + 4
        local ax = w.cx + 3 + mx
        local ay = w.cy + 18 + my
        local by = R.h - D.taskbarH
        if ax + mw > R.w then ax = R.w - mw end
        if ay + mh > by then ay = by - mh end
        D.contextMenu = {x=math.max(1, ax), y=math.max(1, ay), w=mw, h=mh, items=menu, itemH=itemH}
        D.markDirty()
    end

    local function drawPreview(cx, cy, x, y, pw, h)
        if pw <= 0 then return end
        R.drawW95Sunken(cx + x, cy + y, pw, h)
        local it = selected()
        if not it or it.empty then
            drawText(cx + x + 4, cy + y + 5, "No selection", K.DGRAY, K.GRAY, pw - 8)
            return
        end
        local fp = fullPath(it)
        drawText(cx + x + 4, cy + y + 5, clip(it.name, pw - 8), K.BLACK, K.GRAY, pw - 8)
        drawText(cx + x + 4, cy + y + 17, it.kind, K.DBLUE, K.GRAY, pw - 8)
        if not it.dir and not it.up then drawText(cx + x + 4, cy + y + 29, it.sizeText, K.BLACK, K.GRAY, pw - 8) end
        local lineY = y + 43
        if IMAGE_EXT[it.ext] then
            drawText(cx + x + 4, cy + lineY, imageInfo(fp), K.CYAN, K.GRAY, pw - 8)
            lineY = lineY + 12
            if it.size >= LARGE_WARN then
                drawText(cx + x + 4, cy + lineY, "Large: safe preview", K.RED, K.GRAY, pw - 8)
                lineY = lineY + 12
            end
        elseif TEXT_EXT[it.ext] and it.size < 8192 then
            for _, line in ipairs(textPreview(fp, 4)) do
                drawText(cx + x + 4, cy + lineY, line, K.DGRAY, K.GRAY, pw - 8)
                lineY = lineY + 10
                if lineY > y + h - 14 then break end
            end
        end
        drawText(cx + x + 4, cy + y + h - 12, fp, K.DGRAY, K.GRAY, pw - 8)
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

        local listW, previewW, listY, footerY, rowH, rows = layout(cw, ch)
        local nameW = math.max(56, listW - 102)
        local typeX = cx + 6 + nameW
        local sizeX = cx + listW - 50
        local headerY = cy + listY - 9
        local listTop = cy + listY
        local footerAbsY = cy + footerY

        R.fillRect(cx, headerY, listW, 9, K.LGRAY)
        drawText(cx + 6, headerY + 1, "Name", K.BLACK, K.LGRAY, nameW - 2)
        if listW >= 145 then drawText(typeX, headerY + 1, "Type", K.BLACK, K.LGRAY, 38) end
        if listW >= 200 then drawText(sizeX, headerY + 1, "Size", K.BLACK, K.LGRAY, 48) end
        R.fillRect(cx, listTop, listW, rows * rowH, K.GRAY)

        local hoverIndex = nil
        local localMouseX = D.mouse.x - cx
        local localMouseY = D.mouse.y - cy
        if localMouseX >= 0 and localMouseX < listW then
            for i = 1, rows do
                local iy = listY + (i - 1) * rowH
                if localMouseY >= iy and localMouseY < iy + rowH then
                    hoverIndex = scroll + i
                    break
                end
            end
        end

        for i = 1, rows do
            local idx = scroll + i
            local it = items[idx]
            if not it then break end
            local iy = listTop + (i - 1) * rowH
            local active = (hoverIndex and idx == hoverIndex) or (not hoverIndex and idx == sel)
            if active then R.fillRect(cx + 2, iy, listW - 4, rowH, K.DBLUE) end
            local fg, bg = active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY
            local prefix = it.up and "^ " or (it.dir and "[] " or (IMAGE_EXT[it.ext] and "## " or "   "))
            drawText(cx + 6, iy, prefix .. it.name, fg, bg, nameW - 6)
            if listW >= 145 then drawText(typeX, iy, it.kind, fg, bg, 38) end
            if listW >= 200 then drawText(sizeX, iy, it.sizeText, fg, bg, 48) end
        end

        local maxScroll = math.max(0, #items - rows)
        if maxScroll > 0 and listW >= 12 then
            local barH = math.max(8, math.floor((rows / #items) * (rows * rowH)))
            local barY = listTop + math.floor(((rows * rowH) - barH) * scroll / maxScroll)
            R.fillRect(cx + listW - 5, barY, 3, barH, K.DGRAY)
        end

        if previewW > 0 then drawPreview(cx, cy, listW + 6, listY - 9, previewW, footerY - listY + 8) end
        drawText(cx + 4, footerAbsY, status .. "  Enter=open  C/X/V copy/cut/paste", K.DGRAY, K.GRAY, cw - 8)
    end

    w.onClick = function(_, mx, my)
        local hit = toolbarHit(mx, my)
        if hit == "back" then goBack(); return
        elseif hit == "up" then goUp(); return
        elseif hit == "new" then createFile(); return
        elseif hit == "dir" then createFolder(); return
        elseif hit == "copy" then copySelected(false); return
        elseif hit == "cut" then copySelected(true); return
        elseif hit == "paste" then pasteClipboard(); return
        elseif hit == "delete" then deleteSelected(); return
        elseif hit == "sort" then cycleSort(); return
        elseif hit == "refresh" then refresh(); D.markDirty(); return end

        if selectAt(mx, my) then D.markContentDirty(w); return end
    end

    w.onDoubleClick = function(_, mx, my)
        selectAt(mx, my)
        activate()
    end
    w.onRightClick = function(_, mx, my) showContext(mx, my) end

    w.onKey = function(_, k, ch)
        local _, _, _, _, _, rows = layout(w.cw - 6, w.ch - 21)
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
        elseif ch == "c" or ch == "C" then copySelected(false)
        elseif ch == "x" or ch == "X" then copySelected(true)
        elseif ch == "v" or ch == "V" then pasteClipboard()
        elseif ch == "s" or ch == "S" then cycleSort()
        elseif ch == "i" or ch == "I" then showProperties()
        elseif k == keys.delete then deleteSelected()
        elseif k == keys.f5 then refresh(); D.markDirty()
        elseif k == keys.escape then API.close(w) end
    end

    w.onScroll = function(_, dir)
        local _, _, _, _, _, rows = layout(w.cw - 6, w.ch - 21)
        local maxScroll = math.max(0, #items - rows)
        if dir < 0 then scroll = math.max(0, scroll - 3)
        else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#items, math.max(sel, scroll + 1)))
        D.markContentDirty(w)
    end
end

return {name = "File Explorer", icon = "files", run = appFM}
