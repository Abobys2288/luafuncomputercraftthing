-- CCOS Program: Network Browser v3
-- Discovers peers + DNS lookup via CCOS server (async, never blocks UI)
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30,RED=11}

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, tostring(text or ""), fg, bg) end
end

local function appNetBrowse()
    local net = require("ccos.drivers.net")
    if not net.init() then
        if API and API.showError then API.showError("Network Error", "No modem found!")
        else
            local w = D.createWindow("Network Error", 20, 20, 200, 60)
            w.onDraw = function(_,cx,cy) R.drawText(cx+4,cy+4,"No modem found!",K.RED,K.GRAY) end
            w.onKey = function(_,k) if k==keys.escape then D.destroyWindow(w) end end
        end
        return
    end

    local serverId = nil
    local peers = {}
    local sel = 1
    local scroll = 0
    local status = "Starting..."
    local busy = false

    -- Async server lookup (never blocks UI)
    net.lookupAsync("server", 3, function(id)
        serverId = id
        if id then status = "Ready" else status = "No server" end
        D.markDirty()
        if id then scan() end
    end)

    local function buildList()
        local list = {}
        for id, name in pairs(peers) do table.insert(list, {id = id, name = name}) end
        table.sort(list, function(a, b) return a.id < b.id end)
        return list
    end

    local function scan()
        if busy then return end
        busy = true
        status = "Scanning..."
        D.markDirty()
        net.discoverAsync(0.6, function(found)
            peers = found or {}
            sel = 1; scroll = 0
            status = "Found " .. #buildList() .. " peers"
            busy = false
            D.markDirty()
        end)
    end

    local function dnsLookup(name)
        if busy then return end
        if not serverId then status = "No server"; D.markDirty(); return end
        busy = true
        status = "Lookup..."
        D.markDirty()
        net.resolveAsync(serverId, name, function(id)
            if id then
                peers[id] = name
                status = "Found " .. name .. " -> " .. id
            else
                status = "Not found: " .. name
            end
            busy = false
            D.markDirty()
        end)
    end

    local wx, wy, ww, wh = D.fitWin(240, 160)
    local w = D.createWindow("Network", wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,40,14,false)
        R.drawText(cx+4,cy+3,"Scan",K.BLACK,K.GRAY)
        R.drawButton(cx+44,cy,52,14,false)
        R.drawText(cx+48,cy+3,"Lookup",K.BLACK,K.GRAY)
        local stColor = busy and K.DBLUE or K.BLACK
        drawText(cx+100,cy+3,status,stColor,K.GRAY,math.max(0,cw-100))
        local lh = math.floor((ch-28)/8)
        local list = buildList()
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
        if my>=0 and my<14 then
            if mx>=0 and mx<40 then scan(); return
            elseif mx>=44 and mx<96 then
                D.inputDialog("DNS Lookup", "Computer name:", "", function(name)
                    if name then dnsLookup(name) end
                end)
                return
            end
        end
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
            local list=buildList()
            if sel<#list then sel=sel+1; local lh=math.floor((w.ch-28)/8); if sel>scroll+lh then scroll=scroll+1 end; D.markContentDirty(w) end
        elseif k==keys.enter then
            local list=buildList()
            local p=list[sel]; if p then
                D.inputDialog("Message to "..p.name,"Enter message:" ,"",function(msg)
                    if msg then net.send(p.id,{type="chat",text=msg,from=net.hostName}); status="Sent!"; D.markDirty() end
                end)
            end
        elseif k==keys.escape then D.destroyWindow(w) end
    end

    w.onScroll = function(_, dir)
        local list = buildList()
        local lh = math.max(1, math.floor((w.ch - 28) / 8))
        local maxScroll = math.max(0, #list - lh)
        if dir < 0 then scroll = math.max(0, scroll - 3)
        else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#list, math.max(sel, scroll + 1)))
        D.markContentDirty(w)
    end

    scan()
end

return {name = "Network", icon = "net", run = appNetBrowse}
