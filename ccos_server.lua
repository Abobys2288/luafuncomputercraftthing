--[[
    CCOS Server v2 — Network Backend
    ================================
    No GUI. Console logs, DNS registry, chat relay, admin commands.
    Run standalone on a dedicated computer with a modem.
]]

local PROTOCOL = "CCOS_NET"
local HOST_NAME = os.getComputerLabel() or ("server_" .. os.getComputerID())
local LOG_FILE = "/ccos_server.log"
local MAX_HISTORY = 50

-- ============================================================
-- MODEM INIT
-- ============================================================
local function initModem()
    local sides = {"top","bottom","left","right","front","back"}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            return true
        end
    end
    return false
end

if not initModem() then
    print("[FATAL] No modem found. Attach modem and retry.")
    return
end

rednet.host(PROTOCOL, HOST_NAME)

-- ============================================================
-- DATA
-- ============================================================
local clients = {}      -- id -> {name, lastSeen}
local dns = {}          -- name -> id
local banned = {}       -- id -> true
local chatHistory = {}
local running = true

-- ============================================================
-- LOGGING
-- ============================================================
local function log(msg)
    local time = os.time and os.time() or 0
    local h = math.floor(time)
    local m = math.floor((time - h) * 60)
    local ts = string.format("[%02d:%02d] ", h, m)
    local line = ts .. msg
    print(line)
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(line)
        f.close()
    end
end

-- ============================================================
-- CHAT
-- ============================================================
local function addChat(line)
    table.insert(chatHistory, line)
    if #chatHistory > MAX_HISTORY then
        table.remove(chatHistory, 1)
    end
end

local function relayChat(from, text)
    local line = "[" .. from .. "] " .. text
    addChat(line)
    log("[CHAT] " .. line)
    rednet.broadcast({proto = PROTOCOL, type = "chat", from = from, text = text}, PROTOCOL)
end

-- ============================================================
-- SERVICE HANDLERS
-- ============================================================
local function isBanned(id)
    return banned[id] == true
end

local handlers = {}

handlers.register = function(id, msg)
    local name = msg.name or ("guest_" .. id)
    dns[name] = id
    clients[id] = {name = name, lastSeen = os.clock()}
    rednet.send(id, {proto = PROTOCOL, type = "register_ok", name = name, id = id}, PROTOCOL)
    log("[DNS] " .. name .. " -> " .. id)
end

handlers.resolve = function(id, msg)
    local name = msg.name
    local found = dns[name]
    if found then
        rednet.send(id, {proto = PROTOCOL, type = "resolve_ok", name = name, id = found}, PROTOCOL)
    else
        rednet.send(id, {proto = PROTOCOL, type = "resolve_fail", name = name}, PROTOCOL)
    end
end

handlers.heartbeat = function(id, msg)
    local c = clients[id]
    if c then
        c.lastSeen = os.clock()
    else
        local name = msg.name or ("guest_" .. id)
        clients[id] = {name = name, lastSeen = os.clock()}
        log("[JOIN] " .. name .. " (" .. id .. ")")
    end
end

handlers.chat = function(id, msg)
    if isBanned(id) then return end
    local from = msg.from or (clients[id] and clients[id].name) or tostring(id)
    relayChat(from, msg.text or "")
end

handlers.discover = function(id, msg)
    rednet.send(id, {proto = PROTOCOL, type = "discover_ok", host = HOST_NAME, id = os.getComputerID()}, PROTOCOL)
end

handlers.pkg_list = function(id, msg)
    local list = {}
    if fs.isDir("/ccos/programs") then
        for _, name in ipairs(fs.list("/ccos/programs")) do
            if fs.exists("/ccos/programs/" .. name .. "/program.lua") then
                table.insert(list, name)
            end
        end
    end
    rednet.send(id, {proto = PROTOCOL, type = "pkg_list_resp", packages = list}, PROTOCOL)
end

handlers.pkg_get = function(id, msg)
    local pkg = msg.name
    local path = "/ccos/programs/" .. pkg .. "/program.lua"
    local content = nil
    if fs.exists(path) then
        local f = fs.open(path, "r")
        if f then content = f.readAll(); f.close() end
    end
    rednet.send(id, {proto = PROTOCOL, type = "pkg_get_resp", name = pkg, content = content}, PROTOCOL)
end

local function handleMessage(id, msg)
    if isBanned(id) then return end
    local t = msg.type
    if handlers[t] then
        handlers[t](id, msg)
    end
end

-- ============================================================
-- CLEANUP (offline clients)
-- ============================================================
local function cleanupClients()
    local now = os.clock()
    local timeout = 30
    local removed = {}
    for id, c in pairs(clients) do
        if now - c.lastSeen > timeout then
            table.insert(removed, {id = id, name = c.name})
            clients[id] = nil
        end
    end
    for _, r in ipairs(removed) do
        log("[LEAVE] " .. r.name .. " (" .. r.id .. ") timeout")
    end
