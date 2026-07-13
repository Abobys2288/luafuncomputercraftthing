--[[
    CCOS Network Driver — Rednet Standard API
    ==========================================
    Uses CC:Tweaked built-in rednet.

    Key design: net.receive re-queues non-network events (mouse, key, timer)
    via os.queueEvent so the desktop main loop never loses input while a
    network call is in progress. Long operations also have async variants
    (net.request) that run via desktop background tasks and never block UI.
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

-- Send to specific computer (non-blocking)
function net.send(targetId, msg)
    if not net.online then return false end
    return rednet.send(targetId, {proto = net.protocol, data = msg}, net.protocol)
end

-- ============================================================
-- Receive — event-preserving
-- ============================================================
-- Receives a CCOS protocol message. While waiting, non-rednet events
-- (mouse_click, key, char, timer, ...) are re-queued via os.queueEvent so
-- the desktop main loop can still process them afterwards. This is what
-- stops network calls from "eating" user input and freezing the UI.
function net.receive(timeout)
    if not net.online then return nil end
    timeout = timeout or 5
    local timer = os.startTimer(timeout)
    local queue = os.queueEvent
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEventRaw()
        if event == "rednet_message" then
            local id, msg = p1, p2
            if type(msg) == "table" and msg.proto == net.protocol then
                if p3 == timer then p3 = nil end
                os.cancelTimer(timer)
                return id, msg.data
            else
                -- rednet message from another protocol — re-queue it
                queue(event, p1, p2, p3, p4, p5)
            end
        elseif event == "timer" and p1 == timer then
            return nil
        else
            -- Any other event: re-queue so the desktop gets it back.
            queue(event, p1, p2, p3, p4, p5)
        end
    end
end

-- ============================================================
-- Discover — event-preserving
-- ============================================================
function net.discover(timeout)
    if not net.online then return {} end
    net.broadcast({type = "discover", host = net.hostName})
    local found = {}
    local timer = os.startTimer(timeout or 0.5)
    local queue = os.queueEvent
    while true do
        local event, p1, p2, p3 = os.pullEventRaw()
        if event == "rednet_message" then
            local id, msg = p1, p2
            if type(msg) == "table" and msg.proto == net.protocol then
                local data = msg.data or msg
                if type(data) == "table" and data.type == "discover_ok" then
                    found[id] = data.host or ("PC_" .. id)
                end
            else
                queue(event, p1, p2, p3)
            end
        elseif event == "timer" and p1 == timer then
            break
        else
            queue(event, p1, p2, p3)
        end
    end
    return found
end

-- ============================================================
-- Async request — never blocks the UI
-- ============================================================
-- Sends requestMsg to targetId and registers a one-shot background task
-- that fires callback(responseMsg, senderId) when a reply with the given
-- expectedType arrives (or nil on timeout). The task removes itself.
-- The desktop must run bgTasks on rednet_message events (it does).
function net.request(targetId, requestMsg, expectedType, timeout, callback)
    if not net.online then
        if callback then callback(nil, nil) end
        return false
    end
    timeout = timeout or 5
    net.send(targetId, requestMsg)
    local desktop = _G._desktop or _G.desktop
    if not desktop or not desktop.bgTasks then
        if callback then callback(nil, nil) end
        return false
    end
    local myTimer = os.startTimer(timeout)
    local done = false
    local bgTask = function(e, a, b)
        if done then return end
        if e == "rednet_message" then
            local id, raw = a, b
            if type(raw) == "table" and raw.proto == net.protocol then
                local msg = raw.data or raw
                if type(msg) == "table" and msg.type == expectedType then
                    done = true
                    pcall(os.cancelTimer, myTimer)
                    for i, t in ipairs(desktop.bgTasks or {}) do
                        if t == bgTask then table.remove(desktop.bgTasks, i); break end
                    end
                    if callback then callback(msg, id) end
                end
            end
        elseif e == "timer" and a == myTimer then
            done = true
            for i, t in ipairs(desktop.bgTasks or {}) do
                if t == bgTask then table.remove(desktop.bgTasks, i); break end
            end
            if callback then callback(nil, nil) end
        end
    end
    table.insert(desktop.bgTasks, bgTask)
    return true
end

-- Convenience async wrappers (each calls net.request with the right shape).
function net.resolveAsync(serverId, name, callback)
    return net.request(serverId, {type = "resolve", name = name}, "resolve_ok", 2, function(msg, id)
        callback(msg and msg.id or nil)
    end)
end

function net.discoverAsync(timeout, callback)
    if not net.online then if callback then callback({}) end; return false end
    net.broadcast({type = "discover", host = net.hostName})
    local desktop = _G._desktop or _G.desktop
    if not desktop or not desktop.bgTasks then if callback then callback({}) end; return false end
    local found = {}
    local timer = os.startTimer(timeout or 0.5)
    local done = false
    local bgTask = function(e, a, b)
        if done then return end
        if e == "rednet_message" then
            local id, raw = a, b
            if type(raw) == "table" and raw.proto == net.protocol then
                local data = raw.data or raw
                if type(data) == "table" and data.type == "discover_ok" then
                    found[id] = data.host or ("PC_" .. id)
                end
            end
        elseif e == "timer" and a == timer then
            done = true
            for i, t in ipairs(desktop.bgTasks or {}) do
                if t == bgTask then table.remove(desktop.bgTasks, i); break end
            end
            if callback then callback(found) end
        end
    end
    table.insert(desktop.bgTasks, bgTask)
    return true
end

function net.requestPackageListAsync(serverId, callback)
    return net.request(serverId, {type = "pkg_list"}, "pkg_list_resp", 3, function(msg)
        callback(msg and msg.packages or {})
    end)
end

function net.requestPackageAsync(serverId, name, callback)
    return net.request(serverId, {type = "pkg_get", name = name}, "pkg_get_resp", 5, function(msg)
        callback(msg or nil)
    end)
end

function net.siteListAsync(serverId, callback)
    return net.request(serverId, {type = "site_list"}, "site_list_resp", 3, function(msg)
        callback(msg and msg.sites or {})
    end)
end

function net.siteResolveAsync(serverId, name, callback)
    return net.request(serverId, {type = "site_resolve", name = name}, "site_resolve_ok", 3, function(msg)
        callback(msg and msg.id or nil, msg and msg.site or nil)
    end)
end

function net.siteGetAsync(hostId, name, path, callback)
    return net.request(hostId, {type = "site_get", name = name, path = path or "index.txt"}, "site_content", 5, function(msg)
        callback(msg and msg.content or nil, msg and msg.title or nil)
    end)
end

-- ============================================================
-- Sync wrappers (event-preserving, kept for compatibility)
-- ============================================================
function net.resolve(serverId, name)
    if not net.online then return nil end
    net.send(serverId, {type = "resolve", name = name})
    local id, msg = net.receive(2)
    if id and msg and type(msg) == "table" and msg.type == "resolve_ok" then return msg.id end
    return nil
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

-- Host / lookup
function net.host(serviceName)
    if not net.online then return false end
    rednet.host(net.protocol, serviceName)
    return true
end

net._lookupCache = {}
net._lookupCacheAt = {}

-- Synchronous lookup with SHORT timeout (0.3s) and cache.
-- Avoids the multi-second hang of bare rednet.lookup.
function net.lookup(serviceName)
    if not net.online then return nil end
    local now = os.clock()
    local cached = net._lookupCache[serviceName]
    local cachedAt = net._lookupCacheAt[serviceName] or 0
    if cached and now - cachedAt < 30 then return cached end
    -- Use short timeout; some CC:T versions support 3rd arg
    local id = nil
    pcall(function()
        if rednet.lookup then
            local ok, r = pcall(rednet.lookup, net.protocol, serviceName, 0.3)
            id = ok and r or nil
            if id == nil then
                ok, r = pcall(rednet.lookup, net.protocol, serviceName)
                id = ok and r or nil
            end
        end
    end)
    net._lookupCache[serviceName] = id
    net._lookupCacheAt[serviceName] = now
    return id
end

function net.lookupSiteServer()
    if not net.online then return nil end
    return net.lookup("siteserver") or net.lookup("server")
end

-- Async lookup — never blocks. Fires callback(id) when found or nil on timeout.
function net.lookupAsync(serviceName, timeout, callback)
    if not net.online then if callback then callback(nil) end; return false end
    timeout = timeout or 2
    -- Try cache first (instant)
    local now = os.clock()
    local cached = net._lookupCache[serviceName]
    local cachedAt = net._lookupCacheAt[serviceName] or 0
    if cached and now - cachedAt < 30 then
        if callback then callback(cached) end
        return true
    end
    -- Broadcast a lookup request and listen via bgTask
    local desktop = _G._desktop or _G.desktop
    if not desktop or not desktop.bgTasks then
        if callback then callback(nil) end
        return false
    end
    local myTimer = os.startTimer(timeout)
    local done = false
    -- rednet.host messages come as rednet_host events
    local bgTask = function(e, a, b)
        if done then return end
        if e == "rednet_host" then
            -- a = protocol, b = hostname (CC:T rednet.host discovery)
            -- Some versions fire this; cache and resolve.
            if a == net.protocol and b == serviceName then
                -- we don't get the id from this event reliably; fall through
            end
        elseif e == "timer" and a == myTimer then
            done = true
            for i, t in ipairs(desktop.bgTasks or {}) do
                if t == bgTask then table.remove(desktop.bgTasks, i); break end
            end
            -- Final synchronous attempt with very short timeout
            local id = nil
            pcall(function()
                local ok, r = pcall(rednet.lookup, net.protocol, serviceName, 0.1)
                id = ok and r or nil
            end)
            net._lookupCache[serviceName] = id
            net._lookupCacheAt[serviceName] = os.clock()
            if callback then callback(id) end
        end
    end
    table.insert(desktop.bgTasks, bgTask)
    return true
end

function net.lookupSiteServerAsync(timeout, callback)
    if not net.online then if callback then callback(nil) end; return false end
    net.lookupAsync("siteserver", timeout, function(id)
        if id then callback(id) else net.lookupAsync("server", timeout, callback) end
    end)
    return true
end

-- Background listener for chat + kick (cooperative, interruptible)
function net.listenLoop(callback)
    if not net.online then return end
    local kernel = _G.ccos_kernel
    while true do
        if kernel and kernel.interrupted() then break end
        local id, msg = net.receive(1)
        if id and msg and type(msg) == "table" then
            if callback then callback(msg.type, msg) end
        end
        if not id then os.sleep(0) end
    end
end

return net
