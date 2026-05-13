--[[
    CCOS Server v3 - Network Backend
    DNS registry, chat relay, package serving, and simple site registry.
    Run standalone on a dedicated CC:Tweaked computer with a modem.
]]

local PROTOCOL = "CCOS_NET"
local SERVICE_NAME = "server"
local HOST_NAME = os.getComputerLabel() or ("server_" .. os.getComputerID())
local LOG_FILE = "/ccos_server.log"
local MAX_HISTORY = 50

local clients = {}
local dns = {}
local banned = {}
local chatHistory = {}
local sites = {}
local running = true

local sendMsg
local broadcastMsg

local function initModem()
    for _, side in ipairs({"top","bottom","left","right","front","back"}) do
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

local function readFile(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local data = f.readAll()
    f.close()
    return data
end

local function addChat(line)
    table.insert(chatHistory, line)
    if #chatHistory > MAX_HISTORY then table.remove(chatHistory, 1) end
end

local function isBanned(id)
    return banned[id] == true
end

local function touchClient(id, name)
    local old = clients[id]
    clients[id] = {name = name or (old and old.name) or ("guest_" .. id), lastSeen = os.clock()}
    dns[clients[id].name] = id
end

sendMsg = function(targetId, msg)
    rednet.send(targetId, {proto = PROTOCOL, data = msg}, PROTOCOL)
end

broadcastMsg = function(msg)
    rednet.broadcast({proto = PROTOCOL, data = msg}, PROTOCOL)
end

local function relayChat(from, text)
    local line = "[" .. tostring(from) .. "] " .. tostring(text or "")
    addChat(line)
    log("[CHAT] " .. line)
    broadcastMsg({type = "chat", from = from, text = text or ""})
end

local function builtInPackages()
    local list = {}
    if fs.exists("/ccos/packages.lua") then
        local fn = loadfile("/ccos/packages.lua")
        if fn then
            local ok, packages = pcall(fn)
            if ok and type(packages) == "table" then
                for _, pkg in ipairs(packages) do
                    table.insert(list, {
                        name = pkg.name,
                        title = pkg.title or pkg.name,
                        desc = pkg.desc or "",
                        icon = pkg.icon,
                        files = pkg.files,
                    })
                end
            end
        end
    end
    if fs.isDir("/ccos/programs") then
        for _, name in ipairs(fs.list("/ccos/programs")) do
            if fs.exists("/ccos/programs/" .. name .. "/program.lua") then
                local exists = false
                for _, pkg in ipairs(list) do if pkg.name == name then exists = true; break end end
                if not exists then table.insert(list, {name = name, title = name, desc = "Installed program"}) end
            end
        end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return list
end

local handlers = {}

handlers.register = function(id, msg)
    if isBanned(id) then return end
    local name = msg.name or ("guest_" .. id)
    touchClient(id, name)
    sendMsg(id, {type = "register_ok", name = name, id = id})
    log("[DNS] " .. name .. " -> " .. id)
end

handlers.resolve = function(id, msg)
    local name = msg.name
    local found = name and dns[name]
    sendMsg(id, found and {type = "resolve_ok", name = name, id = found} or {type = "resolve_fail", name = name})
end

handlers.heartbeat = function(id, msg)
    touchClient(id, msg.name)
end

handlers.chat = function(id, msg)
    if isBanned(id) then return end
    local from = msg.from or (clients[id] and clients[id].name) or tostring(id)
    relayChat(from, msg.text or "")
end

handlers.discover = function(id)
    sendMsg(id, {type = "discover_ok", host = HOST_NAME, id = os.getComputerID()})
end

handlers.pkg_list = function(id)
    sendMsg(id, {type = "pkg_list_resp", packages = builtInPackages()})
end

handlers.pkg_get = function(id, msg)
    local pkg = tostring(msg.name or "")
    local path = "/ccos/programs/" .. pkg .. "/program.lua"
    local content = readFile(path)
    sendMsg(id, {type = "pkg_get_resp", name = pkg, content = content, path = path})
end

handlers.site_register = function(id, msg)
    if isBanned(id) then return end
    local name = tostring(msg.name or ""):gsub("%s+", "_")
    if name == "" then
        sendMsg(id, {type = "site_register_fail", reason = "empty name"})
        return
    end
    sites[name] = {
        name = name,
        title = msg.title or name,
        host = msg.host or (clients[id] and clients[id].name) or tostring(id),
        id = id,
        lastSeen = os.clock(),
    }
    dns["site:" .. name] = id
    sendMsg(id, {type = "site_register_ok", name = name, id = id})
    log("[SITE] " .. name .. " -> " .. id)
end

handlers.site_resolve = function(id, msg)
    local site = sites[msg.name or ""]
    if site then
        site.lastSeen = os.clock()
        sendMsg(id, {type = "site_resolve_ok", name = site.name, id = site.id, site = site})
    else
        sendMsg(id, {type = "site_resolve_fail", name = msg.name})
    end
end

handlers.site_list = function(id)
    local list = {}
    for _, site in pairs(sites) do
        table.insert(list, {name = site.name, title = site.title, host = site.host, id = site.id})
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    sendMsg(id, {type = "site_list_resp", sites = list})
end

local function handleMessage(id, raw)
    if type(raw) ~= "table" or raw.proto ~= PROTOCOL then return end
    if isBanned(id) then return end
    local msg = raw.data or raw
    if type(msg) ~= "table" then return end
    if clients[id] then clients[id].lastSeen = os.clock() end
    local handler = handlers[msg.type]
    if handler then
        local ok, err = pcall(handler, id, msg)
        if not ok then log("[ERR] handler " .. tostring(msg.type) .. ": " .. tostring(err)) end
    end
end

local function cleanupClients()
    local now = os.clock()
    local removed = {}
    for id, c in pairs(clients) do
        if now - c.lastSeen > 45 then
            table.insert(removed, {id = id, name = c.name})
            clients[id] = nil
        end
    end
    for _, r in ipairs(removed) do
        log("[LEAVE] " .. r.name .. " (" .. r.id .. ") timeout")
        for name, site in pairs(sites) do
            if site.id == r.id then
                sites[name] = nil
                dns["site:" .. name] = nil
                log("[SITE] " .. name .. " offline")
            end
        end
    end
end

local commands = {}

commands.help = function()
    print("")
    print("  list                 online clients")
    print("  names                DNS registry")
    print("  sites                registered sites")
    print("  pkgs                 packages served by this computer")
    print("  broadcast <msg>      send chat broadcast")
    print("  kick <id>            force disconnect")
    print("  ban <id> / unban <id>")
    print("  logs / history       show recent logs/chat")
    print("  clear                clear console")
    print("  quit / q             stop server")
    print("")
end

commands.list = function()
    cleanupClients()
    print("")
    if next(clients) == nil then print("  No clients online.")
    else
        print("  Online clients:")
        for id, c in pairs(clients) do print("    " .. c.name .. " (" .. id .. ")") end
    end
    print("")
end

commands.names = function()
    print("")
    if next(dns) == nil then print("  DNS empty.")
    else
        print("  DNS registry:")
        for name, id in pairs(dns) do print("    " .. name .. " -> " .. id) end
    end
    print("")
end

commands.sites = function()
    print("")
    if next(sites) == nil then print("  No sites registered.")
    else
        print("  Sites:")
        for name, site in pairs(sites) do print("    " .. name .. " -> " .. site.id .. " (" .. site.title .. ")") end
    end
    print("")
end

commands.pkgs = function()
    print("")
    print("  Packages:")
    for _, pkg in ipairs(builtInPackages()) do print("    " .. pkg.name .. " - " .. (pkg.desc or "")) end
    print("")
end

commands.broadcast = function(args)
    local text = table.concat(args, " ")
    if text == "" then print("  Usage: broadcast <message>"); return end
    relayChat("SERVER", text)
end

commands.kick = function(args)
    local id = tonumber(args[1])
    if not id then print("  Usage: kick <computer_id>"); return end
    local name = clients[id] and clients[id].name or tostring(id)
    clients[id] = nil
    sendMsg(id, {type = "kick", reason = "Kicked by admin"})
    log("[KICK] " .. name .. " (" .. id .. ")")
end

commands.ban = function(args)
    local id = tonumber(args[1])
    if not id then print("  Usage: ban <computer_id>"); return end
    banned[id] = true
    local name = clients[id] and clients[id].name or tostring(id)
    clients[id] = nil
    sendMsg(id, {type = "kick", reason = "Banned"})
    log("[BAN] " .. name .. " (" .. id .. ")")
end

commands.unban = function(args)
    local id = tonumber(args[1])
    if not id then print("  Usage: unban <computer_id>"); return end
    banned[id] = nil
    log("[UNBAN] " .. id)
end

commands.logs = function()
    print("")
    local data = readFile(LOG_FILE)
    if not data then print("  No log file yet.")
    else
        local lines = {}
        for line in data:gmatch("[^\n]+") do table.insert(lines, line) end
        for i = math.max(1, #lines - 9), #lines do print("    " .. lines[i]) end
    end
    print("")
end

commands.history = function()
    print("")
    if #chatHistory == 0 then print("  Chat history empty.")
    else for i = math.max(1, #chatHistory - 9), #chatHistory do print("    " .. chatHistory[i]) end end
    print("")
end

commands.clear = function()
    term.clear()
    term.setCursorPos(1, 1)
end

commands.quit = function() running = false end
commands.q = commands.quit

local function processInput(line)
    line = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" then return end
    local parts = {}
    for part in line:gmatch("%S+") do table.insert(parts, part) end
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
log("  CCOS Server v3 started")
log("  Host:  " .. HOST_NAME)
log("  ID:    " .. os.getComputerID())
log("  Modem: " .. side)
log("  Proto: " .. PROTOCOL)
log("========================================")
log("  Type 'help' for commands.")

local function serverLoop()
    while running do
        local id, raw = rednet.receive(PROTOCOL, 2)
        if id then handleMessage(id, raw) end
        cleanupClients()
    end
end

local function consoleLoop()
    while running do
        write("> ")
        processInput(read())
    end
end

parallel.waitForAny(serverLoop, consoleLoop)

log("Server shutting down...")
rednet.unhost(PROTOCOL, SERVICE_NAME)
