--[[
    GUI Framework for CCOS
    ======================
    Windows, buttons, labels, list boxes, text input, message boxes.
    All coordinates are relative to the display (not window).
]]

local gui = {}

gui.C = {
    WHITE = 1, BLACK = 8, GRAY = 256, LIGHT_GRAY = 2,
    RED = 16384, YELLOW = 32, GREEN = 8192, CYAN = 512,
    BLUE = 2048, ORANGE = 4, PINK = 128, PURPLE = 1024,
}

gui.windows = {}
gui.focused = nil
gui.isColor = term.isColor and term.isColor() or false
gui.w, gui.h = term.getSize()

function gui.setDisplay(d, w, h)
    gui.display = d
    gui.w = w
    gui.h = h
    if d.isColor then
        local ok, v = pcall(function() return d.isColor() end)
        gui.isColor = ok and v or false
    end
end

function gui.setColors(fg, bg)
    if not gui.isColor then return end
    local d = gui.display or term
    if d.setTextColor then d.setTextColor(fg) end
    if d.setBackgroundColor then d.setBackgroundColor(bg) end
end

function gui.resetColors()
    gui.setColors(gui.C.WHITE, gui.C.BLACK)
end

function gui.clear()
    local d = gui.display or term
    if gui.isColor then d.setBackgroundColor(gui.C.BLACK) end
    d.clear()
    d.setCursorPos(1, 1)
end

function gui.writeAt(x, y, text, fg, bg)
    local d = gui.display or term
    d.setCursorPos(x, y)
    if fg then gui.setColors(fg, bg or gui.C.BLACK) end
    if #text > gui.w - x + 1 then text = text:sub(1, gui.w - x + 1) end
    d.write(text)
    gui.resetColors()
end

function gui.clearLine(y)
    local d = gui.display or term
    d.setCursorPos(1, y)
    d.clearLine()
end

function gui.fillRect(x, y, w, h, color)
    if not gui.isColor then return end
    local d = gui.display or term
    d.setBackgroundColor(color)
    for row = 0, h - 1 do
        d.setCursorPos(x, y + row)
        d.write(string.rep(" ", w))
    end
    gui.resetColors()
end

-- ============================================================
-- WINDOW
-- ============================================================
function gui.createWindow(x, y, w, h, title)
    local win = {
        x = x, y = y, w = w, h = h,
        title = title or "Window",
        visible = true,
        modal = false,
        fg = gui.C.WHITE,
        bg = gui.C.BLACK,
        titleFg = gui.C.WHITE,
        titleBg = gui.C.BLUE,
        children = {},
        onKey = nil,
        onMouse = nil,
        onClose = nil,
        result = nil,
    }
    table.insert(gui.windows, win)
    gui.focused = win
    return win
end

