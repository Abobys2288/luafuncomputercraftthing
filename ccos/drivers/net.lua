--[[
    CCOS Network Driver — Rednet Standard API
    ==========================================
    Uses CC:Tweaked built-in rednet (no low-level modem hacking).
]]

local net = {}

net.protocol = "CCOS_NET"
net.hostName = os.getComputerLabel() or ("PC_" .. os.getComputerID())
net.online = false

-- Open any available modem
function net.init()
    local sides = {"top","bottom","left","right","front","back"}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            net.online = true
            return true
        end
    end
    return false
end

function net.isReady()
    return net.online
end

-- Broadcast to all computers
function net.broadcast(msg)
    if not net.online then return false end
    rednet.broadcast({proto = net.protocol, data = msg}, net.protocol)
    return true
end

-- Send to specific computer
function net.send(targetId, msg)
    if not net.online then return false end
    return rednet.send(targetId, {proto = net.protocol, data = msg}, net.protocol)
end

-- Receive message (blocks until timeout)
function net.receive(timeout)
    if not net.online then return nil end
    local id, msg = rednet.receive(net.protocol, timeout or 5)
    if id and msg and type(msg) == "table" and msg.proto == net.protocol then
        return id, msg.data
    end
    return nil
end

-- Discover computers running CCOS
function net.discover(timeout)
    if not net.online then return {} end
    net.broadcast({type = "ping", host = net.hostName})
    local found = {}
    local start = os.clock()
    while os.clock() - start < (timeout or 3) do
        local id, msg = net.receive(0.5)
        if id and msg and type(msg) == "table" and msg.type == "pong" then
            found[id] = msg.host or ("PC_" .. id)
        end
    end
    return found
end

-- Host a service (other computers can lookup)
function net.host(serviceName)
    if not net.online then return false end
    rednet.host(net.protocol, serviceName)
    return true
end

-- Lookup a service
function net.lookup(serviceName)
    if not net.online then return nil end
    return rednet.lookup(net.protocol, serviceName)
end

-- Auto-responder (run in parallel with parallel.waitForAny)
function net.listenLoop()
    if not net.online then return end
    while true do
        local id, msg = net.receive(999999)
        if id and msg and type(msg) == "table" then
            if msg.type == "ping" then
                net.send(id, {type = "pong", host = net.hostName})
            end
        end
    end
end

return net
