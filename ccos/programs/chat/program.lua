-- CCOS Program: Chat v2
-- Server-based network chat via desktop background tasks
local D = _G._desktop
local R = _G.ccos_render
local API = _G.ccos_api
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30,RED=11}

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    elseif R.drawTextClipped and w then R.drawTextClipped(x, y, text, fg, bg, w)
    else R.drawText(x, y, tostring(text or ""), fg, bg) end
end

local function popChar(text)
    if API and API.utf8Pop then return API.utf8Pop(text) end
    if R.utf8Pop then return R.utf8Pop(text) end
    return tostring(text or ""):sub(1, -2)
end

    local function appChat()
    local net = require("ccos.drivers.net")
    if not net.init() then
        local w = D.createWindow("Chat Error", 20, 20, 200, 60)
        w.onDraw = function(_,cx,cy) R.drawText(cx+4,cy+4,"No modem found!",K.RED,K.GRAY) end
        w.onKey = function(_,k) if k==keys.escape then D.destroyWindow(w) end end
        return
    end

    local serverId = nil
    local myName = net.hostName
    local messages = {"--- Chat starting ---", "--- Looking for server... ---"}
    local input = ""
    local sy = 0
    local targetId = nil
    local lastHeartbeat = 0
    local ready = false

    -- Async server lookup (never blocks UI)
    net.lookupAsync("server", 4, function(id)
        if not id then
            table.insert(messages, "--- No server found ---")
            table.insert(messages, "--- Enter server ID manually ---")
            D.markDirty()
            D.inputDialog("Server", "Enter server ID:", "", function(entered)
                if entered then
                    serverId = tonumber(entered)
                    if serverId then
                        targetId = serverId
                        ready = true
                        net.register(serverId, myName)
                        table.insert(messages, "--- Connected to " .. serverId .. " ---")
                        D.markDirty()
                    end
                end
            end)
            return
        end
        serverId = id
        targetId = id
        ready = true
        net.register(serverId, myName)
        table.insert(messages, "--- Server: " .. serverId .. " ---")
        D.markDirty()
    end)

    local wx, wy, ww, wh = D.fitWin(260, 160)
    local w = D.createWindow("Chat", wx, wy, ww, wh)

    local function visibleRows()
        return math.max(1, math.floor((w.ch - 21 - 28) / 8))
    end

    local function maxScroll()
        return math.max(0, #messages - visibleRows())
    end

    local function atBottom()
        return sy >= maxScroll()
    end

    local function scrollBottom()
        sy = maxScroll()
    end

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,60,14,false)
        R.drawText(cx+4,cy+3,"Connect",K.BLACK,K.GRAY)
        R.drawButton(cx+66,cy,44,14,false)
        R.drawText(cx+70,cy+3,"Clear",K.BLACK,K.GRAY)
        local ml = math.max(1, math.floor((ch-28)/8))
        for i=1,ml do
            local line = messages[sy+i] or ""
            local color = K.BLACK
            if line:sub(1,3)=="Me:" then color=K.DBLUE end
            if line:sub(1,1)=="-" then color=K.DGRAY end
            drawText(cx+2,cy+16+(i-1)*8,line,color,K.GRAY,cw-10)
        end
        local ms = math.max(0, #messages - ml)
        if ms > 0 and cw >= 12 then
            local listH = ml * 8
            local barH = math.max(8, math.floor(listH * ml / #messages))
            local barY = cy + 16 + math.floor((listH - barH) * sy / ms)
            R.fillRect(cx + cw - 5, barY, 3, barH, K.DGRAY)
        end
        R.fillRect(cx,cy+ch-14,cw,12,K.GRAY)
        local prompt = targetId and ("["..targetId.."]") or "[no target]"
        drawText(cx+2,cy+ch-12,prompt.." "..input.."_",K.BLACK,K.GRAY,cw-4)
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 then
            if mx>=0 and mx<60 then
                D.inputDialog("Connect","Enter computer ID:" ,"",function(id)
                    if id then targetId=tonumber(id); table.insert(messages,"--- Connected to "..id.." ---"); D.markContentDirty(w) end
                end)
            elseif mx>=66 and mx<110 then
                messages={"--- Cleared ---"}; sy=0; D.markContentDirty(w)
            end
        end
    end

    w.onKey = function(_,k,ch)
        if ch then input=input..ch; D.markContentDirty(w)
        elseif k==keys.backspace then input=popChar(input); D.markContentDirty(w)
        elseif k==keys.enter then
            if input~="" and targetId and ready then
                table.insert(messages,"Me: "..input)
                net.send(targetId,{type="chat",text=input,from=myName})
                input=""
                scrollBottom()
                D.markContentDirty(w)
            end
        elseif k==keys.pageUp then sy=math.max(0, sy-visibleRows()); D.markContentDirty(w)
        elseif k==keys.pageDown then sy=math.min(maxScroll(), sy+visibleRows()); D.markContentDirty(w)
        elseif k==keys.up then if sy>0 then sy=sy-1; D.markContentDirty(w) end
        elseif k==keys.down then if sy<maxScroll() then sy=sy+1; D.markContentDirty(w) end
        elseif k==keys.escape then D.destroyWindow(w) end
    end

    w.onScroll = function(_, dir)
        if dir < 0 then sy = math.max(0, sy - 3)
        else sy = math.min(maxScroll(), sy + 3) end
        D.markContentDirty(w)
    end

    -- Background task: heartbeat + receive broadcast
    local bgTask = function(e, a, b, c, d)
        if e == "timer" then
            -- heartbeat every 10 seconds
            if serverId and (os.clock() - lastHeartbeat) > 10 then
                net.heartbeat(serverId)
                lastHeartbeat = os.clock()
            end
        elseif e == "rednet_message" then
            local id, raw = a, b
            if type(raw) == "table" and raw.proto == net.protocol then
                local msg = raw.data or raw
                if msg.type == "chat" then
                    local shouldFollow = atBottom()
                    table.insert(messages, msg.from .. ": " .. msg.text)
                    if shouldFollow then scrollBottom() end
                    D.markContentDirty(w)
                elseif msg.type == "kick" then
                    D.showError("Kicked", msg.reason or "You have been kicked")
                    D.destroyWindow(w)
                end
            end
        end
    end

    if not D.bgTasks then D.bgTasks = {} end
    table.insert(D.bgTasks, bgTask)

    w.onClose = function()
        for i, t in ipairs(D.bgTasks or {}) do
            if t == bgTask then
                table.remove(D.bgTasks, i)
                break
            end
        end
    end
end

return {name = "Chat", icon = "chat", run = appChat}
