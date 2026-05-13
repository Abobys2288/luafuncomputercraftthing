--[[
    CCOS Site Server v1
    Registry-only server for CCOS Sites.

    Run on a dedicated CC:Tweaked computer with a modem. Site Builder computers
    register their site names here, and Sites Browser resolves/list them here.
]]

local PROTOCOL = "CCOS_NET"
local SERVICE_NAME = "siteserver"
local HOST_NAME = os.getComputerLabel() or ("siteserver_" .. os.getComputerID())
local LOG_FILE = "/ccos_siteserver.log"
local SITE_TTL = 60

local sites = {}
local running = true

local function initModem()
    for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            return true, side
        end
    end
    return false
end

local function ensureDir(path)
    local dir = path and path:match("(.+)/[^/]+")
    if not dir then return end
    local build = ""
    for part in dir:gmatch("[^/]+") do
        build = build .. "/" .. part
        if not fs.exists(build) then fs.makeDir(build) end
    end
end

local function log(msg)
    local time = os.time and os.time() or 0
    local h = math.floor(time)
    local m = math.floor((time - h) * 60)
    local line = string.format("[%02d:%02d] %s", h, m, tostring(msg))
    print(line)
    ensureDir(LOG_FILE)
    local f = fs.open(LOG_FILE, "a")
    if f then f.writeLine(line); f.close() end
end

local function sendMsg(targetId, msg)
    rednet.send(targetId, {proto = PROTOCOL, data = msg}, PROTOCOL)
end

local function cleanName(name)
    name = tostring(name or ""):lower():gsub("%s+", "-"):gsub("[^%w%-%_]", "")
    return name
end

local function cleanup()
    local now = os.clock()
    for name, site in pairs(sites) do
        if now - (site.lastSeen or 0) > SITE_TTL then
            sites[name] = nil
            log("[EXPIRE] " .. name)
        end
    end
end

local handlers = {}

handlers.discover = function(id)
    sendMsg(id, {type = "discover_ok", host = HOST_NAME, role = "siteserver", id = os.getComputerID()})
end

handlers.heartbeat = function(id, msg)
    local name = cleanName(msg.site or msg.name)
    if name ~= "" and sites[name] and sites[name].id == id then
        sites[name].lastSeen = os.clock()
    end
end

handlers.site_register = function(id, msg)
    local name = cleanName(msg.name)
    if name == "" then
        sendMsg(id, {type = "site_register_fail", reason = "empty name"})
        return
    end
    sites[name] = {
        name = name,
        title = msg.title or name,
        host = msg.host or tostring(id),
        id = id,
        lastSeen = os.clock(),
    }
    sendMsg(id, {type = "site_register_ok", name = name, id = id})
    log("[SITE] " .. name .. " -> " .. id)
end

handlers.site_resolve = function(id, msg)
    local name = cleanName(msg.name)
    local site = sites[name]
    if site then
        site.lastSeen = os.clock()
        sendMsg(id, {type = "site_resolve_ok", name = site.name, id = site.id, site = site})
    else
        sendMsg(id, {type = "site_resolve_fail", name = name})
    end
end

handlers.site_list = function(id)
    cleanup()
    local list = {}
    for _, site in pairs(sites) do
        list[#list + 1] = {name = site.name, title = site.title, host = site.host, id = site.id}
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    sendMsg(id, {type = "site_list_resp", sites = list})
end

local function handleMessage(id, raw)
    if type(raw) ~= "table" or raw.proto ~= PROTOCOL then return end
    local msg = raw.data or raw
    if type(msg) ~= "table" then return end
    local handler = handlers[msg.type]
    if handler then
        local ok, err = pcall(handler, id, msg)
        if not ok then log("[ERR] " .. tostring(msg.type) .. ": " .. tostring(err)) end
    end
end

local commands = {}

commands.help = function()
    print("")
    print("  sites             list registered sites")
    print("  forget <name>     remove one site")
    print("  clear             clear console")
    print("  quit / q          stop server")
    print("")
end

commands.sites = function()
    cleanup()
    print("")
    if next(sites) == nil then print("  No sites registered.")
    else
        for name, site in pairs(sites) do
            print("  " .. name .. " -> " .. site.id .. " (" .. tostring(site.title) .. ")")
        end
    end
    print("")
end

commands.forget = function(args)
    local name = cleanName(args[1])
    if name == "" then print("  Usage: forget <name>"); return end
    sites[name] = nil
    log("[FORGET] " .. name)
end

commands.clear = function()
    term.clear()
    term.setCursorPos(1, 1)
end

commands.quit = function() running = false end
commands.q = commands.quit

local function processInput(line)
    line = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" then return end
    local parts = {}
    for part in line:gmatch("%S+") do parts[#parts + 1] = part end
    local cmd = table.remove(parts, 1):lower()
    if commands[cmd] then commands[cmd](parts)
    else print("  Unknown command: " .. cmd .. " (type help)") end
end

local ok, side = initModem()
if not ok then
    print("[FATAL] No modem found. Attach modem and retry.")
    return
end

rednet.host(PROTOCOL, SERVICE_NAME)
log("========================================")
log("  CCOS Site Server started")
log("  Host:  " .. HOST_NAME)
log("  ID:    " .. os.getComputerID())
log("  Modem: " .. side)
log("  Proto: " .. PROTOCOL .. " / " .. SERVICE_NAME)
log("========================================")
log("  Type 'help' for commands.")

local function serverLoop()
    while running do
        local id, raw = rednet.receive(PROTOCOL, 2)
        if id then handleMessage(id, raw) end
        cleanup()
    end
end

local function consoleLoop()
    while running do
        write("sites> ")
        processInput(read())
    end
end

parallel.waitForAny(serverLoop, consoleLoop)

log("Site server shutting down...")
rednet.unhost(PROTOCOL, SERVICE_NAME)
