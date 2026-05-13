-- CCOS Program: Settings
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,GREEN=9,RED=11,DBLUE=19,CYAN=7}

local function text(x, y, value, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, value, fg, bg, w)
    else R.drawText(x, y, tostring(value or ""), fg, bg) end
end

local function button(x, y, w, label)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, label, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); text(x + 4, y + 3, label, K.BLACK, K.GRAY, w - 8) end
end

local function appSettings()
    local wx, wy, ww, wh = D.fitWin(260, 170)
    local win = D.createWindow("Settings", wx, wy, ww, wh)
    local status = "Ready"

    local actions = {
        {id="label",  label="Label"},
        {id="layout", label="Layout"},
        {id="save",   label="Save"},
        {id="reload", label="Reload"},
        {id="reboot", label="Reboot"},
        {id="power",  label="Power"},
    }

    local function freeSpace()
        local free = "?"
        pcall(function() free = tostring(fs.getFreeSpace("/")) end)
        return free
    end

    local function setStatus(value)
        status = value
        D.markContentDirty(win)
    end

    local function runAction(id)
        if id == "label" then
            D.inputDialog("Set Label", "Computer label:", os.getComputerLabel and (os.getComputerLabel() or "") or "", function(name)
                if name and os.setComputerLabel then
                    os.setComputerLabel(name)
                    setStatus("Label saved")
                end
            end)
        elseif id == "layout" then
            D.inputLayout = D.inputLayout == "RU" and "EN" or "RU"
            setStatus("Layout: " .. D.inputLayout)
        elseif id == "save" then
            if D.saveConfig then D.saveConfig() end
            setStatus("Session saved")
        elseif id == "reload" then
            if D.loadPrograms then D.loadPrograms() end
            D.markDirty()
            setStatus("Programs reloaded")
        elseif id == "reboot" then
            os.reboot()
        elseif id == "power" then
            os.shutdown()
        end
    end

    win.onDraw = function(_, cx, cy, cw, ch)
        R.fillRect(cx, cy, cw, ch, K.GRAY)

        local label = os.getComputerLabel and (os.getComputerLabel() or "None") or "None"
        local id = os.getComputerID and os.getComputerID() or "?"
        text(cx + 4, cy + 4, "Label: " .. label, K.BLACK, K.GRAY, cw - 8)
        text(cx + 4, cy + 16, "ID: " .. id, K.BLACK, K.GRAY, cw - 8)
        text(cx + 4, cy + 28, "Screen: " .. R.w .. "x" .. R.h, K.BLACK, K.GRAY, cw - 8)
        text(cx + 4, cy + 40, "Free: " .. freeSpace() .. " bytes", K.BLACK, K.GRAY, cw - 8)
        text(cx + 4, cy + 52, "Layout: " .. tostring(D.inputLayout or "EN"), K.BLACK, K.GRAY, cw - 8)
        text(cx + 4, cy + 64, "Windows: " .. tostring(#(D.windows or {})), K.BLACK, K.GRAY, cw - 8)
        text(cx + 4, cy + 78, status, status == "Ready" and K.DGRAY or K.GREEN, K.GRAY, cw - 8)

        local cols = cw >= 190 and 3 or 2
        local gap = 6
        local bw = math.floor((cw - 8 - (cols - 1) * gap) / cols)
        local startY = cy + ch - (cols == 3 and 38 or 56)
        for i, action in ipairs(actions) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            button(cx + 4 + col * (bw + gap), startY + row * 20, bw, action.label)
        end
    end

    win.onClick = function(_, mx, my)
        local cw, ch = win.cw - 6, win.ch - 21
        local cols = cw >= 190 and 3 or 2
        local gap = 6
        local bw = math.floor((cw - 8 - (cols - 1) * gap) / cols)
        local startY = ch - (cols == 3 and 38 or 56)
        for i, action in ipairs(actions) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x = 4 + col * (bw + gap)
            local y = startY + row * 20
            if mx >= x and mx < x + bw and my >= y and my < y + 14 then
                runAction(action.id)
                return
            end
        end
    end

    win.onKey = function(_, k, ch)
        if k == keys.escape then D.destroyWindow(win)
        elseif ch == "l" or ch == "L" then runAction("layout")
        elseif ch == "s" or ch == "S" then runAction("save") end
    end
end

return {
    name = "Settings",
    icon = "settings",
    run = appSettings
}
