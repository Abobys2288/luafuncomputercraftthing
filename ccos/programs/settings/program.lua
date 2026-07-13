-- CCOS Program: Settings
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,GREEN=9,RED=11,DBLUE=19,CYAN=7}

local function text(x, y, value, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, value, fg, bg, w)
    else R.drawText(x, y, tostring(value or ""), fg, bg) end
end

local function button(x, y, w, label, active)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, label, active, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, active); text(x + 4, y + 3, label, K.BLACK, K.GRAY, w - 8) end
end

local function fileSize(path)
    local ok, size = pcall(fs.getSize, path)
    return ok and tostring(size) or "0"
end

local function readTail(path, maxLines)
    if not fs.exists(path) then return {"No crash log yet."} end
    local f = fs.open(path, "r")
    if not f then return {"Cannot open crash log."} end
    local lines = {}
    while true do
        local line = f.readLine()
        if not line then break end
        lines[#lines + 1] = line
        if #lines > maxLines then table.remove(lines, 1) end
    end
    f.close()
    if #lines == 0 then lines[1] = "Crash log is empty." end
    return lines
end

local function appSettings()
    local wx, wy, ww, wh = API.fitWindow(330, 210)
    local win = API.window("Settings", wx, wy, ww, wh)
    if not win then return end

    local tab = "system"
    local status = "Ready"
    local tabs = {
        {id="system", label="System", w=54},
        {id="appearance", label="Look", w=44},
        {id="logs", label="Logs", w=42},
    }

    local function freeSpace()
        local free = "?"
        pcall(function() free = tostring(fs.getFreeSpace("/")) end)
        return free
    end

    local function setStatus(value, tone)
        status = value
        if API and API.notify and tone then API.notify("Settings", value, tone, 3) end
        D.markContentDirty(win)
    end

    local function themeLabel()
        local theme = D.themes and D.themes[D.themeName or "classic"]
        return (theme and theme.label) or tostring(D.themeName or "classic")
    end

    local function action(id)
        if id == "label" then
            D.inputDialog("Set Label", "Computer label:", os.getComputerLabel and (os.getComputerLabel() or "") or "", function(name)
                if name and os.setComputerLabel then os.setComputerLabel(name); setStatus("Label saved", "ok") end
            end)
        elseif id == "layout" then
            D.inputLayout = D.inputLayout == "RU" and "EN" or "RU"
            setStatus("Layout: " .. D.inputLayout, "ok")
        elseif id == "save" then
            local ok, err = true, nil
            if D.saveConfig then ok, err = D.saveConfig() end
            if ok then setStatus("Settings saved", "ok")
            else setStatus(tostring(err or "Save failed")) end
        elseif id == "reload" then
            if D.loadPrograms then D.loadPrograms() end
            setStatus("Programs reloaded", "ok")
            D.markDirty()
        elseif id == "theme" then
            if D.nextTheme then D.nextTheme() end
            setStatus("Theme: " .. themeLabel(), "ok")
        elseif id == "wallpaper" then
            if API and API.chooseFile then
                API.chooseFile({title="Choose Wallpaper", path="/", extensions={"nfp","nfp256","nfpc"}}, function(path)
                    if path and path ~= "" then
                        if D.setWallpaper then D.setWallpaper(path) end
                        setStatus("Wallpaper: " .. path, "ok")
                    end
                end)
            end
        elseif id == "clearwall" then
            if D.setWallpaper then D.setWallpaper(nil) end
            D.wallpaperConfigPath = nil
            setStatus("Wallpaper cleared", "ok")
        elseif id == "sound" then
            D.soundEnabled = D.soundEnabled == false
            setStatus("Sound: " .. (D.soundEnabled and "on" or "off"), "ok")
        elseif id == "notify" then
            D.notificationsEnabled = D.notificationsEnabled == false
            setStatus("Notifications: " .. (D.notificationsEnabled and "on" or "off"), "ok")
        elseif id == "testnotify" then
            if API and API.notify then API.notify("CCOS", "Notifications are working", "ok", 4) end
        elseif id == "clearlog" then
            if fs.exists(D.crashLogPath) then fs.delete(D.crashLogPath) end
            D.crashCount = 0
            setStatus("Crash log cleared", "ok")
        elseif id == "reboot" then
            os.reboot()
        elseif id == "power" then
            os.shutdown()
        end
    end

    local function drawTabs(cx, cy)
        local x = cx
        for _, t in ipairs(tabs) do
            button(x, cy, t.w, t.label, tab == t.id)
            x = x + t.w + 2
        end
    end

    local function hitTab(mx, my)
        if my < 0 or my >= 14 then return nil end
        local x = 0
        for _, t in ipairs(tabs) do
            if mx >= x and mx < x + t.w then return t.id end
            x = x + t.w + 2
        end
        return nil
    end

    local function drawActionGrid(cx, cy, cw, y, actions)
        local cols = cw >= 220 and 3 or 2
        local gap = 6
        local bw = math.floor((cw - 8 - (cols - 1) * gap) / cols)
        for i, a in ipairs(actions) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            button(cx + 4 + col * (bw + gap), cy + y + row * 20, bw, a.label)
        end
        return cols, bw, gap
    end

    local function actionAt(mx, my, startY, actions, cw)
        local cols = cw >= 220 and 3 or 2
        local gap = 6
        local bw = math.floor((cw - 8 - (cols - 1) * gap) / cols)
        for i, a in ipairs(actions) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x = 4 + col * (bw + gap)
            local y = startY + row * 20
            if mx >= x and mx < x + bw and my >= y and my < y + 14 then return a.id end
        end
        return nil
    end

    local systemActions = {
        {id="label", label="Label"},
        {id="layout", label="Layout"},
        {id="save", label="Save"},
        {id="reload", label="Reload"},
        {id="reboot", label="Reboot"},
        {id="power", label="Power"},
    }
    local lookActions = {
        {id="theme", label="Theme"},
        {id="wallpaper", label="Wallpaper"},
        {id="clearwall", label="Clear WP"},
        {id="sound", label="Sound"},
        {id="notify", label="Notify"},
        {id="testnotify", label="Test"},
        {id="save", label="Save"},
    }
    local logActions = {
        {id="clearlog", label="Clear Log"},
        {id="save", label="Save"},
    }

    win.onDraw = function(_, cx, cy, cw, ch)
        R.fillRect(cx, cy, cw, ch, K.GRAY)
        drawTabs(cx, cy)
        local y = 22

        if tab == "system" then
            local label = os.getComputerLabel and (os.getComputerLabel() or "None") or "None"
            local id = os.getComputerID and os.getComputerID() or "?"
            text(cx + 4, cy + y, "Label: " .. label, K.BLACK, K.GRAY, cw - 8); y = y + 12
            text(cx + 4, cy + y, "ID: " .. id .. "  Screen: " .. R.w .. "x" .. R.h, K.BLACK, K.GRAY, cw - 8); y = y + 12
            text(cx + 4, cy + y, "Free: " .. freeSpace() .. " bytes", K.BLACK, K.GRAY, cw - 8); y = y + 12
            text(cx + 4, cy + y, "Windows: " .. tostring(#(D.windows or {})) .. "  Programs: " .. tostring(#(D.programs or {})), K.BLACK, K.GRAY, cw - 8); y = y + 18
            drawActionGrid(cx, cy, cw, y, systemActions)
        elseif tab == "appearance" then
            text(cx + 4, cy + y, "Theme: " .. themeLabel(), K.BLACK, K.GRAY, cw - 8); y = y + 12
            local wp = D.wallpaperPath or (D.wallpaperConfigPath or "none")
            text(cx + 4, cy + y, "Wallpaper: " .. (D.wallpaper and wp or "none"), K.BLACK, K.GRAY, cw - 8); y = y + 12
            text(cx + 4, cy + y, "Layout: " .. tostring(D.inputLayout or "EN"), K.BLACK, K.GRAY, cw - 8); y = y + 12
            text(cx + 4, cy + y, "Sound: " .. (D.soundEnabled == false and "off" or "on"), K.BLACK, K.GRAY, cw - 8); y = y + 12
            text(cx + 4, cy + y, "Notifications: " .. (D.notificationsEnabled == false and "off" or "on"), K.BLACK, K.GRAY, cw - 8); y = y + 18
            drawActionGrid(cx, cy, cw, y, lookActions)
        else
            local logPath = D.crashLogPath or "/ccos/logs/crashes.log"
            text(cx + 4, cy + y, "Crash log: " .. fileSize(logPath) .. " bytes", K.BLACK, K.GRAY, cw - 8); y = y + 12
            text(cx + 4, cy + y, "Crashes this session: " .. tostring(D.crashCount or 0), K.BLACK, K.GRAY, cw - 8); y = y + 12
            for _, line in ipairs(readTail(logPath, math.max(3, math.floor((ch - 96) / 9)))) do
                text(cx + 4, cy + y, line, K.DGRAY, K.GRAY, cw - 8)
                y = y + 9
            end
            drawActionGrid(cx, cy, cw, ch - 42, logActions)
        end

        text(cx + 4, cy + ch - 10, status, status == "Ready" and K.DGRAY or K.GREEN, K.GRAY, cw - 8)
    end

    win.onClick = function(_, mx, my)
        local hit = hitTab(mx, my)
        if hit then tab = hit; D.markContentDirty(win); return end
        local cw = win.cw - 6
        if tab == "system" then
            local id = actionAt(mx, my, 76, systemActions, cw)
            if id then action(id) end
        elseif tab == "appearance" then
            local id = actionAt(mx, my, 76, lookActions, cw)
            if id then action(id) end
        else
            local id = actionAt(mx, my, (win.ch - 21) - 42, logActions, cw)
            if id then action(id) end
        end
    end

    win.onKey = function(_, k, ch)
        if k == keys.escape then API.close(win)
        elseif ch == "1" then tab = "system"; D.markContentDirty(win)
        elseif ch == "2" then tab = "appearance"; D.markContentDirty(win)
        elseif ch == "3" then tab = "logs"; D.markContentDirty(win)
        elseif ch == "t" or ch == "T" then action("theme")
        elseif ch == "s" or ch == "S" then action("save") end
    end
end

return {name = "Settings", icon = "settings", run = appSettings}
