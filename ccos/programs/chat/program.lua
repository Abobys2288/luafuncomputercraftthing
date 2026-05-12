-- CCOS Program: Chat
-- Server-based network chat with heartbeat and background listener
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30,RED=11}

local function appChat()
    local net = require("ccos.drivers.net")
    if not net.init() then
        local w = D.createWindow("Chat Error", 20, 20, 200, 60)
        w.onDraw = function(_,cx,cy) R.drawText(cx+4,cy+4,"No modem found!",K.RED,K.GRAY) end
        w.onKey = function(_,k) if k==keys.escape then D.destroyWindow(w) end end
        return
    end

    -- 1. On startup: register name on server
    local serverId = net.lookup("server")
    local myName = net.hostName

    if not serverId then
        local done = false
        D.inputDialog("Server", "Enter server computer ID:", "", function(id)
            if id then serverId = tonumber(id) end
            done = true
        end)
        while not done do
            local e, a, b, c, d = os.pullEvent()
            if e == "timer" then
                D.drawAll()
            elseif e == "mouse_click" then
                D.mouse.x = b; D.mouse.y = c
                D.click(b, c, a)
            elseif e == "mouse_drag" then
                D.mouse.x = b; D.mouse.y = c
                D.drag(b, c)
            elseif e == "mouse_up" then
                D.drop()
            elseif e == "key" then
                if D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey, D.activeWin, a, nil) end
            elseif e == "char" then
                if D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey, D.activeWin, nil, a) end
            end
        end
    end

    if not serverId then
        D.showError("Chat Error", "No server ID provided.")
        return
    end

    net.register(serverId, myName)

    local messages = {"--- Chat started ---", "--- Server: " .. serverId .. " ---"}
    local input = ""
    local sy = 0
    local targetId = serverId

    local wx, wy, ww, wh = D.fitWin(260, 160)
    local w = D.createWindow("Chat", wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,60,14,false)
        R.drawText(cx+4,cy+3,"Connect",K.BLACK,K.GRAY)
        R.drawButton(cx+66,cy,44,14,false)
        R.drawText(cx+70,cy+3,"Clear",K.BLACK,K.GRAY)
        local ml = math.floor((ch-28)/8)
        for i=1,ml do
            local line = messages[sy+i] or ""
            local color = K.BLACK
            if line:sub(1,3)=="Me:" then color=K.DBLUE end
            if line:sub(1,1)=="-" then color=K.DGRAY end
            R.drawText(cx+2,cy+16+(i-1)*8,line,color,K.GRAY)
        end
        R.fillRect(cx,cy+ch-14,cw,12,K.GRAY)
        local prompt = targetId and ("["..targetId.."] ") or "[no target] "
        R.drawText(cx+2,cy+ch-12,prompt..input.."_",K.BLACK,K.GRAY)
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 then
            if mx>=0 and mx<60 then
                D.inputDialog("Connect","Enter computer ID:","",function(id)
                    if id then targetId=tonumber(id); table.insert(messages,"--- Connected to "..id.." ---"); D.markContentDirty(w) end
                end)
            elseif mx>=66 and mx<110 then
                messages={"--- Cleared ---"}; sy=0; D.markContentDirty(w)
            end
        end
    end

    w.onKey = function(_,k,ch)
        if ch then input=input..ch; D.markContentDirty(w)
        elseif k==keys.backspace then input=input:sub(1,-2); D.markContentDirty(w)
        elseif k==keys.enter then
            if input~="" and targetId then
                table.insert(messages,"Me: "..input)
                net.send(targetId,{type="chat",text=input,from=myName})
                input=""
                local ml=math.floor((w.ch-28)/8); if #messages>ml then sy=#messages-ml end
                D.markContentDirty(w)
            end
        elseif k==keys.up then if sy>0 then sy=sy-1; D.markContentDirty(w) end
        elseif k==keys.down then local ml=math.floor((w.ch-28)/8); if sy<#messages-ml then sy=sy+1; D.markContentDirty(w) end
        elseif k==keys.escape then D.destroyWindow(w) end
    end

    -- Background threads via parallel.waitForAny
    local function uiPoll()
        local uiTimer = os.startTimer(1)
        while true do
            local found = false
            for _, win in ipairs(D.windows) do
                if win.id == w.id then found = true; break end
            end
            if not found then return end

            local e, a, b, c, d = os.pullEvent()
            if e == "timer" then
                if a == uiTimer then
                    uiTimer = os.startTimer(1)
                end
                D.drawAll()
            elseif e == "mouse_click" then
                D.mouse.x = b; D.mouse.y = c
                D.click(b, c, a)
                D.drawAll()
            elseif e == "mouse_drag" then
                D.mouse.x = b; D.mouse.y = c
                D.drag(b, c)
                D.drawAll()
            elseif e == "mouse_up" then
                D.drop()
                D.drawAll()
            elseif e == "key" then
                if D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey, D.activeWin, a, nil) end
                D.drawAll()
            elseif e == "char" then
                if D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey, D.activeWin, nil, a) end
                D.drawAll()
            end
        end
    end

    local function netLoop()
        while true do
            local id, msg = net.receive(60)
            if id and msg and type(msg) == "table" then
                if msg.type == "chat" then
                    table.insert(messages, msg.from .. ": " .. msg.text)
                    local ml = math.floor((w.ch - 28) / 8)
                    if #messages > ml then sy = #messages - ml end
                    D.markContentDirty(w)
                elseif msg.type == "kick" then
                    D.showError("Kicked", msg.reason or "You have been kicked from the server")
                    D.destroyWindow(w)
                    return
                end
            end
        end
    end

    local function heartbeatLoop()
        local nextTimer = os.startTimer(10)
        while true do
            local e, tId = os.pullEvent("timer")
            if e == "timer" and tId == nextTimer then
                if serverId then net.heartbeat(serverId) end
                nextTimer = os.startTimer(10)
            end
            local found = false
            for _, win in ipairs(D.windows) do
                if win.id == w.id then found = true; break end
            end
            if not found then return end
        end
    end

    parallel.waitForAny(uiPoll, netLoop, heartbeatLoop)
end

return {name = "Chat", icon = "chat", run = appChat}
