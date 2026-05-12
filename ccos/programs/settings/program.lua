-- CCOS Program: System Info
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appSettings()
    local wx, wy, ww, wh = D.fitWin(220, 140)
    local w = D.createWindow("System Info", wx, wy, ww, wh)

    w.onDraw = function(win, cx, cy, cw, ch)
        local label = os.getComputerLabel and os.getComputerLabel() or "None"
        local id = os.getComputerID and os.getComputerID() or "?"
        local free = "?"
        pcall(function() free = tostring(fs.getFreeSpace("/")) end)

        R.drawText(cx+4, cy+4, "Label: " .. label, K.BLACK, K.GRAY)
        R.drawText(cx+4, cy+16, "ID: " .. id, K.BLACK, K.GRAY)
        R.drawText(cx+4, cy+28, "Screen: " .. R.w .. "x" .. R.h, K.BLACK, K.GRAY)
        R.drawText(cx+4, cy+40, "Free: " .. free .. " bytes", K.BLACK, K.GRAY)
        R.drawText(cx+4, cy+52, "Windows: " .. #D.windows, K.BLACK, K.GRAY)
        R.drawText(cx+4, cy+64, "CCOS v3.0", K.DBLUE, K.GRAY)

        local by2 = cy + ch - 20
        R.drawButton(cx+4, by2, 52, 14, false)
        R.drawText(cx+8, by2+3, "Set Label", K.BLACK, K.GRAY)

        R.drawButton(cx+62, by2, 44, 14, false)
        R.drawText(cx+66, by2+3, "Reboot", K.BLACK, K.GRAY)

        R.drawButton(cx+110, by2, 52, 14, false)
        R.drawText(cx+114, by2+3, "Shutdown", K.BLACK, K.GRAY)
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
