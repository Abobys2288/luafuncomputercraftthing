-- CCOS Program: Network Browser
-- Discovers and interacts with CCOS computers on rednet
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appNetBrowse()
    local net = require("ccos.drivers.net")
    if not net.init() then
        local w = D.createWindow("Network Error", 20, 20, 200, 60)
        w.onDraw = function(_,cx,cy) R.drawText(cx+4,cy+4,"No modem found!",K.RED,K.GRAY) end
        w.onKey = function(_,k) if k==keys.escape then D.destroyWindow(w) end end
        return
    end

    local peers = {}
    local sel = 1
    local scroll = 0
    local status = "Press F5 to scan"

    local function scan()
        status = "Scanning..."
        D.markDirty()
        peers = net.discover(3)
        sel = 1
        scroll = 0
        status = "Found " .. #peers .. " peers"
        D.markDirty()
    end

    local wx, wy, ww, wh = D.fitWin(220, 140)
    local w = D.createWindow("Network", wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,40,14,false)
        R.drawText(cx+4,cy+3,"Scan",K.BLACK,K.GRAY)
        R.drawText(cx+50,cy+3,status,K.BLACK,K.GRAY)
        local lh = math.floor((ch-28)/8)
        local list = {}
        for id,name in pairs(peers) do table.insert(list,{id=id,name=name}) end
        table.sort(list,function(a,b) return a.id < b.id end)
        -- Pre-scan hover to avoid dual highlight with keyboard selection
        local hasHit = false
        for i=1,lh do
            local idx=scroll+i; local p=list[idx]
            if not p then break end
            local iy=cy+16+(i-1)*8
            if D.mouse.x>=cx+2 and D.mouse.x<cx+cw-2 and D.mouse.y>=iy and D.mouse.y<iy+8 then
                hasHit = true; break
            end
        end
        for i=1,lh do
            local idx=scroll+i; local p=list[idx]
            if not p then break end
            local iy=cy+16+(i-1)*8
            local hit=D.mouse.x>=cx+2 and D.mouse.x<cx+cw-2 and D.mouse.y>=iy and D.mouse.y<iy+8
            local active = (hasHit and hit) or (not hasHit and idx==sel)
            if active then R.fillRect(cx+2,iy,cw-4,8,K.DBLUE); R.drawText(cx+4,iy,p.name.." ("..p.id..")",K.WHITE,K.DBLUE)
            else R.drawText(cx+4,iy,p.name.." ("..p.id..")",K.BLACK,K.GRAY) end
        end
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 and mx>=0 and mx<40 then scan(); return end
        local lh=math.floor((w.ch-28)/8)
        for i=1,lh do
            local iy=16+(i-1)*8
            if my>=iy and my<iy+8 then sel=scroll+i; D.markContentDirty(w); return end
        end
    end

    w.onKey = function(_,k)
        if k==keys.f5 then scan()
        elseif k==keys.up and sel>1 then sel=sel-1; if sel<=scroll then scroll=scroll-1 end; D.markContentDirty(w)
        elseif k==keys.down then
            local list={}; for id,name in pairs(peers) do table.insert(list,{id=id}) end
            if sel<#list then sel=sel+1; local lh=math.floor((w.ch-28)/8); if sel>scroll+lh then scroll=scroll+1 end; D.markContentDirty(w) end
        elseif k==keys.enter then
            local list={}; for id,name in pairs(peers) do table.insert(list,{id=id,name=name}) end; table.sort(list,function(a,b) return a.id<b.id end)
            local p=list[sel]; if p then
                D.inputDialog("Message to "..p.name,"Enter message:","",function(msg)
                    if msg then net.send(p.id,{type="chat",text=msg,from=net.hostName}); status="Sent!"; D.markDirty() end
                end)
            end
        elseif k==keys.escape then D.destroyWindow(w) end
    end

    -- Auto-listener in background
    local function bgListen()
        while w.visible do
            local ok,id,msg=pcall(net.receive,1)
            if ok and id and msg and type(msg) == "table" and msg.type == "chat" then
                status = msg.from .. ": " .. msg.text
                D.markDirty()
            end
        end
    end
    -- Note: in real use, you'd need parallel.waitForAny. Here we just scan once at start.
    scan()
end

return {name = "Network", icon = "net", run = appNetBrowse}
