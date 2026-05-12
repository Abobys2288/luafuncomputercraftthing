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
    if not fs.isDir("/ccos/programs") then return end
    for _, name in ipairs(fs.list("/ccos/programs")) do
        local path = "/ccos/programs/" .. name .. "/program.lua"
        if fs.exists(path) then
            local ok, prog = pcall(function()
                local fn = loadfile(path)
                return fn and fn()
            end)
            if ok and prog and prog.name and prog.run then
                table.insert(D.programs, prog)
            end
        end
    end
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

-- ============================================================
-- DRAW
-- ============================================================
function D._drawFull()
    R.beginDraw(); local by=R.h-D.taskbarH

    -- Desktop bg
    R.fillRect(0,0,R.w,by,K.DESKTOP)

    -- Desktop icons
    local iw,ih=48,42; local cols=math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,prog in ipairs(D.programs) do
        local col=(i-1)%cols; local row=math.floor((i-1)/cols)
        local ix,iy=8+col*(iw+10),8+row*(ih+8)
        if iy+ih>by then break end
        local hover=D.mouse.x>=ix-2 and D.mouse.x<ix+iw+2 and D.mouse.y>=iy-2 and D.mouse.y<iy+ih+2
        if hover then R.fillRect(ix-2,iy-2,iw+4,ih+4,K.DBLUE) end
        R.fillRect(ix,iy,iw,24,K.LGRAY); R.drawW95Sunken(ix,iy,iw,24)
        R.drawText(ix+math.floor((iw-6)/2),iy+7,prog.name:sub(1,1):upper(),K.DBLUE,K.LGRAY)
        local lab=prog.name; if #lab>8 then lab=lab:sub(1,7)..".." end
        R.drawText(ix+math.floor((iw-#lab*6)/2),iy+28,lab,K.WHITE,K.DESKTOP)
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
        local mw=140; local totalItems=#D.programs+2; local itemH=12
        local contentHeight=totalItems*itemH+6; local available=by-10
        local mh=math.min(available,math.max(96,contentHeight)); local my=(by+2)-mh; if my<1 then my=1 end
        local sx=2; R.fillRect(sx,my,mw,mh,K.GRAY); R.drawW95Raised(sx,my,mw,mh)
        R.fillRect(sx+2,my+2,20,mh-4,K.DBLUE); R.drawText(sx+3,my+30,"CC",K.WHITE,K.DBLUE)
        local maxVisible=math.floor((mh-8)/itemH); local needsScroll=totalItems>maxVisible
        if needsScroll then
            local barH=math.max(8,math.floor(mh*maxVisible/totalItems))
            local barY=my+4+math.floor((mh-8-barH)*D.startMenuScroll/(totalItems-maxVisible))
            R.fillRect(sx+mw-6,barY,4,barH,K.DGRAY)
        else D.startMenuScroll=0 end
        local firstItem=D.startMenuScroll+1; local lastItem=math.min(totalItems,maxVisible+D.startMenuScroll)
        local iy=my+4; if needsScroll then iy=iy+14 end
        for idx=firstItem,lastItem do
            local label = ""
            if idx<=#D.programs then label = D.programs[idx].name
            elseif idx==#D.programs+1 then label = "Reboot"
            elseif idx==#D.programs+2 then label = "Shutdown" end
            local hit=D.mouse.x>=sx+24 and D.mouse.x<sx+mw-8 and D.mouse.y>=iy and D.mouse.y<iy+itemH
            local active = hit or (idx == D.startMenuSel)
            if active then R.fillRect(sx+24,iy,mw-32,itemH,K.DBLUE) end
            R.drawText(sx+28,iy+2,label,active and K.WHITE or K.BLACK,active and K.DBLUE or K.GRAY)
            iy=iy+itemH
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
function D.click(mx,my)
    local by=R.h-D.taskbarH
    -- Start button
    if mx>=2 and mx<56 and my>=by+2 and my<by+18 then
        D.startMenuOpen=not D.startMenuOpen; if D.startMenuOpen then D.startMenuSel=1; D.startMenuScroll=0 else D.startMenuScroll=0 end; D.markDirty(); return nil
    end
    -- Start menu
    if D.startMenuOpen then
        local mw=140; local totalItems=#D.programs+2; local itemH=12
        local contentHeight=totalItems*itemH+6; local available=by-10
        local mh=math.min(available,math.max(96,contentHeight)); local my2=(by+2)-mh; if my2<1 then my2=1 end
        if mx>=2 and mx<2+mw and my>=my2 and my<my2+mh then
            local maxVisible=math.floor((mh-8)/itemH); local needsScroll=totalItems>maxVisible
            local firstItem=D.startMenuScroll+1; local itemY=my2+4; if needsScroll then itemY=itemY+14 end
            for idx=firstItem,totalItems do
                if my>=itemY and my<itemY+itemH then
                    D.startMenuSel=idx
                    if idx<=#D.programs then D.startMenuOpen=false; D.startMenuScroll=0; D.markDirty(); D.safeRun(D.programs[idx].run)
                    elseif idx==#D.programs+1 then D.startMenuOpen=false; D.startMenuScroll=0; D.markDirty(); os.reboot()
                    elseif idx==#D.programs+2 then D.startMenuOpen=false; D.startMenuScroll=0; D.markDirty(); os.shutdown() end
                    return nil
                end
                itemY=itemY+itemH
            end
            return nil
        else D.startMenuOpen=false; D.startMenuScroll=0; D.markDirty() end
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
        if w.onClick then pcall(w.onClick,w,mx-w.cx-3,my-w.cy-18) end; return nil
    end
    -- Desktop icons
    local iw,ih=48,42; local cols=math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,prog in ipairs(D.programs) do local col=(i-1)%cols; local row=math.floor((i-1)/cols); local ix,iy=8+col*(iw+10),8+row*(ih+8)
        if mx>=ix-2 and mx<ix+iw+2 and my>=iy-2 and my<iy+ih+2 then D.safeRun(prog.run); return nil end
    end
    return nil
end

function D.drag(mx,my)
    local w=D.dragWin; if not w then
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

function D.drop() D.dragWin=nil; D.resizeWin=nil end

-- ============================================================
-- MAIN LOOP
-- ============================================================
function D.run()
    local ok, err = pcall(function()
        R.init(); D.loadPrograms(); local running=true; local timer=os.startTimer(1); D.markDirty()
        while running do
            D.drawAll(); local e,a,b,c,d=os.pullEvent()
            if e=="mouse_click" then D.mouse.x=b; D.mouse.y=c; D.click(b,c)
            elseif e=="mouse_double_click" then D.mouse.x=b; D.mouse.y=c; local w=D.winAt(b,c); if w then D.bringToFront(w); if w.onDoubleClick then pcall(w.onDoubleClick,w,b-w.cx-3,c-w.cy-18) end end
            elseif e=="mouse_drag" then D.mouse.x=b; D.mouse.y=c; D.drag(b,c)
            elseif e=="mouse_up" then D.drop()
            elseif e=="key" then
                if D.startMenuOpen then
                    local totalItems=#D.programs+2
                    local by=R.h-D.taskbarH; local available=by-10
                    local mh=math.min(available,math.max(96,totalItems*12+6))
                    local maxVisible=math.floor((mh-8)/12)
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
            elseif e=="char" then if D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey,D.activeWin,nil,a) end
            elseif e=="timer" and a==timer then local t=os.time and os.time() or 0; local h=math.floor(t); local m=math.floor((t-h)*60); local nc=string.format("%02d:%02d",h,m); if nc~=D.clock then D.clock=nc; D.markClockDirty() end; timer=os.startTimer(1) end
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
