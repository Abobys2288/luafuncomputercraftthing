--[[
    CCOS Desktop v9 — clean rewrite
]]

local R = _G.ccos_render
local D = {} _G._desktop = D

local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,CYAN=7,LBLUE=8,
    GREEN=9,DGREEN=10,RED=11,DRED=12,YELLOW=13,ORANGE=14,BROWN=15,PURPLE=16,PINK=17,
    DTITLE=18,TBLUE=19,TINACT=20,DESKTOP=30}

D.windows={} D.activeWin=nil D.taskbarH=20 D.startMenuOpen=false D.clock=""
D.nextWinId=1 D.dragWin=nil D.dragOX=0 D.dragOY=0 D.lastDrag=nil
D.mouse={x=0,y=0} D.needRedraw=false

local function gd(p)
    if not p or p=="/" then return "/" end
    local t={} for s in p:gmatch("[^/]+") do t[#t+1]=s end
    if #t<=1 then return "/" end t[#t]=nil
    return "/"..table.concat(t,"/")
end

local function gfn(p)
    if not p or p=="/" then return "" end
    local l=nil for s in p:gmatch("[^/]+") do l=s end
    return l or ""
end

local function rf(p)
    if not fs.exists(p) then return nil end
    local f=fs.open(p,"r") if not f then return nil end
    local c=f.readAll() f.close() return c
end

function D.redraw() D.needRedraw=true end

function D.createWindow(title,cx,cy,cw,ch)
    local id=D.nextWinId D.nextWinId=id+1
    local w={id=id,title=title or "Win",cx=cx or 30,cy=cy or 20,cw=cw or 200,ch=ch or 120,
        minW=80,minH=50,visible=true,maximized=false,minimized=false,prevState=nil,resizing=false,
        onDraw=nil,onKey=nil,onClick=nil}
    D.windows[#D.windows+1]=w D.activeWin=w D.redraw() return w
end

function D.destroyWindow(w)
    for i,v in ipairs(D.windows) do if v.id==w.id then table.remove(D.windows,i) break end end
    D.activeWin=D.windows[#D.windows] D.redraw()
end

function D.bringToFront(w)
    for i,v in ipairs(D.windows) do
        if v.id==w.id then table.remove(D.windows,i) D.windows[#D.windows+1]=w D.activeWin=w D.redraw() return end
    end
end

function D.winAt(mx,my)
    for i=#D.windows,1,-1 do
        local w=D.windows[i]
        if w.visible and not w.minimized and mx>=w.cx and mx<w.cx+w.cw and my>=w.cy and my<w.cy+w.ch then return w end
    end
    return nil
end

function D.drawAll()
    R.clear()
    local by=R.h-D.taskbarH
    R.fillRect(0,0,R.w,by,K.DESKTOP)

    -- Icons
    local ic={{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw,ih=48,42
    local cols=math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,c in ipairs(ic) do
        local col=(i-1)%cols local row=math.floor((i-1)/cols)
        local ix=8+col*(iw+10) local iy=8+row*(ih+8)
        if iy+ih>by-4 then break end
        if D.mouse.x>=ix-2 and D.mouse.x<ix+iw+2 and D.mouse.y>=iy-2 and D.mouse.y<iy+ih+2 then
            R.fillRect(ix-2,iy-2,iw+4,ih+4,K.DBLUE)
        end
        R.fillRect(ix,iy,iw,24,K.LGRAY) R.drawW95Sunken(ix,iy,iw,24)
        R.drawText(ix+16,iy+7,c[1]:sub(1,1),K.DBLUE)
        R.drawText(ix,iy+28,c[1],K.WHITE)
    end

    -- Windows
    for _,w in ipairs(D.windows) do if w.visible and not w.minimized then D.drawWin(w) end end

    -- Taskbar
    R.fillRect(0,by,R.w,D.taskbarH,K.GRAY)
    R.drawLine(0,by,R.w-1,by,K.WHITE)
    R.drawButton(2,by+2,54,16,D.startMenuOpen)
    R.drawText(6,by+6,"Start",K.BLACK)

    local bx=60
    for _,w in ipairs(D.windows) do
        local bw=math.min(100,R.w-bx-55) if bw<25 then break end
        local ia=D.activeWin and D.activeWin.id==w.id
        R.drawButton(bx,by+3,bw,14,ia)
        local t=#w.title>12 and w.title:sub(1,10)..".." or w.title
        if w.minimized then t="("..t..")" end
        R.drawText(bx+4,by+6,t,ia and K.WHITE or K.BLACK)
        bx=bx+bw+2
    end

    R.drawW95Sunken(R.w-48,by+3,44,14)
    R.drawText(R.w-44,by+6,D.clock,K.BLACK)

    -- Start menu (last, on top)
    if D.startMenuOpen then
        local mw,mh=140,96
        local my2=(by+2)-mh if my2<1 then my2=1 end
        local sx=2
        R.fillRect(sx,my2,mw,mh,K.GRAY)
        R.drawW95Raised(sx,my2,mw,mh)
        R.fillRect(sx+2,my2+2,20,mh-4,K.DBLUE)
        R.drawText(sx+3,my2+30,"CC",K.WHITE)
        local items={{"File Manager","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"},{"Reboot","reboot"},{"Shutdown","shutdown"}}
        local iy=my2+4
        for _,it in ipairs(items) do
            local hit=D.mouse.x>=sx+24 and D.mouse.x<sx+mw-4 and D.mouse.y>=iy and D.mouse.y<iy+12
            if hit then R.fillRect(sx+24,iy,mw-28,12,K.DBLUE) end
            R.drawText(sx+28,iy+2,it[1],hit and K.WHITE or K.BLACK)
            iy=iy+14
        end
    end

    D.needRedraw=false D.lastDrag=nil
end

function D.drawWin(w)
    local x,y,ww,hh=w.cx,w.cy,w.cw,w.ch
    local by=R.h-D.taskbarH
    if y+hh>by then hh=math.max(20,by-y) end
    R.fillRect(x,y,ww,hh,K.GRAY)
    local act=D.activeWin and D.activeWin.id==w.id
    R.drawTitleBar(x,y,ww,act)
    R.drawText(x+4,y+4,w.title,act and K.WHITE or K.LGRAY)
    R.drawButton(x+ww-18,y+1,16,14,false) R.drawText(x+ww-13,y+4,"X",K.BLACK)
    R.drawButton(x+ww-36,y+1,16,14,false) R.drawRect(x+ww-32,y+4,8,8,K.BLACK)
    R.drawButton(x+ww-54,y+1,16,14,false) R.fillRect(x+ww-49,y+6,6,2,K.BLACK)
    R.drawW95Raised(x,y,ww,hh)
    R.fillRect(x+2,y+17,ww-4,hh-19,K.GRAY)
    if w.onDraw then pcall(w.onDraw,w,x+3,y+18,ww-6,hh-21) end
end

function D.click(mx,my)
    local by=R.h-D.taskbarH
    -- 1. Start menu (if open)
    if D.startMenuOpen then
        local mw,mh=140,96
        local my2=(by+2)-mh if my2<1 then my2=1 end
        if mx>=2 and mx<2+mw and my>=my2 and my<my2+mh then
            local items={"files","edit","settings","shell","reboot","shutdown"}
            local iy=my2+4
            for _,a in ipairs(items) do
                if mx>=26 and mx<2+mw-4 and my>=iy and my<iy+12 then
                    D.startMenuOpen=false return a
                end
                iy=iy+14
            end
            return nil
        end
        D.startMenuOpen=false
    end
    -- 2. Start button
    if mx>=2 and mx<56 and my>=by+2 and my<by+18 then
        D.startMenuOpen=not D.startMenuOpen D.redraw() return nil
    end
    -- 3. Taskbar
    if my>=by then
        local bx=60
        for _,w in ipairs(D.windows) do
            local bw=math.min(100,R.w-bx-55) if bw<25 then break end
            if mx>=bx and mx<bx+bw then
                if w.minimized then w.minimized=false w.visible=true D.bringToFront(w) D.redraw()
                elseif D.activeWin and D.activeWin.id==w.id then w.minimized=true D.redraw()
                else D.bringToFront(w) D.redraw() end
                return nil
            end
            bx=bx+bw+2
        end
        return nil
    end
    -- 4. Windows (CONSUME ALL CLICKS)
    local w=D.winAt(mx,my)
    if w then
        D.bringToFront(w)
        if my>=w.cy and my<w.cy+16 then
            if mx>=w.cx+w.cw-18 then D.destroyWindow(w) return nil end
            if mx>=w.cx+w.cw-36 and mx<w.cx+w.cw-20 then
                if w.maximized then
                    if w.prevState then w.cx=w.prevState.x;w.cy=w.prevState.y;w.cw=w.prevState.w;w.ch=w.prevState.h;w.prevState=nil end
                    w.maximized=false
                else
                    w.prevState={x=w.cx,y=w.cy,w=w.cw,h=w.ch}
                    w.cx=1;w.cy=1;w.cw=R.w;w.ch=by-1;w.maximized=true
                end
                D.redraw() return nil
            end
            if mx>=w.cx+w.cw-54 and mx<w.cx+w.cw-38 then w.minimized=true D.redraw() return nil end
            if not w.maximized then D.dragWin=w D.dragOX=mx-w.cx D.dragOY=my-w.cy end
            return nil
        end
        if mx>=w.cx+w.cw-8 and my>=w.cy+w.ch-8 and not w.maximized then w.resizing=true return nil end
        -- Forward click to window
        if w.onClick then pcall(w.onClick,w,mx-w.cx-3,my-w.cy-18) end
        return nil
    end
    -- 5. Desktop icons
    local ic={{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw,ih=48,42
    local cols=math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,c in ipairs(ic) do
        local col=(i-1)%cols local row=math.floor((i-1)/cols)
        local ix=8+col*(iw+10) local iy=8+row*(ih+8)
        if mx>=ix-2 and mx<ix+iw+2 and my>=iy-2 and my<iy+ih+2 then return c[2] end
    end
    return nil
end

-- Double click tracking
local lastClickTime=0
local lastClickWin=nil

function D.handleMouseClick(mx,my,button)
    local now=os.clock and os.clock() or 0
    local isDouble=(now-lastClickTime<0.4)
    lastClickTime=now
    local w=D.winAt(mx,my)
    lastClickWin=w
    local action=D.click(mx,my)
    if action then return action end
    -- Double click on window
    if isDouble and w and w.onDoubleClick then
        pcall(w.onDoubleClick,w,mx-w.cx-3,my-w.cy-18)
    end
    return nil
end

function D.drag(mx,my)
    local w=D.dragWin if not w then return end
    local nx=mx-D.dragOX local ny=my-D.dragOY
    if ny<1 then ny=1 end
    local by=R.h-D.taskbarH if ny+w.ch>by+1 then ny=by-w.ch+2 end
    -- Erase old outline: just draw bg rect over it
    if D.lastDrag then
        local r=D.lastDrag
        R.fillRect(r.x,r.y,r.w,r.h,K.DESKTOP)
    end
    -- Draw new outline (fast, just 4 lines)
    R.drawDragOutline(nx,ny,w.cw,w.ch)
    D.lastDrag={x=nx,y=ny,w=w.cw,h=w.ch}
end

function D.drop()
    if D.dragWin then
        local w=D.dragWin
        w.cx=D.mouse.x-D.dragOX w.cy=D.mouse.y-D.dragOY
        if w.cy<1 then w.cy=1 end
        local by=R.h-D.taskbarH if w.cy+w.ch>by+1 then w.cy=by-w.ch+2 end
        D.dragWin=nil D.lastDrag=nil D.redraw()
    end
    for _,w in ipairs(D.windows) do w.resizing=false end
end

function D.key(key,char)
    if D.activeWin and D.activeWin.onKey then
        pcall(D.activeWin.onKey,D.activeWin,key,char)
        -- Redraw active window content after key event
        if D.activeWin.onDraw then
            local w=D.activeWin
            local x,y,ww,hh=w.cx,w.cy,w.cw,w.ch
            local by=R.h-D.taskbarH
            if y+hh>by then hh=math.max(20,by-y) end
            R.fillRect(x+2,y+17,ww-4,hh-19,K.GRAY)
            pcall(w.onDraw,w,x+3,y+18,ww-6,hh-21)
        end
    end
end

function D.run()
    R.init()
    local running=true local timer=os.startTimer(1)
    D.drawAll()
    while running do
        local e,a,b,c,d=os.pullEvent()
        if e=="mouse_click" then
            D.mouse.x=b D.mouse.y=c
            local act=D.handleMouseClick(b,c,d)
            if act=="reboot" then R.clear() R.drawText(10,10,"Rebooting...",K.WHITE) sleep(0.5) os.reboot()
            elseif act=="shutdown" then running=false
            elseif act=="files" then D.appFM()
            elseif act=="edit" then D.appEdit()
            elseif act=="settings" then D.appSettings()
            elseif act=="shell" then D.appShell() end
            if D.needRedraw then D.drawAll() end
        elseif e=="mouse_drag" then D.mouse.x=b D.mouse.y=c D.drag(b,c)
        elseif e=="mouse_up" then D.drop() if D.needRedraw then D.drawAll() end
        elseif e=="key" then
            if a==keys.q and D.startMenuOpen then D.startMenuOpen=false D.redraw()
            else D.key(a,nil) end
        elseif e=="char" then D.key(nil,a)
        elseif e=="timer" then
            local t=os.time and os.time() or 0
            local h=math.floor(t) local m=math.floor((t-h)*60)
            local nc=string.format("%02d:%02d",h,m)
            if nc~=D.clock then
                D.clock=nc
                local by=R.h-D.taskbarH
                R.fillRect(R.w-48,by+3,44,14,K.GRAY)
                R.drawW95Sunken(R.w-48,by+3,44,14)
                R.drawText(R.w-44,by+6,nc,K.BLACK)
            end
            timer=os.startTimer(1)
        end
    end
    R.clear() R.fillRect(0,0,R.w,R.h,K.BLACK) R.drawText(10,10,"CCOS shutdown.",K.WHITE)
end

function D.appFM()
    local path="/" local sel=1 local scroll=0 local items={}
    local function ref()
        local l=fs.list(path) table.sort(l) items={}
        if path~="/" then items[#items+1]=".." end
        for _,it in ipairs(l) do
            local fp=path=="/" and ("/"..it) or (path.."/"..it)
            if fs.isDir(fp) then items[#items+1]="/"..it else items[#items+1]=it end
        end
        if #items==0 then items={"(empty)"} end
        sel=math.max(1,math.min(sel,#items))
    end
    ref()
    local w=D.createWindow("File Manager",20,15,240,150)
    -- Button row
    local btnY=17
    w.onDraw=function(w,cx,cy,cw,ch)
        -- Buttons
        R.drawButton(cx,cy,36,14,false) R.drawText(cx+2,cy+3,"New",K.BLACK)
        R.drawButton(cx+38,cy,50,14,false) R.drawText(cx+40,cy+3,"NewDir",K.BLACK)
        R.drawButton(cx+90,cy,36,14,false) R.drawText(cx+92,cy+3,"Del",K.BLACK)
        -- File list
        local lh=math.floor((ch-20)/8)
        for i=1,lh do
            local idx=scroll+i local it=items[idx]
            if not it then break end
            local iy=cy+16+(i-1)*8
            local hover=D.mouse.x>=cx+2 and D.mouse.x<cx+cw-2 and D.mouse.y>=iy-1 and D.mouse.y<iy+8
            if idx==sel or hover then R.fillRect(cx+2,iy-1,cw-4,9,K.DBLUE) R.drawText(cx+4,iy,it,K.WHITE)
            else R.drawText(cx+4,iy,it,K.BLACK) end
        end
        R.drawText(cx+2,cy+ch-10," "..path,K.BLACK)
    end
    w.onClick=function(w,mx,my)
        local cx,cy=w.cx,w.cy
        -- Button clicks
        if my>=cy and my<cy+14 then
            if mx>=cx and mx<cx+36 then -- New file
                local name="newfile.txt"
                local fp=path=="/" and ("/"..name) or (path.."/"..name)
                local f=fs.open(fp,"w") if f then f.close() end ref() D.redraw()
            elseif mx>=cx+38 and mx<cx+88 then -- New dir
                local name="newdir"
                local fp=path=="/" and ("/"..name) or (path.."/"..name)
                fs.makeDir(fp) ref() D.redraw()
            elseif mx>=cx+90 and mx<cx+126 then -- Delete
                local it=items[sel] if it and it~=".." then
                    local fp=path=="/" and ("/"..it) or (path.."/"..it)
                    if fs.exists(fp) then fs.delete(fp) end ref() D.redraw()
                end
            end
            return
        end
        -- File list click (select)
        local lh=math.floor((w.ch-20)/8)
        for i=1,lh do
            local idx=scroll+i local iy=cy+16+(i-1)*8
            if my>=iy-1 and my<iy+8 then sel=idx return end
        end
    end
    w.onDoubleClick=function(w,mx,my)
        -- Double click to open
        local cx,cy=w.cx,w.cy
        local lh=math.floor((w.ch-20)/8)
        for i=1,lh do
            local idx=scroll+i local iy=cy+16+(i-1)*8
            if my>=iy-1 and my<iy+8 then
                local it=items[idx]
                if it then
                    if it==".." then path=gd(path) sel=1 scroll=0 ref() D.redraw()
                    elseif it:sub(1,1)=="/" then
                        local np=path=="/" and it or (path..it)
                        if fs.isDir(np) then path=np sel=1 scroll=0 ref() D.redraw() end
                    else
                        D.appEdit(path=="/" and ("/"..it) or (path.."/"..it))
                    end
                end
                return
            end
        end
    end
    w.onKey=function(w,k,ch)
        if k==keys.up and sel>1 then sel=sel-1 if sel<=scroll then scroll=scroll-1 end
        elseif k==keys.down and sel<#items then sel=sel+1 local lh=math.floor((w.ch-20)/8) if sel>scroll+lh then scroll=scroll+1 end
        elseif k==keys.enter then
            local it=items[sel]
            if it then
                if it==".." then path=gd(path) sel=1 scroll=0 ref() D.redraw()
                elseif it:sub(1,1)=="/" then local np=path=="/" and it or (path..it) if fs.isDir(np) then path=np sel=1 scroll=0 ref() D.redraw() end
                else D.appEdit(path=="/" and ("/"..it) or (path.."/"..it)) end
            end
        elseif k==keys.backspace then path=gd(path) sel=1 scroll=0 ref() D.redraw()
        elseif k==keys.f5 then ref() D.redraw()
        elseif k==keys.escape or k==keys.q then D.destroyWindow(w) end
    end
end

function D.appEdit(fp)
    fp=fp or "/untitled.txt"
    local lines={} local content=rf(fp)
    if content then for l in content:gmatch("[^\n]*") do lines[#lines+1]=l end end
    if #lines==0 then lines[1]="" end
    local cL,cC,sY=1,1,0 local mod=false
    local w=D.createWindow("Edit: "..gfn(fp),30,18,250,140)
    w.onDraw=function(w,cx,cy,cw,ch)
        -- Button row
        R.drawButton(cx,cy,32,14,false) R.drawText(cx+2,cy+3,"Save",K.BLACK)
        R.drawButton(cx+34,cy,32,14,false) R.drawText(cx+36,cy+3,"Open",K.BLACK)
        R.drawButton(cx+68,cy,32,14,false) R.drawText(cx+70,cy+3,"New",K.BLACK)
        R.drawButton(cx+102,cy,36,14,false) R.drawText(cx+104,cy+3,"Close",K.BLACK)
        -- Text area
        local eh=math.floor((ch-22)/8)
        for i=1,eh do R.drawText(cx+2,cy+16+(i-1)*8,lines[sY+i] or "",K.BLACK) end
        if cL>sY and cL<=sY+eh then
            local cy2=cy+16+(cL-sY-1)*8 local cx2=cx+(cC-1)*6
            if cx2>=cx and cx2<cx+cw then
                R.fillRect(cx2,cy2,6,8,K.DBLUE)
                local c2=(lines[cL] or ""):sub(cC,cC)
                R.drawText(cx2,cy2,c2=="" and " " or c2,K.WHITE)
            end
        end
        R.drawText(cx+2,cy+ch-10,gfn(fp)..(mod and " *" or ""),K.BLACK)
    end
    w.onClick=function(w,mx,my)
        if my>=w.cy+1 and my<w.cy+15 then
            if mx>=w.cx and mx<w.cx+32 then -- Save
                local f=fs.open(fp,"w") if f then f.write(table.concat(lines,"\n")) f.close() mod=false end D.redraw()
            elseif mx>=w.cx+34 and mx<w.cx+66 then -- Open
                D.appEdit(nil) -- Will prompt for path
            elseif mx>=w.cx+68 and mx<w.cx+100 then -- New
                lines={""} cL,cC,sY=1,1,0 mod=false fp="/untitled.txt"
                D.activeWin.title="Edit: untitled.txt" D.redraw()
            elseif mx>=w.cx+102 and mx<w.cx+138 then -- Close
                if mod then local f=fs.open(fp,"w") if f then f.write(table.concat(lines,"\n")) f.close() end end
                D.destroyWindow(w)
            end
        end
    end
    w.onKey=function(w,k,ch)
        if ch then
            local l=lines[cL] or "" lines[cL]=l:sub(1,cC-1)..ch..l:sub(cC) cC=cC+1 mod=true
        elseif k==keys.backspace then
            if cC>1 then
                local l=lines[cL] or "" lines[cL]=l:sub(1,cC-2)..l:sub(cC) cC=cC-1 mod=true
            elseif cL>1 then
                local pl=#lines[cL-1] lines[cL-1]=lines[cL-1]..(lines[cL] or "")
                table.remove(lines,cL) cL=cL-1 cC=pl+1 mod=true
            end
        elseif k==keys.enter then
            local l=lines[cL] or "" lines[cL]=l:sub(1,cC-1)
            table.insert(lines,cL,l:sub(cC)) cL=cL+1 cC=1 mod=true
        elseif k==keys.up then
            if cL>1 then cL=cL-1 cC=math.min(cC,#(lines[cL] or "")+1) if cL<=sY then sY=sY-1 end end
        elseif k==keys.down then
            if cL<#lines then cL=cL+1 cC=math.min(cC,#(lines[cL] or "")+1)
                local eh=math.floor((w.ch-16)/8) if cL>sY+eh then sY=sY+1 end
            end
        elseif k==keys.left then if cC>1 then cC=cC-1 elseif cL>1 then cL=cL-1 cC=#(lines[cL] or "")+1 end
        elseif k==keys.right then if cC<=#(lines[cL] or "") then cC=cC+1 elseif cL<#lines then cL=cL+1 cC=1 end
        elseif k==keys.home then cC=1
        elseif k==keys["end"] then cC=#(lines[cL] or "")+1
        elseif k==keys.tab then
            local l=lines[cL] or "" lines[cL]=l:sub(1,cC-1).."  "..l:sub(cC) cC=cC+2 mod=true
        elseif k==keys.escape or k==keys.q then
            if mod then local f=fs.open(fp,"w") if f then f.write(table.concat(lines,"\n")) f.close() end end
            D.destroyWindow(w)
        end
    end
end

function D.appSettings()
    local lt=os.getComputerLabel and os.getComputerLabel() or "No Label"
    local w=D.createWindow("Settings",50,30,180,100)
    w.onDraw=function(w,cx,cy,cw,ch)
        R.drawText(cx+4,cy+4,"Label:",K.BLACK)
        R.drawW95Sunken(cx+4,cy+16,cw-8,12)
        R.drawText(cx+6,cy+18,lt,K.BLACK)
        R.drawText(cx+4,cy+36,"Size: "..R.w.."x"..R.h,K.BLACK)
    end
    w.onKey=function(w,k) if k==keys.escape or k==keys.q then D.destroyWindow(w) end end
end

function D.appShell()
    local out={"> "} local inp="" local sY=0
    local w=D.createWindow("Shell",30,25,250,130)
    w.onDraw=function(w,cx,cy,cw,ch)
        local ml=math.floor((ch-16)/8)
        for i=1,ml do R.drawText(cx+2,cy+(i-1)*8,out[sY+i] or "",K.BLACK) end
        R.fillRect(cx,cy+ch-12,cw,10,K.GRAY)
        R.drawText(cx+2,cy+ch-10,"> "..inp,K.BLACK)
    end
    w.onKey=function(w,k,ch)
        if ch then inp=inp..ch
        elseif k==keys.backspace then inp=inp:sub(1,-2)
        elseif k==keys.enter then
            out[#out+1]="> "..inp local cmd=inp inp=""
            if cmd=="exit" then D.destroyWindow(w) return end
            local fn,err=load("return "..cmd,"shell","t",_G)
            if not fn then fn,err=load(cmd,"shell","t",_G) end
            if fn then local ok,r=pcall(fn) if ok then if r~=nil then out[#out+1]=tostring(r) end else out[#out+1]="Err: "..tostring(r) end
            else out[#out+1]="Err: "..tostring(err) end
            local ml=math.floor((w.ch-16)/8) if #out>ml then sY=#out-ml end
        elseif k==keys.up then if sY>0 then sY=sY-1 end
        elseif k==keys.down then local ml=math.floor((w.ch-16)/8) if sY<#out-ml then sY=sY+1 end
        elseif k==keys.q then D.destroyWindow(w) end
    end
end

return D
