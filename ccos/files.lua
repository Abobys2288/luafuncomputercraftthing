--[[
    File Manager for CCOS
    =====================
    Browse filesystem, open/edit/delete/rename files and folders.
]]

local gui = require("ccos.gui")

local fm = {}
fm.currentPath = "/"
fm.history = {}

function fm.sortItems(items)
    local dirs = {}
    local files = {}
    for _, item in ipairs(items) do
        local path = fm.currentPath == "/" and ("/" .. item) or (fm.currentPath .. "/" .. item)
        if fs.isDir(path) then
            table.insert(dirs, "/" .. item)
        else
            table.insert(files, item)
        end
    end
    table.sort(dirs)
    table.sort(files)
    local result = {}
    for _, d in ipairs(dirs) do table.insert(result, d) end
    for _, f in ipairs(files) do table.insert(result, f) end
    return result
end

function fm.getDisplayItems()
    local items = fs.list(fm.currentPath)
    items = fm.sortItems(items)
    local display = {}
    if fm.currentPath ~= "/" then
        table.insert(display, "..")
    end
    for _, item in ipairs(items) do
        table.insert(display, item)
    end
    return display
end

function fm.getSelectedPath(selected)
    if selected == ".." then
        -- Go up
        if fm.currentPath == "/" then return "/" end
        local parts = {}
        for part in fm.currentPath:gmatch("[^/]+") do
            table.insert(parts, part)
        end
        if #parts <= 1 then return "/" end
        table.remove(parts)
        return "/" .. table.concat(parts, "/")
    end
    if selected:sub(1, 1) == "/" then
        -- Directory
        return fm.currentPath == "/" and selected or (fm.currentPath .. selected)
    end
    return fm.currentPath == "/" and ("/" .. selected) or (fm.currentPath .. "/" .. selected)
end

