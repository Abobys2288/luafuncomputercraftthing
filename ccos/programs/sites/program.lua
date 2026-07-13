-- CCOS Program: Sites Browser
-- Browse simple CCOS text pages hosted by Site Builder computers.
-- All network operations are async — UI never freezes.
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,GREEN=9}

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or text, fg, bg) end
end

local function button(x, y, w, text)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, text, K.BLACK, K.GRAY, w - 8) end
end

local function splitLines(text)
    local lines = {}
    text = tostring(text or "")
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end
    if #lines == 0 then lines = {"No content."} end
    return lines
end

local function safeName(name)
    name = tostring(name or ""):lower():gsub("%s+", "-"):gsub("[^%w%-%_]", "")
    return name
end

local function appSitesBrowser()
    local net = require("ccos.drivers.net")
    local online = net.init()
    local serverId = nil
    local status = online and "Looking for server..." or "No modem"
    local address = ""
    local title = "Sites"
    local lines = {"Enter a site name or click List."}
    local sy = 0
    local siteList = {}
    local sel = 1
    local mode = "page"
    local busy = false

    -- Async server lookup
    if online then
        net.lookupSiteServerAsync(4, function(id)
            serverId = id
            status = id and "Ready" or "No server"
            D.markDirty()
            if id then listSites() end
        end)
    end

    local wx, wy, ww, wh = API.fitWindow(310, 190)
    local w = API.window("Sites Browser", wx, wy, ww, wh)
    if not w then return end

    local function ensureServer()
        if not online then status = "No modem"; return false end
        if not serverId then status = "No server"; return false end
        return true
    end

    local function openSite(name)
        name = safeName(name)
        if name == "" then status = "Enter site name"; API.redrawContent(w); return end
        if not ensureServer() then API.redrawContent(w); return end
        if busy then return end
        busy = true
        status = "Resolving " .. name .. "..."
        API.redrawContent(w)
        net.siteResolveAsync(serverId, name, function(hostId)
            if not hostId then
                status = "Site not found: " .. name
                busy = false
                API.redrawContent(w)
                return
            end
            status = "Connecting to " .. hostId .. "..."
            API.redrawContent(w)
            net.siteGetAsync(hostId, name, "index.txt", function(content, gotTitle)
                busy = false
                if content then
                    address = name
                    title = gotTitle or name
                    lines = splitLines(content)
                    sy = 0
                    mode = "page"
                    status = "Opened " .. name .. " from " .. hostId
                else
                    status = "Host did not respond"
                end
                API.redrawContent(w)
            end)
        end)
    end

    local function listSites()
        if not ensureServer() then API.redrawContent(w); return end
        if busy then return end
        busy = true
        status = "Loading site list..."
        API.redrawContent(w)
        net.siteListAsync(serverId, function(sites)
            busy = false
            siteList = sites or {}
            table.sort(siteList, function(a, b) return tostring(a.name) < tostring(b.name) end)
            lines = {}
            if #siteList == 0 then
                lines = {"No sites registered."}
            else
                for _, site in ipairs(siteList) do
                    table.insert(lines, site.name .. " - " .. (site.title or "") .. " (" .. site.id .. ")")
                end
            end
            mode = "list"
            title = "Available Sites"
            sy = 0
            sel = 1
            status = #siteList .. " site(s)"
            API.redrawContent(w)
        end)
    end

    local function promptOpen()
        D.inputDialog("Open Site", "Site name:", address, function(name)
            if name then openSite(name) end
        end)
    end

    w.onDraw = function(_, cx, cy, cw, ch)
        button(cx, cy, 38, "Open")
        if cw >= 86 then button(cx + 42, cy, 38, "List") end
        if cw >= 142 then button(cx + 84, cy, 52, "Refresh") end
        if cw >= 190 then drawText(cx + 142, cy + 3, status, busy and K.DBLUE or K.DGRAY, K.GRAY, cw - 146) end

        R.drawW95Sunken(cx, cy + 18, math.max(8, cw), 14)
        drawText(cx + 4, cy + 21, address ~= "" and ("site://" .. address) or "site://", K.BLACK, K.GRAY, cw - 8)

        drawText(cx + 4, cy + 38, title, K.DBLUE, K.GRAY, cw - 8)
        local listY = cy + 50
        local rows = math.max(1, math.floor((ch - 64) / 8))
        for i = 1, rows do
            local idx = sy + i
            local line = lines[idx]
            if not line then break end
            local iy = listY + (i - 1) * 8
            local active = mode == "list" and idx == sel
            if active then R.fillRect(cx + 2, iy, cw - 4, 8, K.DBLUE) end
            drawText(cx + 4, iy, line, active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY, cw - 8)
        end
        drawText(cx + 4, cy + ch - 10, "Enter=open  F5=list  Esc=close", K.DGRAY, K.GRAY, cw - 8)
    end

    w.onClick = function(_, mx, my)
        if my >= 0 and my < 14 then
            if mx < 38 then promptOpen()
            elseif mx >= 42 and mx < 80 then listSites()
            elseif mx >= 84 and mx < 136 then if mode == "page" and address ~= "" then openSite(address) else listSites() end end
            return
        end
        if mode == "list" then
            local row = math.floor((my - 50) / 8) + 1
            if row >= 1 then
                sel = math.min(#siteList, sy + row)
                API.redrawContent(w)
            end
        end
    end

    w.onDoubleClick = function()
        if mode == "list" and siteList[sel] then openSite(siteList[sel].name) end
    end

    w.onKey = function(_, k)
        local rows = math.max(1, math.floor((w.ch - 21 - 64) / 8))
        if k == keys.enter then
            if mode == "list" and siteList[sel] then openSite(siteList[sel].name) else promptOpen() end
        elseif k == keys.f5 then listSites()
        elseif k == keys.escape then API.close(w)
        elseif k == keys.up then
            if mode == "list" and sel > 1 then sel = sel - 1; if sel <= sy then sy = math.max(0, sy - 1) end
            else sy = math.max(0, sy - 1) end
            API.redrawContent(w)
        elseif k == keys.down then
            if mode == "list" and sel < #siteList then sel = sel + 1; if sel > sy + rows then sy = sy + 1 end
            else sy = math.min(math.max(0, #lines - rows), sy + 1) end
            API.redrawContent(w)
        elseif k == keys.pageUp then sy = math.max(0, sy - rows); API.redrawContent(w)
        elseif k == keys.pageDown then sy = math.min(math.max(0, #lines - rows), sy + rows); API.redrawContent(w)
        end
    end

    w.onScroll = function(_, dir)
        local rows = math.max(1, math.floor((w.ch - 21 - 64) / 8))
        local maxScroll = math.max(0, #lines - rows)
        if dir < 0 then sy = math.max(0, sy - 3)
        else sy = math.min(maxScroll, sy + 3) end
        if mode == "list" then sel = math.max(1, math.min(#siteList, math.max(sel, sy + 1))) end
        API.redrawContent(w)
    end

    if serverId then listSites() end
end

return {name = "Sites Browser", icon = "sites", run = appSitesBrowser}
