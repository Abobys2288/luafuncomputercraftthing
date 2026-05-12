--[[
    CCOS Desktop v17 — CLEAN REWRITE
    =================================
    Modular, no syntax errors guaranteed.
]]

local R = _G.ccos_render
local D = {}; _G._desktop = D

local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,RED=11,DESKTOP=30}

D.windows = {}
D.activeWin = nil
D.taskbarH = 20
D.startMenuOpen = false
D.startMenuScroll = 0
D.clock = ""
D.nextWinId = 1
D.dragWin = nil
D.dragOX = 0
D.dragOY = 0
D.resizeWin = nil
D.resizeOX = 0
D.resizeOY = 0
D.mouse = {x=0,y=0}
D.dirty = true
D._contentWin = nil
D._clockDirty = false
D.programs = {}

D.iconCache = {}
D.lastIconCacheW = 0
D.lastIconCacheH = 0

D.rebuildIconCache = function()
    D.iconCache = {}
    local by = R.h - D.taskbarH
    local iw, ih = 48, 42
    local cols = math.max(1, math.floor((R.w - 10) / (iw + 10)))
    local rowHeight = ih + 8
    for i, prog in ipairs(D.programs) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols) - D.iconScrollY
        local ix, iy = 8 + col * (iw + 10), 8 + row * rowHeight
        if iy > by then break end -- fully below screen, stop
        if iy + ih >= 0 then
            local lab = prog.name
            if #lab > 8 then lab = lab:sub(1, 7) .. ".." end
            table.insert(D.iconCache, {
                prog = prog,
                ix = ix, iy = iy,
                iw = iw, ih = ih,
                lab = lab,
                hover = false
            })
        end
    end
    D.lastIconCacheW = R.w
    D.lastIconCacheH = R.h
end

-- ============================================================
-- CONFIG PERSISTENCE
-- ============================================================
D.configPath = "/ccos/config/desktop.cfg"

function D.loadConfig()
    if not fs.exists(D.configPath) then return end
    local f = fs.open(D.configPath, "r")
    if not f then return end
    local content = f.readAll()
    f.close()
    local ok, cfg = pcall(textutils.unserialize, content)
    if ok and cfg then
        if cfg.windows then
            for _, cw in ipairs(cfg.windows) do
                for _, prog in ipairs(D.programs) do
                    if prog.name == cw.title then
                        local wx, wy, ww, wh = D.fitWin(cw.cw or 200, cw.ch or 120)
                        if cw.cx then wx = cw.cx end
                        if cw.cy then wy = cw.cy end
                        if cw.cw then ww = cw.cw end
                        if cw.ch then wh = cw.ch end
                        D.createWindow(cw.title, wx, wy, ww, wh)
                        break
                    end
                end
            end
        end
    end
end

function D.saveConfig()
    local cfg = {windows = {}}
    for _, w in ipairs(D.windows) do
        if w.visible and not w.modal then
            table.insert(cfg.windows, {
                title = w.title,
                cx = w.cx, cy = w.cy,
                cw = w.cw, ch = w.ch
            })
        end
    end
    if not fs.isDir("/ccos/config") then fs.makeDir("/ccos/config") end
    local f = fs.open(D.configPath, "w")
    if f then
        f.write(textutils.serialize(cfg))
        f.close()
    end
end

D.startMenuDragY = nil
D.startMenuDragScroll = nil
D.dragAppWin = nil  -- window receiving internal drag (pan, etc.)
D.dragAppOX = 0
D.dragAppOY = 0

D.iconScrollY = 0

D.markDirty = function() D.dirty = true end
D.markContentDirty = function(win) D._contentWin = win end
D.markClockDirty = function() D._clockDirty = true end
D.startMenuScroll = 0
D.startMenuSel = 1
D.startMenuMaxVisible = 99

