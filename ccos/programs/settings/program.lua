-- CCOS Program: System Info
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=19,DESKTOP=30}

local function text(x, y, value, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, value, fg, bg, w) else R.drawText(x, y, value, fg, bg) end
end

local function button(x, y, w, label)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, label, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); text(x + 4, y + 3, label, K.BLACK, K.GRAY, w - 8) end
end

local function appSettings()
    local wx, wy, ww, wh = D.fitWin(220, 140)
    local w = D.createWindow("System Info", wx, wy, ww, wh)

    w.onDraw = function(win, cx, cy, cw, ch)
        local label = os.getComputerLabel and os.getComputerLabel() or "None"
        local id = os.getComputerID and os.getComputerID() or "?"
        local free = "?"
        pcall(function() free = tostring(fs.getFreeSpace("/")) end)

        text(cx+4, cy+4, "Label: " .. label, K.BLACK, K.GRAY, cw - 8)
        text(cx+4, cy+16, "ID: " .. id, K.BLACK, K.GRAY, cw - 8)
        text(cx+4, cy+28, "Screen: " .. R.w .. "x" .. R.h, K.BLACK, K.GRAY, cw - 8)
        text(cx+4, cy+40, "Free: " .. free .. " bytes", K.BLACK, K.GRAY, cw - 8)
        text(cx+4, cy+52, "Windows: " .. #D.windows, K.BLACK, K.GRAY, cw - 8)
        text(cx+4, cy+64, "CCOS v3.0", K.DBLUE, K.GRAY, cw - 8)

        local by2 = cy + ch - 20
        if cw >= 56 then button(cx+4, by2, 52, "Label") end
        if cw >= 106 then button(cx+62, by2, 44, "Reboot") end
        if cw >= 164 then button(cx+110, by2, 52, "Power") end
    end

    w.onClick = function(win, mx, my)
        local ch2 = win.ch - 21
        local by2 = ch2 - 20
        if my >= by2 and my < by2 + 14 then
            if mx >= 4 and mx < 56 then
                D.inputDialog("Set Label", "Enter new label:", "", function(name)
                    if name and os.setComputerLabel then
                        os.setComputerLabel(name)
                        D.markContentDirty(win)
                    end
                end)
            elseif mx >= 62 and mx < 106 then
                os.reboot()
            elseif mx >= 110 and mx < 162 then
                os.shutdown()
            end
        end
    end

    w.onKey = function(win, k)
        -- Settings is view-only; close only via X button
    end
end

return {
    name = "System Info",
    icon = "settings",
    run = appSettings
}
