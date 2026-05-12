-- CCOS Server — Text-mode network services
-- Standalone server, no graphics required.

local PROTOCOL = "CCOS_NET"
local HOST = os.getComputerLabel() or ("SERVER_" .. os.getComputerID())

-- Open any attached modem
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
    print("ERROR: No modem found. Server cannot start.")
    return
end

rednet.host(PROTOCOL, "CCOS_SERVER")

print("========================================")
print("  CCOS Server started")
print("  Host: " .. HOST)
print("  ID:   " .. os.getComputerID())
print("  Protocol: " .. PROTOCOL)
print("========================================")
print("Press Q to quit")
print("")

local running = true
local clients = {}
local recentChat = {}

local function handleMessage(id, msg)
    if msg.type == "ping" then
        rednet.send(id, {proto = PROTOCOL, type = "pong", host = HOST}, PROTOCOL)
    elseif msg.type == "chat" then
        local line = "[" .. (msg.from or id) .. "] " .. (msg.text or "")
        table.insert(recentChat, line)
        if #recentChat > 24 then table.remove(recentChat, 1) end
        -- Relay to all
        rednet.broadcast({proto = PROTOCOL, type = "chat", from = msg.from, text = msg.text}, PROTOCOL)
        print(line)
    elseif msg.type == "pkg_list" then
        local list = {}
        if fs.isDir("/ccos/programs") then
            for _, name in ipairs(fs.list("/ccos/programs")) do
                if fs.exists("/ccos/programs/" .. name .. "/program.lua") then
                    table.insert(list, name)
                end
            end
        end
        rednet.send(id, {proto = PROTOCOL, type = "pkg_list_resp", packages = list}, PROTOCOL)
    elseif msg.type == "pkg_get" then
        local pkg = msg.name
        local path = "/ccos/programs/" .. pkg .. "/program.lua"
        local content = nil
        if fs.exists(path) then
            local f = fs.open(path, "r")
            if f then content = f.readAll(); f.close() end
        end
        rednet.send(id, {proto = PROTOCOL, type = "pkg_get_resp", name = pkg, content = content}, PROTOCOL)
    end
end

while running do
    local timer = os.startTimer(0.5)
    local event, p1, p2, p3 = os.pullEvent()
    if event == "rednet_message" then
        local id, msg = p1, p2
        if type(msg) == "table" and msg.proto == PROTOCOL then
            handleMessage(id, msg)
        end
    elseif event == "key" and p1 == keys.q then
        running = false
    elseif event == "timer" and p1 == timer then
        -- loop
    end
end

print("Server shutting down...")
rednet.unhost(PROTOCOL, "CCOS_SERVER")
