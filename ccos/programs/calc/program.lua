-- CCOS Program: Calculator
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=19,DESKTOP=30}

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or text, fg, bg) end
end

local function button(x, y, w, h, text)
    if R.drawButtonText then R.drawButtonText(x, y, w, h, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, h, false); drawText(x + 3, y + 3, text, K.BLACK, K.GRAY, w - 6) end
end

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
    local pad = 2

    local function metrics(cw, ch)
        local btnW = math.max(16, math.floor((cw - 10 - 3 * pad) / 4))
        local btnH = math.max(10, math.min(14, math.floor((ch - 54 - 4 * pad) / 5)))
        local gridW = 4 * btnW + 3 * pad
        local gridH = 5 * btnH + 4 * pad
        local startX = math.max(2, math.floor((cw - gridW) / 2))
        local startY = math.max(48, ch - gridH - 4)
        return btnW, btnH, startX, startY
    end

    w.onDraw = function(win, cx, cy, cw, ch)
        R.drawW95Sunken(cx+4, cy+4, math.max(8, cw-8), 18)
        local text = display
        if result ~= "" then text = result end
        drawText(cx+6, cy+7, text, K.BLACK, K.GRAY, cw - 12)

        if ch < 86 or cw < 78 then
            drawText(cx+4, cy+26, "Resize calculator", K.DGRAY, K.GRAY, cw - 8)
            return
        end

        local hy = cy + 26
        for i = math.max(1, #history - 1), #history do
            drawText(cx+4, hy, history[i] or "", K.DBLUE, K.GRAY, cw - 8)
            hy = hy + 8
        end

        local btnW, btnH, startX, startY = metrics(cw, ch)
        for row = 1, 5 do
            for col = 1, 4 do
                local label = buttons[row][col]
                if label and label ~= "" then
                    local bx = cx + startX + (col-1)*(btnW+pad)
                    local by = cy + startY + (row-1)*(btnH+pad)
                    button(bx, by, btnW, btnH, label)
                end
            end
        end
    end

    w.onClick = function(win, mx, my)
        -- mx,my are relative to content area
        if win.ch - 21 < 86 or win.cw - 6 < 78 then return end
        local btnW, btnH, startX, startY = metrics(win.cw - 6, win.ch - 21)

        for row = 1, 5 do
            for col = 1, 4 do
                local label = buttons[row][col]
                if label and label ~= "" then
                    local bx = startX + (col-1)*(btnW+pad)
                    local by = startY + (row-1)*(btnH+pad)
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
