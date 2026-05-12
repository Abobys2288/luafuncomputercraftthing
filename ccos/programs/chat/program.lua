-- CCOS Program: Chat
-- Simple network chat between CCOS computers
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appChat()
    local net = require("ccos.drivers.net")
    if not net.init() then
        local w = D.createWindow("Chat Error", 20, 20, 200, 60)
        w.onDraw = function(_,cx,cy) R.drawText(cx+4,cy+4,"No modem found!",K.RED,K.GRAY) end
        w.onKey = function(_,k) if k==keys.escape then D.destroyWindow(w) end end
        return
    end

    local messages = {"--- Chat started ---"}
    local input = ""
    local sy = 0
    local targetId = nil

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
                net.send(targetId,{type="chat",text=input,from=net.hostName})
                input=""
                local ml=math.floor((w.ch-28)/8); if #messages>ml then sy=#messages-ml end
                D.markContentDirty(w)
            end
        elseif k==keys.up then if sy>0 then sy=sy-1; D.markContentDirty(w) end
        elseif k==keys.down then local ml=math.floor((w.ch-28)/8); if sy<#messages-ml then sy=sy+1; D.markContentDirty(w) end
        elseif k==keys.escape then D.destroyWindow(w) end
    end

    -- Background receive
    local oldOnKey = w.onKey
    w.onKey = function(win,k,ch)
        if k==keys.escape then D.destroyWindow(win) return end
        return oldOnKey(win,k,ch)
    end
end

return {name = "Chat", icon = "chat", run = appChat}
