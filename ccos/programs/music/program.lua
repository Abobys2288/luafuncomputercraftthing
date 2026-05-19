-- CCOS Program: Speaker Panel
-- Native windowed DFPWM player. No terminal takeover, monitor rendering, or monitor_touch loop.
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,GREEN=9,CYAN=7,YELLOW=13,ORANGE=14,BROWN=15,NEAR_BLACK=23}

local CHUNK_SIZE = 4 * 1024
local SCAN_LIMIT = 256
local PLAYLIST_PATH = "/ccos/config/speaker_panel.lst"

local function makeFallbackDfpwm()
    return {
        make_decoder = function()
            local charge, strength, previousBit = 0, 2, false
            return function(input)
                local out, outN = {}, 0
                for i = 1, #input do
                    local byte = input:byte(i) or 0
                    for bit = 0, 7 do
                        local currentBit = math.floor(byte / (2 ^ bit)) % 2 == 1
                        local target = currentBit and 127 or -128
                        local nextCharge = charge + math.floor((strength * (target - charge) + 512) / 1024)
                        if nextCharge == charge and nextCharge ~= target then
                            nextCharge = nextCharge + (currentBit and 1 or -1)
                        end

                        local wantedStrength = currentBit == previousBit and 1023 or 0
                        if strength ~= wantedStrength then
                            strength = strength + (currentBit == previousBit and 1 or -1)
                            if strength < 2 then strength = 2 end
                            if strength > 1023 then strength = 1023 end
                        end

                        local sample = charge + nextCharge
                        if sample > 127 then sample = 127 elseif sample < -128 then sample = -128 end
                        outN = outN + 1
                        out[outN] = sample
                        charge = nextCharge
                        previousBit = currentBit
                    end
                end
                return out
            end
        end,
    }
end

local function loadDfpwm()
    local function valid(mod)
        return type(mod) == "table" and type(mod.make_decoder) == "function"
    end

    local ok, mod
    if type(require) == "function" then
        ok, mod = pcall(require, "cc.audio.dfpwm")
        if ok and valid(mod) then return true, mod, "require" end
    end

    local globalMod = _G.cc and _G.cc.audio and _G.cc.audio.dfpwm
    if valid(globalMod) then return true, globalMod, "global" end

    local paths = {
        "/rom/modules/main/cc/audio/dfpwm.lua",
        "/rom/modules/main/cc/audio/dfpwm/init.lua",
        "/rom/modules/turtle/cc/audio/dfpwm.lua",
        "/rom/modules/command/cc/audio/dfpwm.lua",
    }
    for _, path in ipairs(paths) do
        if fs.exists(path) then
            local fn = loadfile(path)
            if fn then
                ok, mod = pcall(fn)
                if ok and valid(mod) then return true, mod, path end
            end
        end
    end

    return true, makeFallbackDfpwm(), "fallback"
end

local OK_DFPWM, DFPWM, DFPWM_SOURCE = loadDfpwm()

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R and R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, tostring(text or ""), fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or tostring(text or ""), fg, bg) end
end

local function button(x, y, w, text)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, text, K.BLACK, K.GRAY, w - 8) end
end

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizePath(path)
    path = trim(path):gsub("\\", "/")
    if path == "" then return nil end
    if path:match("^https?://") then return path end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    while path:find("//", 1, true) do path = path:gsub("//", "/") end
    if #path > 1 then path = path:gsub("/+$", "") end
    return path
end

local function fileName(path)
    if API and API.getFileName then return API.getFileName(path) end
    return tostring(path or ""):match("([^/]+)$") or tostring(path or "")
end

local function isRemote(path)
    return tostring(path or ""):match("^https?://") ~= nil
end

local function isDfpwm(path)
    return tostring(path or ""):lower():match("%.dfpwm$") ~= nil
end