-- ============================================================
-- ERROR HANDLER
-- ============================================================
function D.showError(title, message)
    local wx, wy, ww, wh = D.fitWin(240, 80)
    local w = D.createWindow(title or "Error", wx, wy, ww, wh)
    w.modal = true
    w.onDraw = function(_, cx, cy, cw, ch)
        R.fillRect(cx+2, cy+2, cw-4, ch-4, K.GRAY)
        -- Error icon (red X)
        R.drawText(cx+6, cy+6, "X", K.RED, K.GRAY)
        -- Message (word wrap manually by line length)
        local maxChars = math.floor((cw - 20) / 6)
        local text = tostring(message) or "Unknown error"
        local lines = {}
        while #text > 0 do
            local piece = text:sub(1, maxChars)
            table.insert(lines, piece)
            text = text:sub(maxChars + 1)
        end
        if #lines == 0 then lines = {"Unknown error"} end
        for i, line in ipairs(lines) do
            R.drawText(cx+20, cy+6 + (i-1)*8, line, K.BLACK, K.GRAY)
        end
        -- OK button
        local bw = 40
        local bx = cx + math.floor((cw - bw) / 2)
        local by2 = cy + ch - 18
        R.drawButton(bx, by2, bw, 14, false)
        R.drawText(bx + 14, by2 + 3, "OK", K.BLACK, K.GRAY)
    end
    w.onClick = function(_, mx, my)
        local bw = 40
        local bx = math.floor((w.cw - bw) / 2)
        local by2 = w.ch - 18
        if mx >= bx and mx < bx + bw and my >= by2 and my < by2 + 14 then
            D.destroyWindow(w)
        end
    end
    w.onKey = function(_, k)
        if k == keys.enter or k == keys.escape then
            D.destroyWindow(w)
        end
    end
end

function D.showContextMenu(cx, cy)
    local items = {
        {"Refresh", function() D.loadPrograms(); D.markDirty() end},
        {"Save Session", function() D.saveConfig() end},
        {"Separator", nil},
        {"Settings", function() for _, p in ipairs(D.programs) do if p.icon == "settings" then D.safeRun(p.run) break end end end},
        {"Reboot", function() os.reboot() end},
        {"Shutdown", function() os.shutdown() end},
    }
    local itemH = 14
    local mw = 100
    local mh = #items * itemH + 4
    if cy + mh > R.h - D.taskbarH then cy = R.h - D.taskbarH - mh end
    if cx + mw > R.w then cx = R.w - mw end
    local w = D.createWindow("Menu", cx, cy, mw, mh)
    w.modal = true
    w.onDraw = function(_, wx, wy, ww, wh)
        R.fillRect(wx, wy, ww, wh, K.GRAY)
        R.drawW95Raised(wx, wy, ww, wh)
        for i, it in ipairs(items) do
            local iy = wy + 2 + (i - 1) * itemH
            local hit = D.mouse.x >= wx + 2 and D.mouse.x < wx + ww - 2 and D.mouse.y >= iy and D.mouse.y < iy + itemH
            if it[1] == "Separator" then
                R.drawLine(wx + 4, iy + math.floor(itemH / 2), wx + ww - 4, iy + math.floor(itemH / 2), K.DGRAY)
            else
                if hit then R.fillRect(wx + 2, iy, ww - 4, itemH, K.DBLUE) end
                R.drawText(wx + 6, iy + 2, it[1], hit and K.WHITE or K.BLACK, hit and K.DBLUE or K.GRAY)
            end
        end
    end
    w.onClick = function(_, mx, my)
        for i, it in ipairs(items) do
            local iy = 2 + (i - 1) * itemH
            if my >= iy and my < iy + itemH and it[1] ~= "Separator" then
                D.destroyWindow(w)
                if it[2] then it[2]() end
                return
            end
        end
        D.destroyWindow(w)
    end
    w.onKey = function(_, k)
        if k == keys.escape then D.destroyWindow(w) end
    end
end