function fm.open()
    local w, h = gui.w, gui.h
    local winW = math.min(w - 4, 60)
    local winH = math.min(h - 4, 20)
    local winX = math.floor((w - winW) / 2) + 1
    local winY = math.floor((h - winH) / 2) + 1

    local win = gui.createWindow(winX, winY, winW, winH, "File Manager")

    local pathLabel = gui.addLabel(win, 2, 2, "")
    local list = gui.addList(win, 2, 4, winW - 4, winH - 7, {})

    local statusLabel = gui.addLabel(win, 2, winH - 2, "")

    local function refresh()
        local items = fm.getDisplayItems()
        list.items = items
        list.selected = 1
        list.scroll = 0
        pathLabel.text = " " .. fm.currentPath .. " "
        statusLabel.text = " " .. #items .. " items | Enter=Open N=New D=Del R=Rename"
    end

    list.onSelect = function(idx, item)
        local path = fm.getSelectedPath(item)
        if fs.isDir(path) then
            if item == ".." then
                fm.currentPath = fm.getSelectedPath("..")
            else
                fm.currentPath = path
            end
            refresh()
        else
            -- Try to open/edit file
            local content = ""
            local f = fs.open(path, "r")
            if f then
                content = f.readAll()
                f.close()
            end
            if content and #content > 0 then
                -- Open in edit mode
                fm.editFile(path, content)
            end
            refresh()
        end
    end

    -- Context menu
    local function showContextMenu()
        local selected = list.items[list.selected]
        if not selected then return end

        local path = fm.getSelectedPath(selected)
        local isDir = fs.isDir(path)

        local choices = {"Open", "Rename", "Delete", "New File", "New Folder", "Cancel"}
        local choice = gui.chooseBox("Action", "Choose action for: " .. selected, choices)

        if choice == 1 then -- Open
            if isDir then
                fm.currentPath = path
                refresh()
            else
                local content = ""
                local f = fs.open(path, "r")
                if f then content = f.readAll(); f.close() end
                fm.editFile(path, content)
                refresh()
            end
        elseif choice == 2 then -- Rename
            local newName = gui.inputBox("Rename", "New name:", selected)
            if newName and #newName > 0 then
                local newPath = fm.currentPath == "/" and ("/" .. newName) or (fm.currentPath .. "/" .. newName)
                fs.move(path, newPath)
                refresh()
            end
        elseif choice == 3 then -- Delete
            if gui.confirm("Delete", "Delete " .. selected .. "?") then
                fs.delete(path)
                refresh()
            end
        elseif choice == 4 then -- New File
            local name = gui.inputBox("New File", "File name:")
            if name and #name > 0 then
                local filePath = fm.currentPath == "/" and ("/" .. name) or (fm.currentPath .. "/" .. name)
                local f = fs.open(filePath, "w")
                if f then f.close() end
                fm.editFile(filePath, "")
                refresh()
            end
        elseif choice == 5 then -- New Folder
            local name = gui.inputBox("New Folder", "Folder name:")
            if name and #name > 0 then
                local dirPath = fm.currentPath == "/" and ("/" .. name) or (fm.currentPath .. "/" .. name)
                fs.makeDir(dirPath)
                refresh()
            end
        end
    end

    -- Key handling
    win.onKey = function(event)
        if event[1] == "key" then
            local key = event[2]
            if key == keys.n then
                local name = gui.inputBox("New File", "File name:")
                if name and #name > 0 then
                    local filePath = fm.currentPath == "/" and ("/" .. name) or (fm.currentPath .. "/" .. name)
                    local f = fs.open(filePath, "w")
                    if f then f.close() end
                    fm.editFile(filePath, "")
                    refresh()
                end
            elseif key == keys.d then
                local selected = list.items[list.selected]
                if selected and selected ~= ".." then
                    local path = fm.getSelectedPath(selected)
                    if gui.confirm("Delete", "Delete " .. selected .. "?") then
                        fs.delete(path)
                        refresh()
                    end
                end
            elseif key == keys.r then
                local selected = list.items[list.selected]
                if selected and selected ~= ".." then
                    local path = fm.getSelectedPath(selected)
                    local newName = gui.inputBox("Rename", "New name:", selected)
                    if newName and #newName > 0 then
                        local newPath = fm.currentPath == "/" and ("/" .. newName) or (fm.currentPath .. "/" .. newName)
                        fs.move(path, newPath)
                        refresh()
                    end
                end
            elseif key == keys.f1 or key == keys.menu then
                showContextMenu()
            end
        end
    end

    refresh()

    -- Main loop for this window
    while win.visible do
        gui.drawAll()
        local event = os.pullEvent()
        if event[1] == "mouse_click" then
            gui.handleClick(win, event[3], event[4])
        elseif event[1] == "char" then
            gui.handleKey(win, nil, event[2])
        elseif event[1] == "key" then
            if win.onKey then win.onKey(event) end
            gui.handleKey(win, event[2], nil)
        end
    end
end

