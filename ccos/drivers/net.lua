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

-- Register name on DNS server
function net.register(serverId, name)
    if not net.online then return false end
    return net.send(serverId, {type = "register", name = name or net.hostName})
end

-- Resolve name via DNS server
function net.resolve(serverId, name)
    if not net.online then return nil end
    net.send(serverId, {type = "resolve", name = name})
    local id, msg = net.receive(2)
    if id and msg and type(msg) == "table" and msg.type == "resolve_ok" then
        return msg.id
    end
    return nil
end

-- Heartbeat to server (keep-alive)
function net.heartbeat(serverId)
    if not net.online then return false end
    return net.send(serverId, {type = "heartbeat", name = net.hostName})
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

-- Discover computers running CCOS (uses new server discover protocol)
function net.discover(timeout)
    if not net.online then return {} end
    net.broadcast({type = "discover", host = net.hostName})
    local found = {}
    local timer = os.startTimer(timeout or 0.5)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local id, msg = p1, p2
            if type(msg) == "table" and msg.proto == net.protocol then
                local data = msg.data or msg
                if type(data) == "table" and data.type == "discover_ok" then
                    found[id] = data.host or ("PC_" .. id)
                end
            end
        elseif event == "timer" and p1 == timer then
            break
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

function net.requestPackageList(serverId)
    if not net.online then return nil end
    net.send(serverId, {type = "pkg_list"})
    local id, msg = net.receive(3)
    if id and msg and msg.type == "pkg_list_resp" then return msg.packages or {} end
    return nil
end

function net.requestPackage(serverId, name)
    if not net.online then return nil end
    net.send(serverId, {type = "pkg_get", name = name})
    local id, msg = net.receive(5)
    if id and msg and msg.type == "pkg_get_resp" then return msg end
    return nil
end

function net.siteRegister(serverId, name, title)
    if not net.online then return false end
    return net.send(serverId, {type = "site_register", name = name, title = title or name, host = net.hostName})
end

function net.siteList(serverId)
    if not net.online then return {} end
    net.send(serverId, {type = "site_list"})
    local id, msg = net.receive(3)
    if id and msg and msg.type == "site_list_resp" then return msg.sites or {} end
    return {}
end

function net.siteResolve(serverId, name)
    if not net.online then return nil end
    net.send(serverId, {type = "site_resolve", name = name})
    local id, msg = net.receive(3)
    if id and msg and msg.type == "site_resolve_ok" then return msg.id, msg.site end
    return nil
end

function net.siteGet(hostId, name, path)
    if not net.online then return nil end
    net.send(hostId, {type = "site_get", name = name, path = path or "index.txt"})
    local id, msg = net.receive(5)
    if id and msg and msg.type == "site_content" then return msg.content, msg.title end
    return nil
end

-- Background listener for chat + kick (non-blocking)
-- callback: function(type, data) ... end
function net.listenLoop(callback)
    if not net.online then return end
    while true do
        local id, msg = net.receive(999999)
        if id and msg and type(msg) == "table" then
            if callback then
                callback(msg.type, msg)
            end
        end
    end
end

return net