function gui.destroyWindow(win)
    for i, w in ipairs(gui.windows) do
        if w == win then
            table.remove(gui.windows, i)
            break
        end
    end
    if gui.focused == win then
        gui.focused = gui.windows[#gui.windows]
    end
    if win.onClose then win.onClose() end
end

function gui.drawWindow(win)
    if not win.visible then return end
    local d = gui.display or term
    local x, y, w, h = win.x, win.y, win.w, win.h

    -- Background
    gui.fillRect(x, y, w, h, win.bg)

    -- Title bar
    gui.fillRect(x, y, w, 1, win.titleBg)
    gui.writeAt(x + 1, y, " " .. win.title .. " ", win.titleFg, win.titleBg)
    -- Close button
    gui.writeAt(x + w - 3, y, "[X]", gui.C.RED, win.titleBg)

    -- Border
    if gui.isColor then
        gui.setColors(gui.C.GRAY, gui.C.BLACK)
    end
    for row = 1, h - 2 do
        d.setCursorPos(x, y + row)
        d.write("|")
        d.setCursorPos(x + w - 1, y + row)
        d.write("|")
    end
    d.setCursorPos(x, y + h - 1)
    d.write("+" .. string.rep("-", w - 2) .. "+")
    gui.resetColors()

    -- Draw children
    for _, child in ipairs(win.children) do
        if child.visible then
            gui.drawChild(child, x, y)
        end
    end
end

function gui.drawChild(child, winX, winY)
    local absX = winX + child.x - 1
    local absY = winY + child.y - 1
    local d = gui.display or term

    if child.type == "label" then
        gui.writeAt(absX, absY, child.text or "", child.fg, child.bg)
    elseif child.type == "button" then
        local text = " " .. (child.text or "") .. " "
        gui.fillRect(absX, absY, #text, 1, child.bg or gui.C.GRAY)
        gui.writeAt(absX, absY, text, child.fg or gui.C.WHITE, child.bg or gui.C.GRAY)
    elseif child.type == "list" then
        gui.drawList(child, absX, absY)
    elseif child.type == "textfield" then
        local text = child.text or ""
        local displayText = text
        if child.password then
            displayText = string.rep("*", #text)
        end
        gui.fillRect(absX, absY, child.w, 1, gui.C.BLACK)
        gui.writeAt(absX, absY, displayText, child.fg or gui.C.WHITE, gui.C.BLACK)
        -- Cursor
        if child.focused and gui.isColor then
            d.setCursorPos(absX + #displayText, absY)
            d.setBackgroundColor(gui.C.WHITE)
            d.write(" ")
            gui.resetColors()
        end
    elseif child.type == "separator" then
        gui.setColors(gui.C.GRAY, gui.C.BLACK)
        d.setCursorPos(absX, absY)
        d.write(string.rep("-", child.w or 10))
        gui.resetColors()
    end
end

function gui.drawList(child, absX, absY)
    local d = gui.display or term
    local items = child.items or {}
    local selected = child.selected or 1
    local h = child.h or 5
    local w = child.w or 20

    for i = 1, h do
        local idx = (child.scroll or 0) + i
        local item = items[idx]
        d.setCursorPos(absX, absY + i - 1)
        if item then
            local prefix = (idx == selected) and "> " or "  "
            local text = prefix .. item
            if #text > w then text = text:sub(1, w) end
            if idx == selected then
                gui.setColors(gui.C.BLACK, gui.C.LIGHT_GRAY)
                d.write(text .. string.rep(" ", w - #text))
            else
                gui.setColors(gui.C.WHITE, gui.C.BLACK)
                d.write(text)
            end
        else
            gui.setColors(gui.C.WHITE, gui.C.BLACK)
            d.write(string.rep(" ", w))
        end
    end
    gui.resetColors()
end

function gui.drawAll()
    gui.clear()
    for _, win in ipairs(gui.windows) do
        if win.visible then
            gui.drawWindow(win)
        end
    end
end

-- ============================================================
-- CHILDREN CREATION
-- ============================================================
function gui.addLabel(win, x, y, text, fg, bg)
    local child = {type="label", x=x, y=y, text=text, fg=fg, bg=bg, visible=true}
    table.insert(win.children, child)
    return child
end

function gui.addButton(win, x, y, w, text, fg, bg, onClick)
    local child = {type="button", x=x, y=y, w=w, text=text, fg=fg, bg=bg, onClick=onClick, visible=true}
    table.insert(win.children, child)
    return child
end

function gui.addList(win, x, y, w, h, items)
    local child = {type="list", x=x, y=y, w=w, h=h, items=items or {}, selected=1, scroll=0, visible=true}
    table.insert(win.children, child)
    return child
end

function gui.addTextField(win, x, y, w, password)
    local child = {type="textfield", x=x, y=y, w=w, text="", password=password, focused=false, visible=true}
    table.insert(win.children, child)
    return child
end

function gui.addSeparator(win, x, y, w)
    local child = {type="separator", x=x, y=y, w=w, visible=true}
    table.insert(win.children, child)
    return child
end

-- ============================================================
-- INPUT HANDLING
-- ============================================================
function gui.handleClick(win, cx, cy)
    -- Check close button
    if cy == win.y and cx >= win.x + win.w - 3 and cx <= win.x + win.w - 1 then
        gui.destroyWindow(win)
        return true
    end

    -- Check children
    for _, child in ipairs(win.children) do
        if not child.visible then goto continue end
        local absX = win.x + child.x - 1
        local absY = win.y + child.y - 1

        if cx >= absX and cx < absX + (child.w or #child.text or 10) and
           cy >= absY and cy < absY + (child.h or 1) then

            if child.type == "button" and child.onClick then
                child.onClick()
                return true
            elseif child.type == "list" then
                local idx = (child.scroll or 0) + (cy - absY + 1)
                if child.items[idx] then
                    child.selected = idx
                    if child.onSelect then child.onSelect(idx, child.items[idx]) end
                end
                return true
            elseif child.type == "textfield" then
                -- Focus this textfield, unfocus others
                for _, c in ipairs(win.children) do
                    if c.type == "textfield" then c.focused = false end
                end
                child.focused = true
                return true
            end
        end
        ::continue::
    end
    return false
end

function gui.handleKey(win, key, char)
    -- Find focused textfield
    local tf = nil
    for _, child in ipairs(win.children) do
        if child.type == "textfield" and child.focused then
            tf = child
            break
        end
    end

    if tf then
        if key == keys.backspace then
            tf.text = tf.text:sub(1, -2)
            return true
        elseif key == keys.enter then
            if tf.onSubmit then tf.onSubmit(tf.text) end
            return true
        elseif char then
            if #tf.text < tf.w then
                tf.text = tf.text .. char
            end
            return true
        end
    end

    -- List navigation
    for _, child in ipairs(win.children) do
        if child.type == "list" and child.items and #child.items > 0 then
            if key == keys.up then
                if child.selected > 1 then
                    child.selected = child.selected - 1
                    if child.selected <= child.scroll then
                        child.scroll = math.max(0, child.selected - 1)
                    end
                end
                return true
            elseif key == keys.down then
                if child.selected < #child.items then
                    child.selected = child.selected + 1
                    if child.selected > child.scroll + child.h then
                        child.scroll = child.selected - child.h
                    end
                end
                return true
            elseif key == keys.enter then
                if child.onSelect and child.items[child.selected] then
                    child.onSelect(child.selected, child.items[child.selected])
                end
                return true
            end
        end
    end

    return false
end

-- ============================================================
-- MESSAGE BOX
-- ============================================================
function gui.messageBox(title, message, buttons)
    buttons = buttons or {"OK"}
    local w = math.max(#title + 6, #message + 6, 30)
    local h = 8
    local x = math.floor((gui.w - w) / 2) + 1
    local y = math.floor((gui.h - h) / 2) + 1

    local win = gui.createWindow(x, y, w, h, title)
    gui.addLabel(win, 2, 3, message)

    local result = nil
    local btnY = 5
    local btnX = 2
    for i, btnText in ipairs(buttons) do
        local btn = gui.addButton(win, btnX, btnY, #btnText + 2, btnText, gui.C.WHITE, gui.C.GRAY, function()
            result = i
            gui.destroyWindow(win)
        end)
        btnX = btnX + #btnText + 4
    end

    -- Modal loop
    while win.visible and result == nil do
        gui.drawAll()
        local event = os.pullEvent()
        if event[1] == "mouse_click" then
            gui.handleClick(win, event[3], event[4])
        elseif event[1] == "key" then
            if event[2] == keys.enter and #buttons == 1 then
                result = 1
                gui.destroyWindow(win)
            elseif event[2] == keys.escape then
                result = #buttons
                gui.destroyWindow(win)
            end
        end
    end

    return result
end

-- ============================================================
-- INPUT DIALOG
-- ============================================================
function gui.inputBox(title, prompt, default)
    default = default or ""
    local w = math.max(#title + 6, 40)
    local h = 8
    local x = math.floor((gui.w - w) / 2) + 1
    local y = math.floor((gui.h - h) / 2) + 1

    local win = gui.createWindow(x, y, w, h, title)
    gui.addLabel(win, 2, 3, prompt)

    local result = nil
    local tf = gui.addTextField(win, 2, 5, w - 4)
    tf.text = default
    tf.focused = true
    tf.onSubmit = function(text)
        result = text
        gui.destroyWindow(win)
    end

    -- Modal loop
    while win.visible and result == nil do
        gui.drawAll()
        local event = os.pullEvent()
        if event[1] == "mouse_click" then
            gui.handleClick(win, event[3], event[4])
        elseif event[1] == "char" then
            gui.handleKey(win, nil, event[2])
        elseif event[1] == "key" then
            gui.handleKey(win, event[2], nil)
        end
    end

    return result
end

-- ============================================================
-- CONFIRM DIALOG
-- ============================================================
function gui.confirm(title, message)
    local result = gui.messageBox(title, message, {"Yes", "No"})
    return result == 1
end

-- ============================================================
-- CHOOSE FROM LIST
-- ============================================================
function gui.chooseBox(title, prompt, items)
    local w = math.max(#title + 6, 50)
    local h = math.min(#items + 6, gui.h - 4)
    local x = math.floor((gui.w - w) / 2) + 1
    local y = math.floor((gui.h - h) / 2) + 1

    local win = gui.createWindow(x, y, w, h, title)
    gui.addLabel(win, 2, 2, prompt)

    local result = nil
    local list = gui.addList(win, 2, 4, w - 4, h - 5, items)
    list.onSelect = function(idx, item)
        result = idx
        gui.destroyWindow(win)
    end

    -- Modal loop
    while win.visible and result == nil do
        gui.drawAll()
        local event = os.pullEvent()
        if event[1] == "mouse_click" then
            gui.handleClick(win, event[3], event[4])
        elseif event[1] == "key" then
            gui.handleKey(win, event[2], nil)
        end
    end

    return result
end

return gui