function fm.editFile(path, content)
    local w, h = gui.w, gui.h
    local winW = math.min(w - 2, 64)
    local winH = math.min(h - 2, 22)
    local winX = math.floor((w - winW) / 2) + 1
    local winY = math.floor((h - winH) / 2) + 1

    local win = gui.createWindow(winX, winY, winW, winH, "Edit: " .. path)

    -- Simple multi-line text editor
    local lines = {}
    if content and #content > 0 then
        for line in content:gmatch("[^\n]*") do
            table.insert(lines, line)
        end
    else
        table.insert(lines, "")
    end
    if #lines == 0 then table.insert(lines, "") end

    local cursorLine = 1
    local cursorCol = 1
    local scrollY = 0
    local editH = winH - 5
    local modified = false

    local statusLabel = gui.addLabel(win, 2, winH - 2, "")
    local pathLabel = gui.addLabel(win, 2, 2, " " .. path .. " ")

    local function drawEditor()
        local d = gui.display or term
        for i = 1, editH do
            local lineIdx = scrollY + i
            local lineText = lines[lineIdx] or ""
            d.setCursorPos(win.x + 2, win.y + 2 + i)
            gui.setColors(gui.C.WHITE, gui.C.BLACK)
            local display = lineText
            if #display > winW - 4 then display = display:sub(1, winW - 4) end
            d.write(display .. string.rep(" ", (winW - 4) - #display))
        end

        -- Draw cursor
        if cursorLine > scrollY and cursorLine <= scrollY + editH then
            local cy = win.y + 2 + (cursorLine - scrollY)
            local cx = win.x + 1 + cursorCol
            if cx > win.x + winW - 3 then cx = win.x + winW - 3 end
            d.setCursorPos(cx, cy)
            if gui.isColor then
                d.setBackgroundColor(gui.C.WHITE)
                d.setTextColor(gui.C.BLACK)
            end
            local ch = (lines[cursorLine] or ""):sub(cursorCol, cursorCol)
            if ch == "" then ch = " " end
            d.write(ch)
            gui.resetColors()
        end

        -- Status
        local modStr = modified and " [modified]" or ""
        statusLabel.text = " Ln " .. cursorLine .. ", Col " .. cursorCol .. modStr .. " | Ctrl+S=Save Ctrl+Q=Quit"
    end

    -- Modal loop
    while win.visible do
        gui.drawWindow(win)
        drawEditor()
        local event = os.pullEvent()

        if event[1] == "char" then
            local ch = event[2]
            local line = lines[cursorLine] or ""
            lines[cursorLine] = line:sub(1, cursorCol - 1) .. ch .. line:sub(cursorCol)
            cursorCol = cursorCol + 1
            modified = true
        elseif event[1] == "key" then
            local key = event[2]
            if key == keys.backspace then
                if cursorCol > 1 then
                    local line = lines[cursorLine] or ""
                    lines[cursorLine] = line:sub(1, cursorCol - 2) .. line:sub(cursorCol)
                    cursorCol = cursorCol - 1
                    modified = true
                elseif cursorLine > 1 then
                    -- Join with previous line
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
                    if cursorLine > scrollY + editH then scrollY = cursorLine - editH end
                end
            elseif key == keys.left then
                if cursorCol > 1 then cursorCol = cursorCol - 1
                elseif cursorLine > 1 then
                    cursorLine = cursorLine - 1
                    cursorCol = #(lines[cursorLine] or "") + 1
                end
            elseif key == keys.right then
                if cursorCol <= #(lines[cursorLine] or "") then cursorCol = cursorCol + 1
                elseif cursorLine < #lines then
                    cursorLine = cursorLine + 1
                    cursorCol = 1
                end
            elseif key == keys.tab then
                -- Insert 2 spaces
                local line = lines[cursorLine] or ""
                lines[cursorLine] = line:sub(1, cursorCol - 1) .. "  " .. line:sub(cursorCol)
                cursorCol = cursorCol + 2
                modified = true
            elseif key == keys.home then
                cursorCol = 1
            elseif key == keys["end"] then
                cursorCol = #(lines[cursorLine] or "") + 1
            elseif key == keys.pageUp then
                cursorLine = math.max(1, cursorLine - editH)
                scrollY = math.max(0, cursorLine - 1)
            elseif key == keys.pageDown then
                cursorLine = math.min(#lines, cursorLine + editH)
                if cursorLine > scrollY + editH then scrollY = cursorLine - editH end
            -- Ctrl+S to save (check for ctrl modifier via key combo)
            elseif key == keys.s then
                -- Save
                local content = table.concat(lines, "\n")
                local f = fs.open(path, "w")
                if f then
                    f.write(content)
                    f.close()
                    modified = false
                end
            elseif key == keys.q then
                if modified then
                    local choice = gui.messageBox("Unsaved", "Save changes?", {"Save", "Discard", "Cancel"})
                    if choice == 1 then
                        local content = table.concat(lines, "\n")
                        local f = fs.open(path, "w")
                        if f then f.write(content); f.close() end
                        gui.destroyWindow(win)
                    elseif choice == 2 then
                        gui.destroyWindow(win)
                    end
                    -- choice == 3: cancel, do nothing
                else
                    gui.destroyWindow(win)
                end
            end
        end
    end
end

return fm
