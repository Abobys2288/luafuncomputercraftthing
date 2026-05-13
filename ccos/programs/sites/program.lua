-- CCOS Program: Sites
-- Host and browse simple text pages over the CCOS rednet protocol.
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,GREEN=9}

local PAGE_DIR = "/www"
local PAGE_PATH = "/www/index.txt"

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
    if #lines == 0 then lines = {""} end
    return lines
end

local function joinLines(lines)
    return table.concat(lines, "\n")
end

local function safeName(name)
    name = tostring(name or ""):lower():gsub("%s+", "-"):gsub("[^%w%-%_]", "")
    if name == "" then name = "site" .. os.getComputerID() end
    return name
end

local function appSites()
    local net = require("ccos.drivers.net")
    local online = net.init()
    local serverId = online and net.lookup("server") or nil
    local siteName = safeName(os.getComputerLabel() or ("site" .. os.getComputerID()))
    local siteTitle = os.getComputerLabel() or siteName
    local status = online and (serverId and "Ready" or "No server") or "No modem"
    local mode = "edit"
    local viewTitle = "Local page"
    local viewLines = {}
    local lines = {}
    local cl, cc, sy = 1, 1, 0
    local lastRegister = 0

    if not fs.isDir(PAGE_DIR) then fs.makeDir(PAGE_DIR) end
    if not fs.exists(PAGE_PATH) then
        API.writeFile(PAGE_PATH, "# " .. siteTitle .. "\nWelcome to my CCOS site.\n")
    end
    lines = splitLines(API.readFile(PAGE_PATH) or "")
    viewLines = lines

    local wx, wy, ww, wh = API.fitWindow(310, 190)
    local w = API.window("Sites", wx, wy, ww, wh)
    if not w then return end

    local function savePage()
        API.writeFile(PAGE_PATH, joinLines(lines))
        status = "Saved " .. PAGE_PATH
        API.redrawContent(w)
    end

    local function registerSite()
        if not online then status = "No modem"; API.redrawContent(w); return end
        serverId = serverId or net.lookup("server")
        if not serverId then status = "No server"; API.redrawContent(w); return end
        savePage()
        net.siteRegister(serverId, siteName, siteTitle)
        lastRegister = os.clock()
        status = "Registered site:" .. siteName
        API.redrawContent(w)
    end

    local function openSite(name)
        if not online then status = "No modem"; API.redrawContent(w); return end
        serverId = serverId or net.lookup("server")
        if not serverId then status = "No server"; API.redrawContent(w); return end
        status = "Resolving " .. name .. "..."
        API.redrawContent(w)
        local hostId = net.siteResolve(serverId, name)
        if not hostId then status = "Site not found"; API.redrawContent(w); return end
        local content, title = net.siteGet(hostId, name, "index.txt")
        if content then
            viewTitle = title or name
            viewLines = splitLines(content)
            mode = "view"
            sy = 0
            status = "Opened " .. name .. " from " .. hostId
        else
            status = "Host did not respond"
        end
        API.redrawContent(w)
    end

    local function listSites()
        if not online then status = "No modem"; API.redrawContent(w); return end
        serverId = serverId or net.lookup("server")
        if not serverId then status = "No server"; API.redrawContent(w); return end
        local sites = net.siteList(serverId)
        viewLines = {}
        if #sites == 0 then
            viewLines = {"No registered sites."}
        else
            for _, site in ipairs(sites) do
                table.insert(viewLines, site.name .. " - " .. (site.title or "") .. " (" .. site.id .. ")")
            end
        end
        viewTitle = "Sites"
        mode = "view"
        sy = 0
        status = #sites .. " site(s)"
        API.redrawContent(w)
    end

    local bgTask = function(e, a, b)
        if e == "timer" then
            if online and serverId and os.clock() - lastRegister > 20 then
                net.siteRegister(serverId, siteName, siteTitle)
                lastRegister = os.clock()
            end
        elseif e == "rednet_message" then
            local id, raw = a, b
            if type(raw) == "table" and raw.proto == net.protocol then
                local msg = raw.data or raw
                if type(msg) == "table" and msg.type == "site_get" and msg.name == siteName then
                    local content = API.readFile(PAGE_PATH) or ""
                    net.send(id, {type="site_content", name=siteName, title=siteTitle, content=content})
                end
            end
        end
    end

    if not D.bgTasks then D.bgTasks = {} end
    table.insert(D.bgTasks, bgTask)
    w.onClose = function()
        for i, task in ipairs(D.bgTasks or {}) do
            if task == bgTask then table.remove(D.bgTasks, i); break end
        end
    end

    w.onDraw = function(_, cx, cy, cw, ch)
        button(cx, cy, 54, "Register")
        if cw >= 108 then button(cx + 58, cy, 42, "Open") end
        if cw >= 154 then button(cx + 104, cy, 42, "Sites") end
        if cw >= 204 then button(cx + 150, cy, 46, mode == "edit" and "View" or "Edit") end
        if cw >= 252 then button(cx + 200, cy, 44, "Save") end

        drawText(cx + 4, cy + 18, "site:" .. siteName .. "  " .. status, K.DGRAY, K.GRAY, cw - 8)
        local areaY = cy + 30
        local rows = math.max(1, math.floor((ch - 44) / 8))
        local activeLines = mode == "edit" and lines or viewLines
        local title = mode == "edit" and ("Editing " .. PAGE_PATH) or viewTitle
        drawText(cx + 4, areaY, title, K.DBLUE, K.GRAY, cw - 8)

        for i = 1, rows do
            local idx = sy + i
            local line = activeLines[idx]
            if not line then break end
            local y = areaY + 10 + (i - 1) * 8
            drawText(cx + 4, y, line, K.BLACK, K.GRAY, cw - 8)
        end

        if mode == "edit" and cl > sy and cl <= sy + rows then
            local cursorX = cx + 4 + (cc - 1) * 6
            local cursorY = areaY + 10 + (cl - sy - 1) * 8
            if cursorX < cx + cw - 6 then R.fillRect(cursorX, cursorY, 6, 8, K.DBLUE) end
        end

        drawText(cx + 4, cy + ch - 10, "Ctrl? no. Enter newline  F5 register  Esc close", K.DGRAY, K.GRAY, cw - 8)
    end

    w.onClick = function(_, mx, my)
        if my >= 0 and my < 14 then
            if mx < 54 then registerSite()
            elseif mx >= 58 and mx < 100 then
                D.inputDialog("Open Site", "Site name:", siteName, function(name) if name then openSite(safeName(name)) end end)
            elseif mx >= 104 and mx < 146 then listSites()
            elseif mx >= 150 and mx < 196 then mode = mode == "edit" and "view" or "edit"; viewLines = lines; API.redrawContent(w)
            elseif mx >= 200 and mx < 244 then savePage()
            end
        else
            local row = math.floor((my - 40) / 8) + 1
            if mode == "edit" and row >= 1 and row <= #lines then
                cl = math.max(1, math.min(#lines, sy + row))
                cc = math.min(#(lines[cl] or "") + 1, math.max(1, math.floor((mx - 4) / 6) + 1))
                API.redrawContent(w)
            end
        end
    end

    w.onKey = function(_, k, ch)
        local rows = math.max(1, math.floor((w.ch - 21 - 44) / 8))
        if mode == "edit" and ch then
            local line = lines[cl] or ""
            lines[cl] = line:sub(1, cc - 1) .. ch .. line:sub(cc)
            cc = cc + 1
            API.redrawContent(w)
        elseif k == keys.f5 then registerSite()
        elseif k == keys.escape then API.close(w)
        elseif k == keys.up then
            if mode == "edit" and cl > 1 then cl = cl - 1; cc = math.min(cc, #(lines[cl] or "") + 1); if cl <= sy then sy = math.max(0, sy - 1) end
            else sy = math.max(0, sy - 1) end
            API.redrawContent(w)
        elseif k == keys.down then
            local count = #(mode == "edit" and lines or viewLines)
            if mode == "edit" and cl < #lines then cl = cl + 1; cc = math.min(cc, #(lines[cl] or "") + 1); if cl > sy + rows then sy = sy + 1 end
            else sy = math.min(math.max(0, count - rows), sy + 1) end
            API.redrawContent(w)
        elseif mode == "edit" and k == keys.left then
            cc = math.max(1, cc - 1); API.redrawContent(w)
        elseif mode == "edit" and k == keys.right then
            cc = math.min(#(lines[cl] or "") + 1, cc + 1); API.redrawContent(w)
        elseif mode == "edit" and k == keys.backspace then
            local line = lines[cl] or ""
            if cc > 1 then lines[cl] = line:sub(1, cc - 2) .. line:sub(cc); cc = cc - 1
            elseif cl > 1 then
                local prevLen = #(lines[cl - 1] or "")
                lines[cl - 1] = (lines[cl - 1] or "") .. line
                table.remove(lines, cl)
                cl = cl - 1
                cc = prevLen + 1
            end
            API.redrawContent(w)
        elseif mode == "edit" and k == keys.enter then
            local line = lines[cl] or ""
            lines[cl] = line:sub(1, cc - 1)
            table.insert(lines, cl + 1, line:sub(cc))
            cl = cl + 1
            cc = 1
            if cl > sy + rows then sy = sy + 1 end
            API.redrawContent(w)
        end
    end
end

return {name = "Sites", icon = "sites", run = appSites}