function D.safeRun(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        D.showError("Application Error", tostring(err))
        return false, err
    end
    return true
end

function D.fitWin(ww, wh)
    ww = math.min(ww, R.w - 4)
    wh = math.min(wh, R.h - D.taskbarH - 4)
    local x = math.max(1, math.floor((R.w - ww) / 2))
    local y = math.max(1, math.floor((R.h - D.taskbarH - wh) / 2))
    return x, y, ww, wh
end

function D.loadPrograms()
    D.programs = {}
    if not fs.isDir("/ccos/programs") then D.rebuildIconCache(); return end
    for _, name in ipairs(fs.list("/ccos/programs")) do
        local path = "/ccos/programs/" .. name .. "/program.lua"
        if fs.exists(path) then
            local ok, prog = pcall(function()
                local fn, err = loadfile(path)
                if not fn then error("loadfile: " .. tostring(err)) end
                return fn()
            end)
            if ok and prog and prog.name and prog.run then
                table.insert(D.programs, prog)
            else
                print("[CCOS] Failed to load program '" .. name .. "': " .. tostring(prog))
            end
        end
    end
    D.rebuildIconCache()
end

function D.createWindow(title, cx, cy, cw, ch)
    local id = D.nextWinId; D.nextWinId = id + 1
    local w = {id=id,title=title or "Win",cx=cx or 30,cy=cy or 20,cw=cw or 200,ch=ch or 120,visible=true,minimized=false,onDraw=nil,onKey=nil,onClick=nil,onDoubleClick=nil}
    table.insert(D.windows,w); D.activeWin=w; D.markDirty(); return w
end

function D.destroyWindow(w)
    for i,v in ipairs(D.windows) do if v.id==w.id then table.remove(D.windows,i); break end end
    D.activeWin=D.windows[#D.windows]; w.visible=false; D.markDirty()
end

function D.bringToFront(w)
    for i,v in ipairs(D.windows) do if v.id==w.id then table.remove(D.windows,i); table.insert(D.windows,w); D.activeWin=w; D.markDirty(); return end end
end

function D.winAt(mx,my)
    for i=#D.windows,1,-1 do local w=D.windows[i]; if w.visible and not w.minimized and mx>=w.cx and mx<w.cx+w.cw and my>=w.cy and my<w.cy+w.ch then return w end end return nil
end

function D.inputDialog(title,prompt,default,callback)
    default=default or ""; local input=default
    local wx,wy,ww,wh=D.fitWin(240,80); local w=D.createWindow(title,wx,wy,ww,wh)
    w.onDraw=function(win,cx,cy,cw,ch)
        R.drawText(cx+4,cy+4,prompt,K.BLACK,K.GRAY)
        R.drawW95Sunken(cx+4,cy+18,cw-8,16)
        R.drawText(cx+6,cy+20,input.."_",K.BLACK,K.GRAY)
        R.drawText(cx+4,cy+42,"Enter=OK  Esc=Cancel",K.BLACK,K.GRAY)
    end
    w.onKey=function(win,k,ch)
        if ch then input=input..ch; D.markContentDirty(win)
        elseif k==keys.backspace then input=input:sub(1,-2); D.markContentDirty(win)
        elseif k==keys.enter then local r=input~="" and input or nil; D.destroyWindow(w); if callback then callback(r) end
        elseif k==keys.escape then D.destroyWindow(w); if callback then callback(nil) end end
    end
    return w
end

function D._startMenuMetrics()
    local by = R.h - D.taskbarH
    local mw = 140
    local totalItems = #D.programs + 2
    local itemH = 14
    local pad = 4
    local contentHeight = totalItems * itemH + pad * 2
    local maxH = by - 4
    local mh = math.min(maxH, math.max(64, contentHeight))
    local my = by - mh
    if my < 4 then my = 4; mh = by - 4 end
    local sx = 2
    local innerY = my + pad
    local innerH = mh - pad * 2
    local maxVisible = math.floor(innerH / itemH)
    local needsScroll = totalItems > maxVisible
    return mw, mh, my, sx, innerY, innerH, maxVisible, totalItems, itemH, pad, needsScroll
end

-- ============================================================
-- DRAW
-- ============================================================
function D._drawFull()
    R.beginDraw(); local by=R.h-D.taskbarH

    -- Desktop bg
    R.fillRect(0,0,R.w,by,K.DESKTOP)

    -- Desktop icons (cached layout)
    if R.w ~= D.lastIconCacheW or R.h ~= D.lastIconCacheH then
        D.rebuildIconCache()
    end
    for _, ic in ipairs(D.iconCache) do
        local hover = D.mouse.x >= ic.ix - 2 and D.mouse.x < ic.ix + ic.iw + 2 and D.mouse.y >= ic.iy - 2 and D.mouse.y < ic.iy + ic.ih + 2
        if hover then
            R.fillRect(ic.ix - 2, ic.iy - 2, ic.iw + 4, ic.ih + 4, K.DBLUE)
            R.fillRect(ic.ix, ic.iy, ic.iw, 24, K.LGRAY); R.drawW95Sunken(ic.ix, ic.iy, ic.iw, 24)
            R.drawText(ic.ix + math.floor((ic.iw - 6) / 2), ic.iy + 7, ic.prog.name:sub(1, 1):upper(), K.DBLUE, K.LGRAY)
            R.drawText(ic.ix + math.floor((ic.iw - #ic.lab * 6) / 2), ic.iy + 28, ic.lab, K.WHITE, K.DBLUE)
        else
            R.fillRect(ic.ix, ic.iy, ic.iw, 24, K.LGRAY); R.drawW95Sunken(ic.ix, ic.iy, ic.iw, 24)
            R.drawText(ic.ix + math.floor((ic.iw - 6) / 2), ic.iy + 7, ic.prog.name:sub(1, 1):upper(), K.DBLUE, K.LGRAY)
            R.drawText(ic.ix + math.floor((ic.iw - #ic.lab * 6) / 2), ic.iy + 28, ic.lab, K.WHITE, K.DESKTOP)
        end
    end

    -- Windows
    for _,w in ipairs(D.windows) do if w.visible and not w.minimized then
        local x,y,ww,hh=w.cx,w.cy,w.cw,w.ch; if y+hh>by then hh=math.max(20,by-y) end
        local act=D.activeWin and D.activeWin.id==w.id
        -- Background + content
        R.fillRect(x,y,ww,hh,K.GRAY)
        R.fillRect(x+2,y+17,ww-4,hh-19,K.GRAY)
        if w.onDraw then pcall(w.onDraw,w,x+3,y+18,ww-6,hh-21) end
        -- Title bar & frame on top to clip overflow
        R.fillRect(x,y,ww,18,act and K.DBLUE or K.GRAY)
        R.drawText(x+4,y+4,w.title,act and K.WHITE or K.LGRAY,act and K.DBLUE or K.GRAY)
        R.drawButton(x+ww-54,y+1,16,14,false); R.drawText(x+ww-49,y+4,"_",K.BLACK,K.GRAY)
        R.drawButton(x+ww-36,y+1,16,14,false); R.drawText(x+ww-31,y+4,"[]",K.BLACK,K.GRAY)
        R.drawButton(x+ww-18,y+1,16,14,false); R.drawText(x+ww-13,y+4,"X",K.BLACK,K.GRAY)
        R.drawW95Raised(x,y,ww,hh)
        if not w.maximized then
            R.fillRect(x+ww-6, y+hh-6, 6, 6, K.DGRAY)
        end
    end end

    -- Taskbar
    R.fillRect(0,by,R.w,D.taskbarH,K.GRAY); R.drawLine(0,by,R.w-1,by,K.WHITE)
    R.drawButton(2,by+2,54,16,D.startMenuOpen); R.drawText(6,by+6,"Start",K.BLACK,K.GRAY)
    local bx=60; for _,w in ipairs(D.windows) do local bw=math.min(100,R.w-bx-55); if bw<25 then break end
        local active=D.activeWin and D.activeWin.id==w.id; R.drawButton(bx,by+3,bw,14,active)
        local t=#w.title>12 and w.title:sub(1,10)..".." or w.title; if w.minimized then t="("..t..")" end
        R.drawText(bx+4,by+6,t,active and K.WHITE or K.BLACK,active and K.GRAY or K.GRAY)
        bx=bx+bw+2
    end
    R.drawW95Sunken(R.w-48,by+3,44,14); R.drawText(R.w-44,by+6,D.clock,K.BLACK,K.GRAY)

    -- Start Menu
    if D.startMenuOpen then
        local mw, mh, my, sx, innerY, innerH, maxVisible, totalItems, itemH, pad, needsScroll = D._startMenuMetrics()
        R.fillRect(sx, my, mw, mh, K.GRAY)
        R.drawW95Raised(sx, my, mw, mh)
        -- Sidebar
        R.fillRect(sx + 2, my + 2, 20, mh - 4, K.DBLUE)
        R.drawText(sx + 3, my + math.floor(mh / 2) - 4, "CC", K.WHITE, K.DBLUE)
        -- Scrollbar
        if needsScroll then
            local barH = math.max(8, math.floor(innerH * maxVisible / totalItems))
            local barY = innerY + math.floor((innerH - barH) * D.startMenuScroll / (totalItems - maxVisible))
            R.fillRect(sx + mw - 6, barY, 4, barH, K.DGRAY)
        else
            D.startMenuScroll = 0
        end
        local firstItem = D.startMenuScroll + 1
        local lastItem = math.min(totalItems, maxVisible + D.startMenuScroll)
        -- Detect if mouse is hovering any item
        local hasHit = false
        for idx = firstItem, lastItem do
            local iy = innerY + (idx - firstItem) * itemH
            if D.mouse.x >= sx + 24 and D.mouse.x < sx + mw - 8 and D.mouse.y >= iy and D.mouse.y < iy + itemH then
                hasHit = true; break
            end
        end
        for idx = firstItem, lastItem do
            local iy = innerY + (idx - firstItem) * itemH
            local label = ""
            if idx <= #D.programs then label = D.programs[idx].name
            elseif idx == #D.programs + 1 then label = "Reboot"
            elseif idx == #D.programs + 2 then label = "Shutdown" end
            local hit = D.mouse.x >= sx + 24 and D.mouse.x < sx + mw - 8 and D.mouse.y >= iy and D.mouse.y < iy + itemH
            local active = (hasHit and hit) or (not hasHit and idx == D.startMenuSel)
            if active then R.fillRect(sx + 24, iy, mw - 32, itemH, K.DBLUE) end
            R.drawText(sx + 28, iy + 2, label, active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY)
        end
    end

    R.endDraw()
end

function D.drawAll()
    if not D.dirty and not D._contentWin and not D._clockDirty then return end
    R.beginDraw(); local topWin=D.windows[#D.windows]
    if D.dirty or (D._contentWin and D._contentWin~=topWin) then
        D._drawFull(); D.dirty=false; D._contentWin=nil; D._clockDirty=false
    else
        if D._contentWin then local w=D._contentWin
            if w.visible then
                R.fillRect(w.cx+2,w.cy+17,w.cw-4,w.ch-19,K.GRAY)
                if w.onDraw then pcall(w.onDraw,w,w.cx+3,w.cy+18,w.cw-6,w.ch-21) end
                -- Redraw frame to clip any content overflow
                local x,y,ww,hh=w.cx,w.cy,w.cw,w.ch; local by=R.h-D.taskbarH; if y+hh>by then hh=math.max(20,by-y) end
                local act=D.activeWin and D.activeWin.id==w.id
                R.fillRect(x,y,ww,18,act and K.DBLUE or K.GRAY)
                R.drawText(x+4,y+4,w.title,act and K.WHITE or K.LGRAY,act and K.DBLUE or K.GRAY)
                R.drawButton(x+ww-54,y+1,16,14,false); R.drawText(x+ww-49,y+4,"_",K.BLACK,K.GRAY)
                R.drawButton(x+ww-36,y+1,16,14,false); R.drawText(x+ww-31,y+4,"[]",K.BLACK,K.GRAY)
                R.drawButton(x+ww-18,y+1,16,14,false); R.drawText(x+ww-13,y+4,"X",K.BLACK,K.GRAY)
                R.drawW95Raised(x,y,ww,hh)
                if not w.maximized then
                    R.fillRect(x+ww-6, y+hh-6, 6, 6, K.DGRAY)
                end
            end
            D._contentWin=nil
        end
        if D._clockDirty then local by=R.h-D.taskbarH; R.fillRect(R.w-48,by+3,44,14,K.GRAY); R.drawW95Sunken(R.w-48,by+3,44,14); R.drawText(R.w-44,by+6,D.clock,K.BLACK,K.GRAY); D._clockDirty=false end
    end
    R.endDraw()
end

-- ============================================================
-- INPUT
-- ============================================================
function D.click(mx,my,btn)
    local by=R.h-D.taskbarH
    -- Right-click on empty desktop
    if btn==2 then
        if my>=by then return nil end
        local w=D.winAt(mx,my)
        if w then return nil end
        if R.w ~= D.lastIconCacheW or R.h ~= D.lastIconCacheH then D.rebuildIconCache() end
        for _, ic in ipairs(D.iconCache) do
            if mx>=ic.ix-2 and mx<ic.ix+ic.iw+2 and my>=ic.iy-2 and my<ic.iy+ic.ih+2 then return nil end
        end
        D.showContextMenu(mx,my)
        return nil
    end
    -- Start button
    if mx>=2 and mx<56 and my>=by+2 and my<by+18 then
        D.startMenuOpen=not D.startMenuOpen; if D.startMenuOpen then D.startMenuSel=1; D.startMenuScroll=0 else D.startMenuScroll=0 end; D.markDirty(); return nil
    end
    -- Start menu
    if D.startMenuOpen then
        local mw, mh, my2, sx, innerY, innerH, maxVisible, totalItems, itemH, pad, needsScroll = D._startMenuMetrics()
        if mx >= sx and mx < sx + mw and my >= my2 and my < my2 + mh then
            if mx >= sx + 24 and mx < sx + mw - 8 and my >= innerY and my < innerY + innerH then
                -- Click in scrollable content area — begin drag
                D.startMenuDragY = my
                D.startMenuDragScroll = D.startMenuScroll
            end
            for idx = D.startMenuScroll + 1, totalItems do
                local iy = innerY + (idx - D.startMenuScroll - 1) * itemH
                if my >= iy and my < iy + itemH then
                    D.startMenuSel = idx
                    if idx <= #D.programs then D.startMenuOpen = false; D.startMenuScroll = 0; D.markDirty(); D.safeRun(D.programs[idx].run)
                    elseif idx == #D.programs + 1 then D.startMenuOpen = false; D.startMenuScroll = 0; D.markDirty(); os.reboot()
                    elseif idx == #D.programs + 2 then D.startMenuOpen = false; D.startMenuScroll = 0; D.markDirty(); os.shutdown() end
                    return nil
                end
            end
            return nil
        else
            D.startMenuOpen = false; D.startMenuScroll = 0; D.markDirty()
            return nil -- prevent click-through to desktop icons
        end
    end
    -- Taskbar
    if my>=by then local bx=60; for _,w in ipairs(D.windows) do local bw=math.min(100,R.w-bx-55); if bw<25 then break end
        if mx>=bx and mx<bx+bw then
            if w.minimized then w.minimized=false; w.visible=true; D.bringToFront(w)
            elseif D.activeWin and D.activeWin.id==w.id then w.minimized=true
            else D.bringToFront(w) end
            D.markDirty(); return nil
        end; bx=bx+bw+2
    end; return nil end
    -- Windows
    local w=D.winAt(mx,my); if w then D.bringToFront(w)
        if my>=w.cy and my<w.cy+16 then
            if mx>=w.cx+w.cw-18 then D.destroyWindow(w); return nil end
            if mx>=w.cx+w.cw-36 and mx<w.cx+w.cw-20 then
                if w.maximized then if w.prevState then w.cx=w.prevState.x; w.cy=w.prevState.y; w.cw=w.prevState.w; w.ch=w.prevState.h; w.prevState=nil end; w.maximized=false
                else w.prevState={x=w.cx,y=w.cy,w=w.cw,h=w.ch}; w.cx=1; w.cy=1; w.cw=R.w; w.ch=by-1; w.maximized=true end
                D.markDirty(); return nil
            end
            if mx>=w.cx+w.cw-54 and mx<w.cx+w.cw-38 then w.minimized=true; D.markDirty(); return nil end
            if not w.maximized then D.dragWin=w; D.dragOX=mx-w.cx; D.dragOY=my-w.cy end; return nil
        end
        if not w.maximized and mx>=w.cx+w.cw-8 and my>=w.cy+w.ch-8 then
            D.resizeWin=w; D.resizeOX=w.cw-(mx-w.cx); D.resizeOY=w.ch-(my-w.cy); return nil
        end
        -- App-level drag (pan, etc.) if window has onDrag
        if w.onDrag then
            D.dragAppWin = w
            D.dragAppOX = mx
            D.dragAppOY = my
        end
        if w.onClick then pcall(w.onClick,w,mx-w.cx-3,my-w.cy-18) end; return nil
    end
    -- Desktop icons (cached layout)
    if R.w ~= D.lastIconCacheW or R.h ~= D.lastIconCacheH then
        D.rebuildIconCache()
    end
    for _, ic in ipairs(D.iconCache) do
        if mx >= ic.ix - 2 and mx < ic.ix + ic.iw + 2 and my >= ic.iy - 2 and my < ic.iy + ic.ih + 2 then
            D.safeRun(ic.prog.run)
            return nil
        end
    end
    return nil
end

function D.drag(mx,my)
    if D.startMenuOpen and D.startMenuDragY then
        local mw, mh, my2, sx, innerY, innerH, maxVisible, totalItems, itemH, pad, needsScroll = D._startMenuMetrics()
        if needsScroll then
            local dy = D.startMenuDragY - my
            local delta = math.floor(dy / itemH)
            D.startMenuScroll = math.max(0, math.min(totalItems - maxVisible, D.startMenuDragScroll + delta))
            D.markDirty()
        end
        return
    end
    -- App-level drag (pan inside window content)
    local w = D.dragAppWin
    if w then
        local dx = mx - D.dragAppOX
        local dy = my - D.dragAppOY
        D.dragAppOX = mx
        D.dragAppOY = my
        if w.onDrag then pcall(w.onDrag, w, dx, dy) end
        return
    end
    w=D.dragWin; if not w then
        w=D.resizeWin; if not w then return end
        local nw = mx - w.cx + D.resizeOX
        local nh = my - w.cy + D.resizeOY
        w.cw = math.max(80, math.min(R.w - w.cx + 1, nw))
        w.ch = math.max(40, math.min(R.h - D.taskbarH - w.cy + 1, nh))
        D.markDirty()
        return
    end
    w.cx=mx-D.dragOX; w.cy=my-D.dragOY; if w.cy<1 then w.cy=1 end; local by=R.h-D.taskbarH; if w.cy+w.ch>by+1 then w.cy=by-w.ch+2 end
    D.markDirty()
end

function D.drop() D.dragWin=nil; D.resizeWin=nil; D.startMenuDragY=nil; D.startMenuDragScroll=nil; D.dragAppWin=nil end

-- ============================================================
-- MAIN LOOP
-- ============================================================
function D.run()
    local ok, err = pcall(function()
        R.init(); D.loadPrograms(); D.loadConfig(); local running=true; local lastTimer=nil; D.markDirty()
        while running do
            D.drawAll()
            if lastTimer then os.cancelTimer(lastTimer) end
            lastTimer = os.startTimer(1)
            local e,a,b,c,d=os.pullEvent()
            if e=="timer" then
                local t=os.time and os.time() or 0; local h=math.floor(t); local m=math.floor((t-h)*60); local nc=string.format("%02d:%02d",h,m); if nc~=D.clock then D.clock=nc; D.markClockDirty() end
            end
            if e=="mouse_click" then D.mouse.x=b; D.mouse.y=c; D.click(b,c,a)
            elseif e=="mouse_double_click" then D.mouse.x=b; D.mouse.y=c; local w=D.winAt(b,c); if w then D.bringToFront(w); if w.onDoubleClick then pcall(w.onDoubleClick,w,b-w.cx-3,c-w.cy-18) end end
            elseif e=="mouse_drag" then D.mouse.x=b; D.mouse.y=c; D.drag(b,c)
            elseif e=="mouse_up" then D.drop()
            elseif e=="mouse_scroll" then
                D.mouse.x=b; D.mouse.y=c
                if D.startMenuOpen then
                    local mw, mh, my2, sx, innerY, innerH, maxVisible, totalItems, itemH, pad, needsScroll = D._startMenuMetrics()
                    if needsScroll then
                        if a > 0 then
                            D.startMenuScroll = math.max(0, D.startMenuScroll - math.floor(maxVisible/3))
                        else
                            D.startMenuScroll = math.min(totalItems - maxVisible, D.startMenuScroll + math.floor(maxVisible/3))
                        end
                        D.markDirty()
                    end
                else
                    -- Desktop icon scroll
                    local by = R.h - D.taskbarH
                    local totalRows = math.ceil(#D.programs / math.max(1, math.floor((R.w - 10) / 58)))
                    local visibleRows = math.max(1, math.floor((by - 8) / 50))
                    if totalRows > visibleRows then
                        if a > 0 then
                            D.iconScrollY = math.max(0, D.iconScrollY - 1)
                        else
                            D.iconScrollY = math.min(totalRows - visibleRows, D.iconScrollY + 1)
                        end
                        D.rebuildIconCache()
                        D.markDirty()
                    end
                end
            elseif e=="key" then
                if D.startMenuOpen then
                    local mw, mh, my, sx, innerY, innerH, maxVisible, totalItems, itemH, pad, needsScroll = D._startMenuMetrics()
                    if a==keys.up then
                        D.startMenuSel = math.max(1, D.startMenuSel - 1)
                        if D.startMenuSel <= D.startMenuScroll + 1 then D.startMenuScroll = math.max(0, D.startMenuSel - 1) end
                        D.markDirty()
                    elseif a==keys.down then
                        D.startMenuSel = math.min(totalItems, D.startMenuSel + 1)
                        if D.startMenuSel > D.startMenuScroll + maxVisible then D.startMenuScroll = math.min(totalItems - maxVisible, D.startMenuSel - maxVisible) end
                        D.markDirty()
                    elseif a==keys.enter then
                        local idx = D.startMenuSel
                        D.startMenuOpen=false; D.startMenuScroll=0; D.markDirty()
                        if idx<=#D.programs then D.safeRun(D.programs[idx].run)
                        elseif idx==#D.programs+1 then os.reboot()
                        elseif idx==#D.programs+2 then os.shutdown() end
                    elseif a==keys.escape then
                        D.startMenuOpen=false; D.startMenuScroll=0; D.markDirty()
                    end
                elseif D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey,D.activeWin,a,nil) end
            elseif e=="char" then
                if not D.startMenuOpen and D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey,D.activeWin,nil,a) end
            end
        end
        R.beginDraw(); R.clear(); R.fillRect(0,0,R.w,R.h,K.BLACK); R.drawText(10,10,"CCOS shutdown.",K.WHITE,K.BLACK); R.endDraw(); sleep(0.3); R.shutdown()
    end)
    if not ok then
        R.bsod("0xDEADCC0S", tostring(err))
        os.pullEvent("key")
        os.reboot()
    end
end

return D