end

-- ============================================================
-- CONSOLE COMMANDS
-- ============================================================
local commands = {}

commands.help = function()
    print("")
    print("  list        — online clients")
    print("  names       — DNS registry")
    print("  broadcast <msg>")
    print("  kick <id>   — force disconnect")
    print("  ban <id>    — blacklist")
    print("  unban <id>  — remove blacklist")
    print("  logs        — show last 10 log lines")
    print("  history     — show last 10 chat lines")
    print("  clear       — clear console")
    print("  quit / q    — stop server")
    print("")
end

commands.list = function()
    cleanupClients()
    print("")
    if next(clients) == nil then
        print("  No clients online.")
    else
        print("  Online clients:")
        for id, c in pairs(clients) do
            print("    " .. c.name .. " (" .. id .. ")")
        end
    end
    print("")
end

commands.names = function()
    print("")
    if next(dns) == nil then
        print("  DNS empty.")
    else
        print("  DNS registry:")
        for name, id in pairs(dns) do
            print("    " .. name .. " -> " .. id)
        end
    end
    print("")
end

commands.broadcast = function(args)
    local text = table.concat(args, " ")
    if text == "" then
        print("  Usage: broadcast <message>")
        return
    end
    relayChat("SERVER", text)
    print("  Broadcasted.")
end

commands.kick = function(args)
    local id = tonumber(args[1])
    if not id then
        print("  Usage: kick <computer_id>")
        return
    end
    local c = clients[id]
    local name = c and c.name or tostring(id)
    clients[id] = nil
    rednet.send(id, {proto = PROTOCOL, type = "kick", reason = "Kicked by admin"}, PROTOCOL)
    log("[KICK] " .. name .. " (" .. id .. ")")
    print("  Kicked " .. name .. ".")
end

commands.ban = function(args)
    local id = tonumber(args[1])
    if not id then
        print("  Usage: ban <computer_id>")
        return
    end
    banned[id] = true
    local c = clients[id]
    local name = c and c.name or tostring(id)
    clients[id] = nil
    rednet.send(id, {proto = PROTOCOL, type = "kick", reason = "Banned"}, PROTOCOL)
    log("[BAN] " .. name .. " (" .. id .. ")")
    print("  Banned " .. name .. ".")
end

commands.unban = function(args)
    local id = tonumber(args[1])
    if not id then
        print("  Usage: unban <computer_id>")
        return
    end
    banned[id] = nil
    log("[UNBAN] " .. id)
    print("  Unbanned " .. id .. ".")
end

commands.logs = function()
    print("")
    if not fs.exists(LOG_FILE) then
        print("  No log file yet.")
    else
        local f = fs.open(LOG_FILE, "r")
        if f then
            local lines = {}
            while true do
                local l = f.readLine()
                if not l then break end
                table.insert(lines, l)
            end
            f.close()
            print("  Last log lines:")
            local startIdx = math.max(1, #lines - 9)
            for i = startIdx, #lines do
                print("    " .. lines[i])
            end
        end
    end
    print("")
end

commands.history = function()
    print("")
    if #chatHistory == 0 then
        print("  Chat history empty.")
    else
        print("  Last chat lines:")
        local startIdx = math.max(1, #chatHistory - 9)
        for i = startIdx, #chatHistory do
            print("    " .. chatHistory[i])
        end
    end
    print("")
end

commands.clear = function()
    term.clear()
    term.setCursorPos(1, 1)
end

commands.quit = function()
    running = false
end

-- ============================================================
-- CONSOLE INPUT
-- ============================================================
local function processInput(line)
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" then return end
    local parts = {}
    for part in line:gmatch("%S+") do
        table.insert(parts, part)
    end
    local cmd = parts[1]:lower()
    table.remove(parts, 1)
    if commands[cmd] then
        commands[cmd](parts)
    else
        print("  Unknown command: " .. cmd)
        print("  Type 'help' for commands.")
    end
end

-- ============================================================
-- MAIN LOOP (parallel network + console)
-- ============================================================
log("========================================")
log("  CCOS Server v2 started")
log("  Host:  " .. HOST_NAME)
log("  ID:    " .. os.getComputerID())
log("  Proto: " .. PROTOCOL)
log("========================================")
log("  Type 'help' for commands.")
log("")

local function serverLoop()
    while running do
        local timer = os.startTimer(2)
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local id, msg = p1, p2
            if type(msg) == "table" and msg.proto == PROTOCOL then
                handleMessage(id, msg)
            end
        elseif event == "timer" and p1 == timer then
            cleanupClients()
        end
    end
end

local function consoleLoop()
    while running do
        write("> ")
        local line = read()
        processInput(line)
    end
end

parallel.waitForAny(serverLoop, consoleLoop)

log("Server shutting down...")
rednet.unhost(PROTOCOL, HOST_NAME)