local function formatBytes(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < 1024 then return tostring(bytes) .. " B" end
    if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.2f MB", bytes / (1024 * 1024))
end

local function streamUrl(url)
    if url:lower():match("%.dfpwm$") or url:find("music.madefor.cc", 1, true) then return url end
    local enc = url:gsub("[^%w%-%.%_%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return "https://music.madefor.cc/convert?url=" .. enc
end

local function appSpeakerPanel(initialPath)
    local playlist, seen = {}, {}
    local sel, scroll = 1, 0
    local current = 0
    local status = OK_DFPWM and (DFPWM_SOURCE == "fallback" and "Ready (fallback decoder)" or "Ready") or "DFPWM decoder missing"
    local lastError = ""
    local state = "stopped"
    local volume = 1.0
    local speakers, speakerLabel = {}, nil
    local decoder, handle, response = nil, nil, nil
    local pendingBuffer = nil
    local pendingAccepted = {}
    local totalBytes, readBytes = 0, 0
    local lastProgressBucket, lastProgressAt = -1, 0
    local timerId = nil
    local closed = false
    local bgTask = nil
    local win = nil
    local savePlaylist = nil
    local buttonBounds = {}
    local drawOriginX, drawOriginY = 0, 0
    local listYRel = 108

    local function mark()
        if win and win.visible then
            if API and API.redrawContent then API.redrawContent(win) else D.markDirty() end
        end
    end

    local function setStatus(text, err)
        local nextStatus = tostring(text or "")
        local nextError = err and tostring(err) or ""
        if status == nextStatus and lastError == nextError then return end
        status = nextStatus
        lastError = nextError
        mark()
    end

    local function progressPct()
        if totalBytes <= 0 then return 0 end
        return math.max(0, math.min(1, readBytes / totalBytes))
    end

    local function markProgress(force)
        local bucket = totalBytes > 0 and math.floor(progressPct() * 100) or math.floor(readBytes / CHUNK_SIZE)
        local now = os.clock()
        if force or bucket ~= lastProgressBucket or now - lastProgressAt > 0.5 then
            lastProgressBucket = bucket
            lastProgressAt = now
            mark()
        end
    end

    local function refreshSpeakers()
        local newNames = {}
        speakers, speakerLabel = {}, nil
        if peripheral and peripheral.getNames then
            for _, name in ipairs(peripheral.getNames()) do
                if peripheral.getType(name) == "speaker" then
                    local sp = peripheral.wrap(name)
                    if sp and type(sp.playAudio) == "function" then
                        speakers[#speakers + 1] = {name=name, device=sp}
                        newNames[name] = true
                    end
                end
            end
        elseif peripheral and peripheral.find then
            local sp = peripheral.find("speaker")
            if sp and type(sp.playAudio) == "function" then
                speakers[#speakers + 1] = {name="speaker", device=sp}
                newNames.speaker = true
            end
        end
        for name in pairs(pendingAccepted or {}) do
            if not newNames[name] then pendingAccepted[name] = nil end
        end
        if #speakers == 1 then speakerLabel = speakers[1].name
        elseif #speakers > 1 then speakerLabel = tostring(#speakers) .. " speakers" end
        return #speakers > 0
    end

    local function closeStream()
        if timerId and os.cancelTimer then pcall(os.cancelTimer, timerId) end
        timerId = nil
        if response then pcall(function() response.close() end) end
        if handle then pcall(function() handle.close() end) end
        response, handle, decoder, pendingBuffer = nil, nil, nil, nil
        pendingAccepted = {}
        totalBytes, readBytes = 0, 0
        lastProgressBucket = -1
    end

    local function schedule(delay)
        if closed or state ~= "playing" then return end
        if timerId then return end
        timerId = os.startTimer(delay or 0.08)
    end

    local function addTrack(path, silent)
        path = normalizePath(path)
        if not path then return false, "Empty path" end
        if not isRemote(path) then
            if not fs.exists(path) then return false, "Not found" end
            if fs.isDir(path) then return false, "Directory" end
            if not isDfpwm(path) then return false, "Only .dfpwm" end
        end
        if seen[path] then return false, "Already listed" end
        seen[path] = true
        playlist[#playlist + 1] = path
        if current == 0 then current = 1 end
        sel = #playlist
        if savePlaylist and not silent then savePlaylist() end
        return true
    end

    local function indexOfTrack(path)
        path = normalizePath(path)
        for i, item in ipairs(playlist) do
            if item == path then return i end
        end
        return nil
    end

    savePlaylist = function()
        local lines = {"# CCOS Speaker Panel playlist", "volume=" .. tostring(volume)}
        for _, path in ipairs(playlist) do
            lines[#lines + 1] = path
        end
        if API and API.writeFile then
            API.writeFile(PLAYLIST_PATH, table.concat(lines, "\n") .. "\n")
        end
    end

    local function loadPlaylist()
        local content = API and API.readFile and API.readFile(PLAYLIST_PATH) or nil
        if not content then return 0 end
        local added = 0
        for line in content:gmatch("[^\r\n]+") do
            line = trim(line)
            if line ~= "" and line:sub(1, 1) ~= "#" then
                local vol = tonumber(line:match("^volume=(.+)$") or "")
                if vol then
                    volume = math.max(0.05, math.min(3.0, vol))
                else
                    local ok = addTrack(line, true)
                    if ok then added = added + 1 end
                end
            end
        end
        if added > 0 then sel = math.max(1, math.min(sel, #playlist)) end
        return added
    end

    local function scanDir(dir)
        dir = normalizePath(dir)
        if not dir or isRemote(dir) or not fs.isDir(dir) then return 0 end
        local added = 0
        local ok, list = pcall(fs.list, dir)
        if not ok or not list then return 0 end
        table.sort(list)
        for _, name in ipairs(list) do
            if #playlist >= SCAN_LIMIT then break end
            local path = dir == "/" and ("/" .. name) or (dir .. "/" .. name)
            if fs.isDir(path) then
                if name ~= "rom" and path ~= "/ccos" then added = added + scanDir(path) end
            elseif isDfpwm(path) then
                local okAdd = addTrack(path, true)
                if okAdd then added = added + 1 end
            end
        end
        return added
    end

    local function scanDefaults()
        local added = 0
        for _, dir in ipairs({"/music", "/disk", "/disks"}) do added = added + scanDir(dir) end
        if added > 0 and savePlaylist then savePlaylist() end
        setStatus(added > 0 and ("Scanned +" .. added) or "No new .dfpwm")
    end

    local function stopAudio(keepTitle)
        state = "stopped"
        closeStream()
        for _, item in ipairs(speakers or {}) do
            if item.device and item.device.stop then pcall(function() item.device.stop() end) end
        end
        if not keepTitle then
            current = #playlist > 0 and math.max(1, math.min(current, #playlist)) or 0
        end
        setStatus("Stopped")
    end

    local function openCurrent()
        closeStream()
        if not OK_DFPWM then state = "stopped"; setStatus("DFPWM decoder missing"); return end
        if #speakers == 0 and not refreshSpeakers() then state = "stopped"; setStatus("No speaker attached"); return end
        local src = playlist[current]
        if not src then state = "stopped"; setStatus("Playlist empty"); return end

        decoder = DFPWM.make_decoder()
        totalBytes, readBytes = 0, 0
        lastProgressBucket = -1
        lastError = ""

        if isRemote(src) then
            if not http or not http.get then
                state = "stopped"
                setStatus("HTTP disabled")
                return
            end
            local ok, res = pcall(http.get, streamUrl(src), nil, true)
            if not ok or not res then
                state = "stopped"
                setStatus("HTTP failed", tostring(res or "No response"))
                return
            end
            response = res
            local code = response.getResponseCode and response.getResponseCode() or 200
            if code ~= 200 then
                local err = "HTTP " .. tostring(code)
                closeStream()
                state = "stopped"
                setStatus("Download failed", err)
                return
            end
            local headers = response.getResponseHeaders and response.getResponseHeaders() or {}
            totalBytes = tonumber(headers["Content-Length"] or headers["content-length"]) or 0
        else
            if not fs.exists(src) then state = "stopped"; setStatus("File missing", src); return end
            handle = fs.open(src, "rb")
            if not handle then state = "stopped"; setStatus("Cannot open file", src); return end
            totalBytes = fs.getSize(src) or 0
        end

        state = "playing"
        setStatus("Playing")
        markProgress(true)
        schedule(0.05)
    end

    local function playSelected()
        if #playlist == 0 then setStatus("Playlist empty"); return end
        current = math.max(1, math.min(sel, #playlist))
        openCurrent()
    end

    local function finishTrack()
        closeStream()
        if current < #playlist then
            current = current + 1
            sel = current
            openCurrent()
        else
            state = "stopped"
            setStatus("Finished")
        end
    end

    local function readBuffer()
        if not decoder then return nil, "No decoder" end
        local chunk
        if response then chunk = response.read(CHUNK_SIZE)
        elseif handle then chunk = handle.read(CHUNK_SIZE)
        else return nil, "No stream" end
        if not chunk or #chunk == 0 then return nil, "eof" end
        readBytes = readBytes + #chunk
        markProgress(false)
        local ok, buffer = pcall(decoder, chunk)
        if not ok then return nil, tostring(buffer) end
        return buffer
    end

    local function acceptPendingBuffer()
        if not pendingBuffer then return true end
        if #speakers == 0 and not refreshSpeakers() then return false end

        local allAccepted = true
        for _, item in ipairs(speakers) do
            if not pendingAccepted[item.name] then
                local ok, played = pcall(function() return item.device.playAudio(pendingBuffer, volume) end)
                if ok and played then
                    pendingAccepted[item.name] = true
                else
                    allAccepted = false
                end
            end
        end

        if allAccepted then
            pendingBuffer = nil
            pendingAccepted = {}
            return true
        end
        return false
    end

    local function pump()
        if closed or state ~= "playing" then return end
        if #speakers == 0 and not refreshSpeakers() then setStatus("No speaker attached"); return end

        if pendingBuffer then
            if acceptPendingBuffer() then
                setStatus("Playing on " .. tostring(#speakers) .. " speaker(s)")
                schedule(0.01)
            else
                schedule(0.12)
            end
            return
        end

        local buffer, err = readBuffer()
        if not buffer then
            if err == "eof" then finishTrack() else state = "stopped"; setStatus("Playback error", err) end
            return
        end

        pendingBuffer = buffer
        pendingAccepted = {}
        if acceptPendingBuffer() then
            setStatus("Playing on " .. tostring(#speakers) .. " speaker(s)")
            schedule(0.01)
        else
            schedule(0.12)
        end
    end

    local function togglePause()
        if state == "playing" then
            state = "paused"
            if timerId and os.cancelTimer then pcall(os.cancelTimer, timerId) end
            timerId = nil
            for _, item in ipairs(speakers or {}) do
                if item.device and item.device.stop then pcall(function() item.device.stop() end) end
            end
            setStatus("Paused")
        elseif state == "paused" then
            state = "playing"
            setStatus("Playing")
            schedule(0.05)
        else
            playSelected()
        end
    end

    local function nextTrack()
        if #playlist == 0 then return end
        current = math.min(#playlist, (current > 0 and current or sel) + 1)
        sel = current
        openCurrent()
    end

    local function prevTrack()
        if #playlist == 0 then return end
        current = math.max(1, (current > 0 and current or sel) - 1)
        sel = current
        openCurrent()
    end

    local function clearList()
        stopAudio(true)
        playlist, seen = {}, {}
        current, sel, scroll = 0, 1, 0
        if savePlaylist then savePlaylist() end
        setStatus("Playlist cleared")
    end

    local function changeVolume(delta)
        volume = math.max(0.05, math.min(3.0, volume + delta))
        if savePlaylist then savePlaylist() end
        setStatus("Volume " .. tostring(math.floor(volume * 100)) .. "%")
    end

    local function promptAdd()
        D.inputDialog("Add Track", "DFPWM path, folder or URL:", "/music", function(path)
            if not path or path == "" then return end
            path = normalizePath(path)
            if path and not isRemote(path) and fs.exists(path) and fs.isDir(path) then
                local added = scanDir(path)
                if added > 0 and savePlaylist then savePlaylist() end
                setStatus(added > 0 and ("Added +" .. added) or "No .dfpwm in folder")
            else
                local ok, err = addTrack(path)
                setStatus(ok and "Track added" or tostring(err))
            end
        end)
    end

    local function drawMeter(x, y, w, pct, fill)
        w = math.max(8, w or 8)
        pct = math.max(0, math.min(1, pct or 0))
        if R.drawW95Sunken then R.drawW95Sunken(x, y, w, 8)
        else R.fillRect(x, y, w, 8, K.LGRAY) end
        local inner = math.max(0, w - 4)
        R.fillRect(x + 2, y + 2, math.floor(inner * pct), 4, fill or K.DBLUE)
    end

    local function drawCone(cx, cy, w, h)
        if w < 70 or h < 48 then return end
        local x = cx + math.floor(w / 2)
        local y = cy + math.floor(h / 2) - 18
        R.fillRect(x - 18, y + 31, 36, 5, K.ORANGE)
        R.fillRect(x - 13, y + 27, 26, 5, K.YELLOW)
        R.fillRect(x - 9, y + 10, 18, 20, K.ORANGE)
        R.fillRect(x - 11, y + 20, 22, 4, K.WHITE)
        R.fillRect(x - 7, y + 13, 14, 4, K.YELLOW)
        R.fillRect(x - 5, y + 5, 10, 7, K.ORANGE)
        R.fillRect(x - 3, y + 3, 6, 3, K.YELLOW)
    end

    local function drawControl(cx, cy, id, label, w)
        button(cx, cy, w, label)
        local rx, ry = cx - drawOriginX, cy - drawOriginY
        buttonBounds[#buttonBounds + 1] = {id=id, x1=rx, x2=rx + w, y1=ry, y2=ry + 14}
        return cx + w + 3
    end

    local function toolbarHit(mx, my)
        for _, b in ipairs(buttonBounds or {}) do
            if mx >= b.x1 and mx < b.x2 and my >= b.y1 and my < b.y2 then return b.id end
        end
        return nil
    end

    local function runToolbar(id)
        if id == "play" then togglePause()
        elseif id == "stop" then stopAudio()
        elseif id == "prev" then prevTrack()
        elseif id == "next" then nextTrack()
        elseif id == "add" then promptAdd()
        elseif id == "scan" then scanDefaults()
        elseif id == "clear" then clearList()
        elseif id == "vold" then changeVolume(-0.1)
        elseif id == "volu" then changeVolume(0.1) end
    end

    local wx, wy, ww, wh = API.fitWindow(520, 300)
    win = API.window("Speaker Panel", wx, wy, ww, wh)
    if not win then return end

    bgTask = function(e, a)
        if closed then return end
        if e == "timer" and a == timerId then
            timerId = nil
            pump()
        elseif e == "speaker_audio_empty" and state == "playing" then
            pump()
        end
    end
    D.bgTasks = D.bgTasks or {}
    table.insert(D.bgTasks, bgTask)

    win.onClose = function()
        closed = true
        stopAudio(true)
        for i, task in ipairs(D.bgTasks or {}) do
            if task == bgTask then table.remove(D.bgTasks, i); break end
        end
    end

    win.onDraw = function(_, cx, cy, cw, ch)
        buttonBounds = {}
        drawOriginX, drawOriginY = cx, cy
        local track = current > 0 and playlist[current] or playlist[sel]
        local title = track and fileName(track) or "No track selected"
        local pct = progressPct()
        local volPct = math.max(0, math.min(1, volume / 3.0))

        local footerH = 10
        local libraryH = ch >= 170 and math.min(64, math.floor(ch * 0.24)) or 36
        local controlsH = 43
        local viewH = math.max(48, ch - controlsH - libraryH - footerH)
        if viewH > ch - controlsH - footerH then viewH = math.max(48, ch - controlsH - footerH) end

        R.fillRect(cx, cy, cw, viewH, K.BLACK)
        drawCone(cx, cy, cw, viewH)
        drawText(cx + 8, cy + 6, title, K.WHITE, K.BLACK, cw - 16)
        local mediaStatus = state:upper() .. "  " .. (speakerLabel and ("SPK " .. speakerLabel) or "NO SPEAKER")
        drawText(cx + 8, cy + viewH - 12, mediaStatus, speakerLabel and K.LGRAY or K.RED, K.BLACK, cw - 16)

        local controlsY = cy + viewH
        R.fillRect(cx, controlsY, cw, controlsH, K.LGRAY)
        drawMeter(cx + 8, controlsY + 4, math.max(40, cw - 16), pct, K.DBLUE)
        drawText(cx + 10, controlsY + 14, tostring(math.floor(pct * 100)) .. "%", K.DGRAY, K.LGRAY, 34)
        drawText(cx + 48, controlsY + 14, status .. (lastError ~= "" and (" : " .. lastError) or ""), lastError ~= "" and K.RED or K.DGRAY, K.LGRAY, math.max(30, cw - 56))

        local x = cx + 6
        local y = controlsY + 25
        local function ctl(id, label, w)
            if x + w <= cx + cw - 4 then x = drawControl(x, y, id, label, w) end
        end
        ctl("prev", "|<", 24)
        ctl("play", state == "playing" and "Pause" or "Play", 48)
        ctl("stop", "Stop", 38)
        ctl("next", ">|", 24)
        if cw >= 230 then
            x = x + 4
            ctl("add", "Add", 34)
            ctl("scan", "Scan", 40)
        end

        local volX = math.max(x + 6, cx + cw - 116)
        if volX + 112 <= cx + cw then
            drawText(volX, y + 3, "VOL", K.DGRAY, K.LGRAY, 20)
            drawMeter(volX + 22, y + 3, 52, volPct, K.CYAN)
            buttonBounds[#buttonBounds + 1] = {id="vold", x1=volX + 78 - cx, x2=volX + 94 - cx, y1=y - cy, y2=y - cy + 14}
            buttonBounds[#buttonBounds + 1] = {id="volu", x1=volX + 96 - cx, x2=volX + 112 - cx, y1=y - cy, y2=y - cy + 14}
            button(volX + 78, y, 16, "-")
            button(volX + 96, y, 16, "+")
        end

        local libraryY = controlsY + controlsH
        R.fillRect(cx, libraryY, cw, math.max(0, ch - (libraryY - cy) - footerH), K.GRAY)
        listYRel = libraryY - cy + 12
        local listY = cy + listYRel
        local footerY = cy + ch - 10
        local rowH = 9
        local visible = math.max(1, math.floor((footerY - listY - 2) / rowH))
        if sel <= scroll then scroll = math.max(0, sel - 1) end
        if sel > scroll + visible then scroll = sel - visible end

        drawText(cx + 4, listY - 10, "Playlist  " .. tostring(#playlist) .. " track(s)", K.BLACK, K.GRAY, cw - 56)
        if cw >= 120 then
            local clearX = cx + cw - 48
            button(clearX, listY - 13, 42, "Clear")
            buttonBounds[#buttonBounds + 1] = {id="clear", x1=clearX - cx, x2=clearX - cx + 42, y1=listY - 13 - cy, y2=listY - 13 - cy + 14}
        end
        for i = 1, visible do
            local idx = scroll + i
            local path = playlist[idx]
            if not path then break end
            local iy = listY + (i - 1) * rowH
            local active = idx == sel
            if active then R.fillRect(cx + 2, iy, cw - 4, rowH, K.DBLUE) end
            local fg, bg = active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY
            local prefix = idx == current and (state == "playing" and "> " or "= ") or "  "
            local size = (not isRemote(path) and fs.exists(path)) and (" " .. formatBytes(fs.getSize(path))) or ""
            drawText(cx + 4, iy + 1, prefix .. idx .. ". " .. fileName(path) .. size, fg, bg, cw - 8)
        end

        drawText(cx + 4, footerY, "Enter=play  Space=pause  A=add  F=scan  +/- volume", K.DGRAY, K.GRAY, cw - 8)
    end

    local function rowAt(mx, my)
        local listY = listYRel
        local footerY = win.ch - 21 - 10
        local rowH = 9
        local visible = math.max(1, math.floor((footerY - listY - 2) / rowH))
        for i = 1, visible do
            local iy = listY + (i - 1) * rowH
            if my >= iy and my < iy + rowH then
                local idx = scroll + i
                if idx >= 1 and idx <= #playlist then return idx end
            end
        end
        return nil
    end

    win.onClick = function(_, mx, my)
        local hit = toolbarHit(mx, my)
        if hit then runToolbar(hit); return end
        local idx = rowAt(mx, my)
        if idx then
            sel = idx
            mark()
        end
    end

    win.onDoubleClick = function(_, mx, my)
        if toolbarHit(mx or -1, my or -1) then return end
        local idx = rowAt(mx or -1, my or -1)
        if idx then
            sel = idx
            playSelected()
        end
    end

    win.onKey = function(_, k, ch)
        local rows = math.max(1, math.floor((win.ch - listYRel - 33) / 9))
        if k then
            if keys.up and k == keys.up and sel > 1 then
                sel = sel - 1; if sel <= scroll then scroll = math.max(0, scroll - 1) end; mark()
            elseif keys.down and k == keys.down and sel < #playlist then
                sel = sel + 1; if sel > scroll + rows then scroll = scroll + 1 end; mark()
            elseif keys.enter and k == keys.enter then playSelected()
            elseif keys.space and k == keys.space then togglePause()
            elseif keys.delete and k == keys.delete then clearList()
            elseif keys.escape and k == keys.escape then API.close(win) end
        elseif ch then
            if ch == "a" or ch == "A" then promptAdd()
            elseif ch == "f" or ch == "F" then scanDefaults()
            elseif ch == "s" or ch == "S" then stopAudio()
            elseif ch == "n" or ch == "N" then nextTrack()
            elseif ch == "b" or ch == "B" then prevTrack()
            elseif ch == "+" or ch == "=" then changeVolume(0.1)
            elseif ch == "-" or ch == "_" then changeVolume(-0.1) end
        end
    end

    win.onScroll = function(_, dir)
        local rows = math.max(1, math.floor((win.ch - listYRel - 33) / 9))
        local maxScroll = math.max(0, #playlist - rows)
        if dir < 0 then scroll = math.max(0, scroll - 3) else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#playlist, math.max(sel, scroll + 1)))
        mark()
    end

    refreshSpeakers()
    loadPlaylist()
    scanDefaults()
    if initialPath and initialPath ~= "" then
        local path = normalizePath(initialPath)
        if path and not isRemote(path) and fs.exists(path) and fs.isDir(path) then
            local added = scanDir(path)
            if added > 0 and savePlaylist then savePlaylist() end
        else
            addTrack(path)
            local idx = indexOfTrack(path)
            if idx then
                sel = idx
                current = idx
                openCurrent()
            end
        end
    end
end

return {name = "Speaker Panel", icon = "music", run = appSpeakerPanel}
