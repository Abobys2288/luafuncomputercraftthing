-- CCOS Program: Fastfetch
-- Native CCOS port of fastfetch_cc.lua using the public CCOS API.
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render

local K = {
    BLACK=0, WHITE=1, GRAY=2, LGRAY=3, DGRAY=4,
    BLUE=5, DBLUE=6, CYAN=7, GREEN=9, YELLOW=13,
    ORANGE=14, RED=11
}

local LOGO = {
    " ######  ###### ",
    " #       #      ",
    " #       #      ",
    " #       #      ",
    " ######  ###### ",
    "                ",
    "   FASTFETCH    ",
}
local LOGO_W = 16 * 6
local LINE_H = 8

local function pcallWrap(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function safeTurtleCall(name)
    if not turtle or type(turtle[name]) ~= "function" then return nil end
    return pcallWrap(function() return turtle[name]() end)
end

local function timeText()
    local t = pcallWrap(os.time) or 0
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    return string.format("%02d:%02d", h, m)
end

local function collectInfo()
    local info = {}
    info.os = pcallWrap(os.version) or "CC:Tweaked"
    info.time = timeText()
    info.day = pcallWrap(os.day) or 0
    info.id = pcallWrap(os.getComputerID) or "N/A"
    info.label = pcallWrap(os.getComputerLabel) or "No Label"
    info.free = pcallWrap(function() return fs.getFreeSpace("/") end) or "N/A"
    info.screen = tostring(R.w) .. "x" .. tostring(R.h)
    info.graphics = R.mode and R.mode > 0
    info.isTurtle = turtle ~= nil
    info.fuel = safeTurtleCall("getFuelLevel")
    info.fuelMax = safeTurtleCall("getFuelLimit")

    local pnames = pcallWrap(function()
        if peripheral and peripheral.getNames then return peripheral.getNames() end
        return {}
    end) or {}

    info.peripherals = {}
    for _, name in ipairs(pnames) do
        local ptype = pcallWrap(function() return peripheral.getType(name) end)
        if ptype then table.insert(info.peripherals, {name=name, type=ptype}) end
    end
    table.sort(info.peripherals, function(a, b) return a.name < b.name end)

    info.invUsed = 0
    info.invTotal = 0
    info.invItems = {}
    if turtle then
        for i = 1, 16 do
            local detail = pcallWrap(function() return turtle.getItemDetail(i) end)
            if detail then
                info.invUsed = info.invUsed + 1
                info.invTotal = info.invTotal + (detail.count or 0)
                table.insert(info.invItems, string.format("[%d] %s x%d", i, tostring(detail.name), detail.count or 0))
            end
        end
    end

    info.disks = {}
    for _, p in ipairs(info.peripherals) do
        if p.type == "drive" then
            local d = pcallWrap(function() return peripheral.wrap(p.name) end)
            if d then
                local present = pcallWrap(function() return d.isDiskPresent() end)
                if present then
                    table.insert(info.disks, {
                        side = p.name,
                        label = pcallWrap(function() return d.getDiskLabel() end) or "N/A",
                        id = pcallWrap(function() return d.getDiskID() end) or "N/A",
                    })
                end
            end
        end
    end

    return info
end

local function addLine(rows, label, value, color)
    table.insert(rows, {label=label or "", value=tostring(value or ""), color=color or K.WHITE})
end

local function addSection(rows, label)
    table.insert(rows, {section=label})
end

local function buildRows(info)
    local rows = {}
    addLine(rows, "OS", info.os, K.CYAN)
    addLine(rows, "CCOS", "Desktop API", K.CYAN)
    addLine(rows, "ID", info.id, K.CYAN)
    addLine(rows, "Label", info.label, K.CYAN)
    addLine(rows, "Time", info.time, K.CYAN)
    addLine(rows, "Day", info.day, K.CYAN)
    addLine(rows, "Screen", info.screen, K.CYAN)
    addLine(rows, "Graphics", info.graphics and "Yes" or "No", K.CYAN)
    addLine(rows, "Free", tostring(info.free) .. " bytes", K.CYAN)

    if info.isTurtle then
        addSection(rows, "Turtle")
        addLine(rows, "Fuel", info.fuel or "N/A", K.YELLOW)
        if type(info.fuel) == "number" and type(info.fuelMax) == "number" and info.fuelMax > 0 then
            local pct = math.floor((info.fuel / info.fuelMax) * 100)
            addLine(rows, "Fuel Max", tostring(info.fuelMax) .. " (" .. pct .. "%)", K.YELLOW)
        elseif info.fuelMax then
            addLine(rows, "Fuel Max", info.fuelMax, K.YELLOW)
        end
        addLine(rows, "Inventory", info.invUsed .. "/16, " .. info.invTotal .. " items", K.GREEN)
        for _, item in ipairs(info.invItems) do
            addLine(rows, "", item, K.GREEN)
        end
    end

    addSection(rows, "Peripherals")
    addLine(rows, "Count", #info.peripherals, K.GREEN)
    for _, p in ipairs(info.peripherals) do
        addLine(rows, "  " .. p.name, p.type, K.GREEN)
    end

    if #info.disks > 0 then
        addSection(rows, "Disks")
        for _, disk in ipairs(info.disks) do
            addLine(rows, "  " .. disk.side, disk.label .. " (ID:" .. tostring(disk.id) .. ")", K.GREEN)
        end
    end

    return rows
end

local function clipText(text, pxWidth)
    local maxChars = math.max(0, math.floor(pxWidth / 6))
    text = tostring(text or "")
    if #text > maxChars then
        if maxChars <= 0 then return "" end
        if maxChars <= 2 then return string.rep(".", maxChars) end
        return text:sub(1, maxChars - 2) .. ".."
    end
    return text
end

local function appFastfetch()
    if not API or not R then return end

    local wx, wy, ww, wh = API.fitWindow(360, 220)
    local win = API.window("Fastfetch", wx, wy, ww, wh)
    if not win then return end

    local info = collectInfo()
    local rows = buildRows(info)
    local scroll = 0

    local function visibleRows(ch)
        return math.max(1, math.floor((ch - 46) / LINE_H))
    end

    local function clampScroll(ch)
        scroll = math.max(0, math.min(scroll, math.max(0, #rows - visibleRows(ch))))
    end

    local function refresh()
        info = collectInfo()
        rows = buildRows(info)
        clampScroll(win.ch - 21)
        API.redrawContent(win)
    end

    local function drawRows(cx, y, maxW, maxRows)
        for i = 1, maxRows do
            local row = rows[scroll + i]
            if not row then break end
            local yy = y + (i - 1) * LINE_H
            if row.section then
                local title = "-- " .. row.section .. " "
                local fill = math.max(0, math.floor(maxW / 6) - #title)
                R.drawText(cx, yy, clipText(title .. string.rep("-", fill), maxW), K.DGRAY, K.BLACK)
            else
                local text
                if row.label ~= "" then text = row.label .. ": " .. row.value else text = "  " .. row.value end
                R.drawText(cx, yy, clipText(text, maxW), row.color, K.BLACK)
            end
        end
    end

    win.onDraw = function(_, cx, cy, cw, ch)
        clampScroll(ch)

        R.drawButton(cx, cy, 52, 14, false)
        R.drawText(cx + 4, cy + 3, "Refresh", K.BLACK, K.GRAY)
        if cw >= 96 then
            R.drawButton(cx + 56, cy, 38, 14, false)
            R.drawText(cx + 62, cy + 3, "Close", K.BLACK, K.GRAY)
        end
        if cw >= 150 then
            R.drawText(cx + 102, cy + 3, clipText("R/F5 refresh", cw - 104), K.DGRAY, K.GRAY)
        end

        local bodyY = cy + 18
        local bodyH = math.max(10, ch - 32)
        R.fillRect(cx, bodyY, cw, bodyH, K.BLACK)

        local wide = cw >= 260
        local infoX = cx + 4
        local infoY = bodyY + 4
        local infoW = cw - 8

        if wide then
            for i, line in ipairs(LOGO) do
                R.drawText(cx + 8, bodyY + 8 + (i - 1) * LINE_H, line, K.CYAN, K.BLACK)
            end
            infoX = cx + LOGO_W + 22
            infoW = math.max(30, cw - (infoX - cx) - 6)
        end

        R.drawText(infoX, infoY, clipText(info.label .. "@CCOS", infoW), K.CYAN, K.BLACK)
        R.drawText(infoX, infoY + LINE_H, string.rep("-", math.max(1, math.min(36, math.floor(infoW / 6)))), K.DGRAY, K.BLACK)

        local rowY = infoY + 2 * LINE_H + 2
        local maxRows = math.max(1, math.floor((bodyY + bodyH - rowY - 2) / LINE_H))
        drawRows(infoX, rowY, infoW, maxRows)

        local footer = "Up/Down scroll  Esc close"
        if #rows > maxRows then
            footer = footer .. "  " .. tostring(scroll + 1) .. "/" .. tostring(#rows)
        end
        R.drawText(cx + 4, cy + ch - 10, clipText(footer, cw - 8), K.DGRAY, K.GRAY)
    end

    win.onClick = function(w, mx, my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 52 then
                refresh()
            elseif w.cw - 6 >= 96 and mx >= 56 and mx < 94 then
                API.close(win)
            end
        end
    end

    win.onKey = function(_, k, ch)
        if k == keys.escape then
            API.close(win)
        elseif k == keys.f5 or ch == "r" or ch == "R" then
            refresh()
        elseif k == keys.up then
            scroll = math.max(0, scroll - 1)
            API.redrawContent(win)
        elseif k == keys.down then
            scroll = math.min(math.max(0, #rows - visibleRows(win.ch - 21)), scroll + 1)
            API.redrawContent(win)
        elseif k == keys.pageUp then
            scroll = math.max(0, scroll - visibleRows(win.ch - 21))
            API.redrawContent(win)
        elseif k == keys.pageDown then
            scroll = math.min(math.max(0, #rows - visibleRows(win.ch - 21)), scroll + visibleRows(win.ch - 21))
            API.redrawContent(win)
        elseif k == keys.home then
            scroll = 0
            API.redrawContent(win)
        elseif k == keys["end"] then
            scroll = math.max(0, #rows - visibleRows(win.ch - 21))
            API.redrawContent(win)
        end
    end
end

return {
    name = "Fastfetch",
    icon = "fastfetch",
    run = appFastfetch
}
