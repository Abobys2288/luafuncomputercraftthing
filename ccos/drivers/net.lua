--[[
    CCOS Network Driver
    ===================
    Simple rednet/modem wrapper for CCOS networking.
    Uses modem peripherals (wired/wireless).
]]

local net = {}

net.modem = nil
net.protocol = "CCOS_NET"
net.channel = 65535 -- broadcast channel

function net.init()
    local sides = {"top","bottom","left","right","front","back"}
    for _, side in ipairs(sides) do
        local ok, ptype = pcall(peripheral.getType, side)
        if ok and ptype == "modem" then
            local ok2, modem = pcall(peripheral.wrap, side)
            if ok2 and modem then
                net.modem = modem
                local ok3 = pcall(function() modem.open(os.getComputerID()) end)
                if ok3 then return true end
            end
        end
    end
    return false
end

function net.isReady()
    return net.modem ~= nil
end

function net.send(targetId, message)
    if not net.modem then return false end
    local ok = pcall(function()
        net.modem.transmit(targetId, os.getComputerID(), {
            protocol = net.protocol,
            from = os.getComputerID(),
            data = message
        })
    end)
    return ok
end

function net.broadcast(message)
    return net.send(net.channel, message)
end

function net.receive(timeout)
    if not net.modem then return nil end
    local timer = os.startTimer(timeout or 5)
    while true do
        local event = {os.pullEvent()}
        if event[1] == "modem_message" then
            local msg = event[5]
            if type(msg) == "table" and msg.protocol == net.protocol then
                return msg.from, msg.data
            end
        elseif event[1] == "timer" and event[2] == timer then
            return nil
        end
    end
end

function net.discover(timeout)
    if not net.modem then return {} end
    net.broadcast({type = "ping"})
    local found = {}
    local start = os.clock()
    while os.clock() - start < (timeout or 3) do
        local event = {os.pullEvent()}
        if event[1] == "modem_message" then
            local msg = event[5]
            if type(msg) == "table" and msg.protocol == net.protocol then
                if msg.data and msg.data.type == "pong" then
                    found[msg.from] = true
                end
            end
        end
    end
    local result = {}
    for id in pairs(found) do table.insert(result, id) end
    return result
end

-- Auto-respond to pings (call this in a parallel thread)
function net.listen()
    if not net.modem then return end
    while true do
        local event = {os.pullEvent("modem_message")}
        local msg = event[5]
        if type(msg) == "table" and msg.protocol == net.protocol then
            if msg.data and msg.data.type == "ping" then
                net.send(msg.from, {type = "pong"})
            end
        end
    end
end

return net
