-- CCOS Program: Calculator
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appCalc()
    local display = ""
    local result = ""
    local history = {}

    local wx, wy, ww, wh = D.fitWin(160, 180)
    local w = D.createWindow("Calculator", wx, wy, ww, wh)

    local buttons = {
        {"C",  "",  "",  "/"},
        {"7", "8", "9", "*"},
        {"4", "5", "6", "-"},
        {"1", "2", "3", "+"},
        {"0", ".", "=", ""}
    }
    local btnW, btnH = 32, 18

    w.onDraw = function(win, cx, cy, cw, ch)
        R.drawW95Sunken(cx+4, cy+4, cw-8, 20)
        local text = display
        if result ~= "" then text = result end
        R.drawText(cx+6, cy+8, text, K.BLACK, K.GRAY)

        local hy = cy + 28
        for i = math.max(1, #history - 2), #history do
            R.drawText(cx+4, hy, history[i] or "", K.DBLUE, K.GRAY)
            hy = hy + 8
        end

        local startX = cx + math.floor((cw - 4*btnW - 12) / 2)
        local startY = cy + ch - 5*btnH - 20
        for row = 1, 5 do
            for col = 1, 4 do
                local label = buttons[row][col]
                if label and label ~= "" then
                    local bx = startX + (col-1)*(btnW+3)
                    local by = startY + (row-1)*(btnH+3)
                    R.drawButton(bx, by, btnW, btnH, false)
                    R.drawText(bx+10, by+5, label, K.BLACK, K.GRAY)
                end
            end
        end
    end

    w.onClick = function(win, mx, my)
        -- mx,my are relative to content area (0,0 = top-left of content)
        -- Must match onDraw coordinates
        local startX = math.floor((win.cw - 4*btnW - 18) / 2)
        local startY = win.ch - 5*btnH - 41

        for row = 1, 5 do
            for col = 1, 4 do
                local label = buttons[row][col]
                if label and label ~= "" then
                    local bx = startX + (col-1)*(btnW+3)
                    local by = startY + (row-1)*(btnH+3)
                    if mx >= bx and mx < bx+btnW and my >= by and my < by+btnH then
                        if label == "C" then
                            display = ""
                            result = ""
                        elseif label == "=" then
                            local fn = load("return " .. display, "calc", "t", _G)
                            if fn then
                                local ok, r = pcall(fn)
                                if ok then
                                    result = tostring(r)
                                    table.insert(history, display .. " = " .. result)
                                    display = result
                                else
                                    result = "Error"
                                end
                            else
                                result = "Syntax"
                            end
                        else
                            display = display .. label
                            result = ""
                        end
                        D.markContentDirty(win)
                        return
                    end
                end
            end
        end
    end

    w.onKey = function(win, k, ch)
        if ch and ch:match("[%d%.%+%-%*/]") then
            display = display .. ch
            result = ""
            D.markContentDirty(win)
        elseif k == keys.enter then
            local fn = load("return " .. display, "calc", "t", _G)
            if fn then
                local ok, r = pcall(fn)
                if ok then
                    result = tostring(r)
                    table.insert(history, display .. " = " .. result)
                    display = result
                else
                    result = "Error"
                end
            else
                result = "Syntax"
            end
            D.markContentDirty(win)
        elseif k == keys.backspace then
            display = display:sub(1, -2)
            result = ""
            D.markContentDirty(win)
        elseif k == keys.delete then
            display = ""
            result = ""
            D.markContentDirty(win)
        elseif k == keys.escape then
            D.destroyWindow(win)
        end
    end
end

return {
    name = "Calculator",
    icon = "calc",
    run = appCalc
}
