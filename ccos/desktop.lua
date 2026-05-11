--[[
    CCOS Desktop — Window Manager & Event Loop
]]

local R = _G.ccos_render
local D = {}
_G._desktop = D

-- Color constants
local C = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,CYAN=7,LBLUE=8,
    GREEN=9,DGREEN=10,RED=11,DRED=12,YELLOW=13,ORANGE=14,BROWN=15,PURPLE=16,PINK=17,
    DTITLE=18,TBLUE=19,TINACT=20,PBLUE=21,AWHITE=22,NBLACK=23,MGRAY=24,
    BFACE=25,BHI=26,DNAVY=27,BTDARK=28,DGBG=29,DESKTOP=30}

D.windows={}
D.activeWin=nil
D.taskbarH=20
D.startMenuOpen=false
D.clock=""
D.nextWinId=1
D.dirty=true
D.dragWin=nil
D.dragOX=0
D.dragOY=0
D.lastDragRect=nil
D.mouse={x=0,y=0}

local function getDir(p) if not p or p=="/" then return "/" end local t={} for s in p:gmatch("[^/]+") do t[#t+1]=s end if #t<=1 then return "/" end t[#t]=nil return "/"..table.concat(t,"/") end
local function getFN(p) if not p or p=="/" then return "" end local l=nil for s in p:gmatch("[^/]+") do l=s end return l or "" end
local function readF(p) if not fs.exists(p) then return nil end local f=fs.open(p,"r") if not f then return nil end local c=f.readAll() f.close() return c end

function D.createWindow(title,cx,cy,cw,ch)
    local id=D.nextWinId D.nextWinId=D.nextWinId+1
    local w={id=id,title=title or "Window",cx=cx or 30,cy=cy or 20,cw=cw or 200,ch=ch or 120,
        minW=80,minH=50,visible=true,maximized=false,minimized=false,prevState=nil,resizing=false,
        onDraw=nil,onKey=nil,onClick=nil,onClose=nil}
    D.windows[#D.windows+1]=w D.activeWin=w D.dirty=true return w
end

function D.destroyWindow(w)
    for i,v in ipairs(D.windows) do if v.id==w.id then table.remove(D.windows,i) break end end
    if D.activeWin and D.activeWin.id==w.id then D.activeWin=D.windows[#D.windows] end
    if w.onClose then pcall(w.onClose) end D.dirty=true
end

function D.bringToFront(w)
    for i,v in ipairs(D.windows) do if v.id==w.id then table.remove(D.windows,i) D.windows[#D.windows+1]=w D.activeWin=w D.dirty=true return end end
end

function D.getWindowAt(mx,my)
    for i=#D.windows,1,-1 do local w=D.windows[i] if w.visible and not w.minimized and mx>=w.cx and mx<w.cx+w.cw and my>=w.cy and my<w.cy+w.ch then return w end end
    return nil
end

-- ============================================================
-- DRAW DESKTOP
-- ============================================================
function D.drawDesktop()
    R.clear() local by=R.h-D.taskbarH
    R.fillRect(0,0,R.w,by,C.DESKTOP)
    -- Icons
    local icons={{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw,ih=48,42 local cols=math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,ic in ipairs(icons) do local col=(i-1)%cols local row=math.floor((i-1)/cols) local ix=8+col*(iw+10) local iy=8+row*(ih+8) if iy+ih>by-4 then break end
        if D.mouse.x>=ix-2 and D.mouse.x<ix+iw+2 and D.mouse.y>=iy-2 and D.mouse.y<iy+ih+2 then R.fillRect(ix-2,iy-2,iw+4,ih+4,C.DBLUE) end
        R.fillRect(ix,iy,iw,24,C.LGRAY) R.drawW95Sunken(ix,iy,iw,24) R.drawText(ix+16,iy+7,ic[1]:sub(1,1),C.DBLUE) R.drawText(ix,iy+28,ic[1],C.WHITE) end
    -- Windows
    for _,w in ipairs(D.windows) do if w.visible and not w.minimized then D.drawWindow(w) end end
    -- Taskbar
    R.fillRect(0,by,R.w,D.taskbarH,C.GRAY) R.drawLine(0,by,R.w-1,by,C.WHITE)
    R.drawButton(2,by+2,54,16,D.startMenuOpen) R.drawText(6,by+6,"Start",C.BLACK)
    local bx=60
    for _,w in ipairs(D.windows) do local bw=math.min(100,R.w-bx-55) if bw<25 then break end
        local ia=(D.activeWin and D.activeWin.id==w.id) R.drawButton(bx,by+3,bw,14,ia)
        local tt=#w.title>12 and w.title:sub(1,10)..".." or w.title if w.minimized then tt="("..tt..")" end
        R.drawText(bx+4,by+6,tt,ia and C.WHITE or C.BLACK) bx=bx+bw+2 end
    R.drawW95Sunken(R.w-48,by+3,44,14) R.drawText(R.w-44,by+6,D.clock,C.BLACK)
    -- Start menu
    if D.startMenuOpen then local my=by-100 if my<1 then my=1 end
        R.fillRect(2,my,140,96,C.GRAY) R.drawW95Raised(2,my,140,96) R.fillRect(4,my+2,20,92,C.DBLUE) R.drawText(5,my+30,"CC",C.WHITE)
        local items={{"File Manager","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"},{"Reboot","reboot"},{"Shutdown","shutdown"}}
        local iy=my+4 for _,it in ipairs(items) do local h=D.mouse.x>=26 and D.mouse.x<138 and D.mouse.y>=iy and D.mouse.y<iy+12
            if h then R.fillRect(26,iy,112,12,C.DBLUE) end R.drawText(28,iy+2,it[1],h and C.WHITE or C.BLACK) iy=iy+14 end end
    D.dirty=false D.lastDragRect=nil
end

-- ============================================================
-- DRAW WINDOW
-- ============================================================
function D.drawWindow(w)
    local x,y,ww,hh=w.cx,w.cy,w.cw,w.ch local by=R.h-D.taskbarH
    if y+hh>by then hh=math.max(20,by-y) end
    R.fillRect(x,y,ww,hh,C.GRAY)
    local act=(D.activeWin and D.activeWin.id==w.id)
    R.drawTitleBar(x,y,ww,act) R.drawText(x+4,y+4,w.title,act and C.WHITE or C.LGRAY)
    -- Title buttons: close, max, min
    R.drawButton(x+ww-18,y+1,16,14,false) R.drawText(x+ww-13,y+4,"X",C.BLACK)
    R.drawButton(x+ww-36,y+1,16,14,false) R.drawRect(x+ww-32,y+4,8,8,C.BLACK)
    R.drawButton(x+ww-54,y+1,16,14,false) R.fillRect(x+ww-49,y+6,6,2,C.BLACK)
    R.drawW95Raised(x,y,ww,hh)
    -- App buttons row (if any)
    if w.appButtons then local abx=x+2 for i,btn in ipairs(w.appButtons) do
            local bw=#btn.label+4 R.drawButton(abx,y+17,bw,14,false) R.drawText(abx+2,y+20,btn.label,C.BLACK) abx=abx+bw+2 end
        R.fillRect(x+2,y+33,ww-4,hh-35,C.GRAY)
        if w.onDraw then pcall(w.onDraw,w,x+3,y+34,ww-6,hh-36) end
    else
        R.fillRect(x+2,y+17,ww-4,hh-19,C.GRAY)
        if w.onDraw then pcall(w.onDraw,w,x+3,y+18,ww-6,hh-21) end
    end
end

-- ============================================================
-- MOUSE
-- ============================================================
function D.handleClick(mx,my,btn)
    local by=R.h-D.taskbarH
    -- Start menu
    if D.startMenuOpen then local my2=by-100 if my2<1 then my2=1 end local items={"files","edit","settings","shell","reboot","shutdown"} local iy=my2+4
        for _,a in ipairs(items) do if mx>=26 and mx<138 and my>=iy and my<iy+12 then D.startMenuOpen=false return a end iy=iy+14 end
        D.startMenuOpen=false return nil end
    -- Start button
    if mx>=2 and mx<56 and my>=by+2 and my<by+18 then D.startMenuOpen=true return nil end
    -- Taskbar buttons
    if my>=by then local bx=60 for _,w in ipairs(D.windows) do local bw=math.min(100,R.w-bx-55) if bw<25 then break end
            if mx>=bx and mx<bx+bw and my>=by+3 and my<by+17 then
                if w.minimized then w.minimized=false w.visible=true D.bringToFront(w) D.dirty=true
                elseif D.activeWin and D.activeWin.id==w.id then w.minimized=true D.dirty=true
                else D.bringToFront(w) D.dirty=true end return nil end bx=bx+bw+2 end return nil end
    -- Desktop icons
    local icons={{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw,ih=48,42 local cols=math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,ic in ipairs(icons) do local col=(i-1)%cols local row=math.floor((i-1)/cols) local ix=8+col*(iw+10) local iy=8+row*(ih+8)
        if mx>=ix-2 and mx<ix+iw+2 and my>=iy-2 and my<iy+ih+2 then return ic[2] end end
    -- Windows
    local w=D.getWindowAt(mx,my)
    if w then
        D.bringToFront(w)
        -- Title bar buttons
        if my>=w.cy and my<w.cy+16 then
            if mx>=w.cx+w.cw-18 then D.destroyWindow(w) return nil end
            if mx>=w.cx+w.cw-36 and mx<w.cx+w.cw-20 then
                if w.maximized then if w.prevState then w.cx=w.prevState.x;w.cy=w.prevState.y;w.cw=w.prevState.w;w.ch=w.prevState.h;w.prevState=nil end w.maximized=false
                else w.prevState={x=w.cx,y=w.cy,w=w.cw,h=w.ch} w.cx=1;w.cy=1;w.cw=R.w;w.ch=R.h-D.taskbarH-1;w.maximized=true end
                D.dirty=true return nil end
            if mx>=w.cx+w.cw-54 and mx<w.cx+w.cw-38 then w.minimized=true D.dirty=true return nil end
            -- Drag
            if not w.maximized then D.dragWin=w D.dragOX=mx-w.cx D.dragOY=my-w.cy end
            return nil
        end
        -- App buttons row
        if w.appButtons and my>=w.cy+17 and my<w.cy+31 then local abx=w.cx+2 for i,button in ipairs(w.appButtons) do local bw=#button.label+4
                if mx>=abx and mx<abx+bw then if button.onClick then pcall(button.onClick) end return nil end abx=abx+bw+2 end
        end
        -- Resize
        if mx>=w.cx+w.cw-8 and my>=w.cy+w.ch-8 and not w.maximized then w.resizing=true return nil end
        -- Client
        if w.onClick then pcall(w.onClick,w,mx-w.cx-3,my-w.cy-18) end
        return nil
    end
    return nil
end

function D.handleDrag(mx,my)
    local w=D.dragWin if not w then return end
    local nx=mx-D.dragOX local ny=my-D.dragOY if ny<1 then ny=1 end local by=R.h-D.taskbarH if ny+w.ch>by+1 then ny=by-w.ch+2 end
    -- Clear old outline
    if D.lastDragRect then local r=D.lastDragRect R.fillRect(r.x,r.y,r.w,r.h,C.DESKTOP) for _,v in ipairs(D.windows) do
            if v.id~=w.id and v.visible and not v.minimized and not (v.cx+v.cw<r.x or v.cx>r.x+r.w or v.cy+v.ch<r.y or v.cy>r.y+r.h) then D.drawWindow(v) end end end
    -- Draw new outline
    R.drawDragOutline(nx,ny,w.cw,w.ch) D.lastDragRect={x=nx,y=ny,w=w.cw,h=w.ch}
end

function D.handleMouseUp()
    if D.dragWin then local w=D.dragWin w.cx=D.mouse.x-D.dragOX w.cy=D.mouse.y-D.dragOY if w.cy<1 then w.cy=1 end local by=R.h-D.taskbarH if w.cy+w.ch>by+1 then w.cy=by-w.ch+2 end D.dragWin=nil D.lastDragRect=nil D.dirty=true end
    for _,w in ipairs(D.windows) do w.resizing=false end
end

function D.handleKey(key,char)
    if D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey,D.activeWin,key,char) end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
function D.run()
    R.init() local running=true local timer=os.startTimer(1) D.drawDesktop()
    while running do
        local event,p1,p2,p3,p4=os.pullEvent()
        if event=="mouse_click" then D.mouse.x=p2 D.mouse.y=p3 local a=D.handleClick(p2,p3,p1)
            if a=="reboot" then R.clear() R.drawText(10,10,"Rebooting...",C.WHITE) sleep(0.5) os.reboot()
            elseif a=="shutdown" then running=false
            elseif a=="files" then D.app_fm()
            elseif a=="edit" then D.app_editor()
            elseif a=="settings" then D.app_settings()
            elseif a=="shell" then D.app_shell() end
            if D.dirty then D.drawDesktop() end
        elseif event=="mouse_drag" then D.mouse.x=p2 D.mouse.y=p3 D.handleDrag(p2,p3)
        elseif event=="mouse_up" then D.handleMouseUp() if D.dirty then D.drawDesktop() end
        elseif event=="key" then if p1==keys.q and D.startMenuOpen then D.startMenuOpen=false D.dirty=true else D.handleKey(p1,nil) end
        elseif event=="char" then D.handleKey(nil,p1)
        elseif event=="timer" then local t=os.time and os.time() or 0 local h=math.floor(t) local m=math.floor((t-h)*60) local nc=string.format("%02d:%02d",h,m)
            if nc~=D.clock then D.clock=nc local by=R.h-D.taskbarH R.fillRect(R.w-48,by+3,44,14,C.GRAY) R.drawW95Sunken(R.w-48,by+3,44,14) R.drawText(R.w-44,by+6,nc,C.BLACK) end
            timer=os.startTimer(1) end
    end
    R.clear() R.fillRect(0,0,R.w,R.h,C.BLACK) R.drawText(10,10,"CCOS shutdown.",C.WHITE)
end

-- ============================================================
-- APPS
-- ============================================================

function D.app_fm()
    local path="/" local sel=1 local scroll=0 local items={}
    local function refresh() local list=fs.list(path) table.sort(list) items={} if path~="/" then items[#items+1]=".." end
        for _,it in ipairs(list) do local fp=path=="/" and ("/"..it) or (path.."/"..it) items[#items+1]=fs.isDir(fp) and ("/"..it) or it end
        if #items==0 then items={"(empty)"} end sel=math.max(1,math.min(sel,#items)) end refresh()
    local w=D.createWindow("File Manager",30,25,220,130)
    w.appButtons={{label="Open",onClick=function() local it=items[sel] if not it then return end
        if it==".." then path=getDir(path) sel=1 scroll=0 refresh()
        elseif it:sub(1,1)=="/" then local np=path=="/" and it or (path..it) if fs.isDir(np) then path=np sel=1 scroll=0 refresh() end
        else local fp=path=="/" and ("/"..it) or (path.."/"..it) D.app_editor(fp) end end},
        {label="Back",onClick=function() path=getDir(path) sel=1 scroll=0 refresh() end},
        {label="Close",onClick=function() D.destroyWindow(w) end}}
    w.onDraw=function(w,cx,cy,cw,ch) local lh=math.floor((ch-20)/8) for i=1,lh do local idx=scroll+i local it=items[idx] if not it then break end
            local iy=cy+(i-1)*8 local hover=D.mouse.x>=cx and D.mouse.x<cx+cw and D.mouse.y>=iy-1 and D.mouse.y<iy+8
            if idx==sel or hover then R.fillRect(cx,iy-1,cw,9,C.DBLUE) R.drawText(cx+2,iy,it,C.WHITE) else R.drawText(cx+2,iy,it,C.BLACK) end
        end R.fillRect(cx,cy+ch-12,cw,10,C.GRAY) R.drawText(cx+2,cy+ch-10," "..path,C.BLACK) end
    w.onKey=function(w,key,char)
        if key==keys.up and sel>1 then sel=sel-1 if sel<=scroll then scroll=scroll-1 end
        elseif key==keys.down and sel<#items then sel=sel+1 local lh=math.floor((w.ch-20)/8) if sel>scroll+lh then scroll=scroll+1 end
        elseif key==keys.enter then local it=items[sel] if not it then return end
            if it==".." then path=getDir(path) sel=1 scroll=0 refresh()
            elseif it:sub(1,1)=="/" then local np=path=="/" and it or (path..it) if fs.isDir(np) then path=np sel=1 scroll=0 refresh() end
            else local fp=path=="/" and ("/"..it) or (path.."/"..it) D.app_editor(fp) end
        elseif key==keys.backspace then path=getDir(path) sel=1 scroll=0 refresh()
        elseif key==keys.f5 then refresh()
        elseif key==keys.escape or key==keys.q then D.destroyWindow(w) end
    end
    w.onClick=function(w,mx,my) local lh=math.floor((w.ch-20)/8) for i=1,lh do local idx=scroll+i local iy=34+(i-1)*8 if my>=iy-1 and my<iy+8 then sel=idx local it=items[idx] if not it then return end
            if it==".." then path=getDir(path) sel=1 scroll=0 refresh()
            elseif it:sub(1,1)=="/" then local np=path=="/" and it or (path..it) if fs.isDir(np) then path=np sel=1 scroll=0 refresh() end
            else local fp=path=="/" and ("/"..it) or (path.."/"..it) D.app_editor(fp) end return end end end
end

function D.app_editor(filePath)
    filePath=filePath or "/untitled.txt" local lines={} local content=readF(filePath)
    if content then for line in content:gmatch("[^\n]*") do lines[#lines+1]=line end end if #lines==0 then lines[1]="" end
    local cL,cC,sY=1,1,0 local modified=false
    local w=D.createWindow("Edit: "..getFN(filePath),40,20,250,140)
    w.appButtons={{label="Save",onClick=function() local f=fs.open(filePath,"w") if f then f.write(table.concat(lines,"\n")) f.close() modified=false end end},
        {label="Close",onClick=function() if modified then local f=fs.open(filePath,"w") if f then f.write(table.concat(lines,"\n")) f.close() end end D.destroyWindow(w) end}}
    w.onDraw=function(w,cx,cy,cw,ch)
        local eh=math.floor((ch-16)/8) for i=1,eh do local li=sY+i R.drawText(cx+2,cy+(i-1)*8,lines[li] or "",C.BLACK) end
        if cL>sY and cL<=sY+eh then local cy2=cy+(cL-sY-1)*8 local cx2=cx+(cC-1)*6 if cx2>=cx and cx2<cx+cw then R.fillRect(cx2,cy2,6,8,C.DBLUE) local c=(lines[cL] or ""):sub(cC,cC) R.drawText(cx2,cy2,c=="" and " " or c,C.WHITE) end end
        R.fillRect(cx,cy+ch-12,cw,10,C.GRAY) local ms=modified and " [mod]" or "" R.drawText(cx+2,cy+ch-10,"Ln "..cL..ms,C.BLACK) end
    w.onKey=function(w,key,char)
        if char then local l=lines[cL] or "" lines[cL]=l:sub(1,cC-1)..char..l:sub(cC) cC=cC+1 modified=true
        elseif key==keys.backspace then if cC>1 then local l=lines[cL] or "" lines[cL]=l:sub(1,cC-2)..l:sub(cC) cC=cC-1 modified=true elseif cL>1 then local pl=#lines[cL-1] lines[cL-1]=lines[cL-1]..(lines[cL] or "") table.remove(lines,cL) cL=cL-1 cC=pl+1 modified=true end
        elseif key==keys.enter then local l=lines[cL] or "" lines[cL]=l:sub(1,cC-1) table.insert(lines,cL,l:sub(cC)) cL=cL+1 cC=1 modified=true
        elseif key==keys.up then if cL>1 then cL=cL-1 cC=math.min(cC,#(lines[cL] or "")+1) if cL<=sY then sY=sY-1 end end
        elseif key==keys.down then if cL<#lines then cL=cL+1 cC=math.min(cC,#(lines[cL] or "")+1) local eh=math.floor((w.ch-16)/8) if cL>sY+eh then sY=sY+1 end end
        elseif key==keys.left then if cC>1 then cC=cC-1 elseif cL>1 then cL=cL-1 cC=#(lines[cL] or "")+1 end
        elseif key==keys.right then if cC<=#(lines[cL] or "") then cC=cC+1 elseif cL<#lines then cL=cL+1 cC=1 end
        elseif key==keys.home then cC=1 elseif key==keys["end"] then cC=#(lines[cL] or "")+1
        elseif key==keys.tab then local l=lines[cL] or "" lines[cL]=l:sub(1,cC-1).."  "..l:sub(cC) cC=cC+2 modified=true
        elseif key==keys.escape or key==keys.q then if modified then local f=fs.open(filePath,"w") if f then f.write(table.concat(lines,"\n")) f.close() end end D.destroyWindow(w) end
    end
end

function D.app_settings()
    local lt=os.getComputerLabel and os.getComputerLabel() or "No Label"
    local w=D.createWindow("Settings",50,30,180,100)
    w.appButtons={{label="Close",onClick=function() D.destroyWindow(w) end}}
    w.onDraw=function(w,cx,cy,cw,ch)
        R.drawText(cx+4,cy+4,"Computer Label:",C.BLACK) R.drawW95Sunken(cx+4,cy+16,cw-8,12) R.drawText(cx+6,cy+18,lt,C.BLACK)
        R.drawText(cx+4,cy+36,"Display: "..R.w.."x"..R.h,C.BLACK)
        R.drawText(cx+4,cy+48,"Color: "..(R.isColor and "Yes" or "No"),C.BLACK)
        R.drawText(cx+4,cy+60,"Graphics: "..(R.hasGraphics and "Yes" or "No"),C.BLACK) end
    w.onKey=function(w,key) if key==keys.escape or key==keys.q then D.destroyWindow(w) end end
end

function D.app_shell()
    local output={"> "} local inputLine="" local scrollY=0
    local w=D.createWindow("Shell",30,25,250,130)
    w.appButtons={{label="Run",onClick=function() local cmd=inputLine inputLine="" output[#output+1]="> "..cmd
            if cmd=="exit" then D.destroyWindow(w) return end
            local fn,err=load("return "..cmd,"shell","t",_G) if not fn then fn,err=load(cmd,"shell","t",_G) end
            if fn then local ok,res=pcall(fn) if ok then if res~=nil then output[#output+1]=tostring(res) end else output[#output+1]="Error: "..tostring(res) end
            else output[#output+1]="Error: "..tostring(err) end
            local ml=math.floor((w.ch-16)/8) if #output>ml then scrollY=#output-ml end end},
        {label="Close",onClick=function() D.destroyWindow(w) end}}
    w.onDraw=function(w,cx,cy,cw,ch) local ml=math.floor((ch-16)/8) for i=1,ml do R.drawText(cx+2,cy+(i-1)*8,output[scrollY+i] or "",C.BLACK) end
        R.fillRect(cx,cy+ch-12,cw,10,C.GRAY) R.drawText(cx+2,cy+ch-10,"> "..inputLine,C.BLACK) end
    w.onKey=function(w,key,char)
        if char then inputLine=inputLine..char
        elseif key==keys.backspace then inputLine=inputLine:sub(1,-2)
        elseif key==keys.up then if scrollY>0 then scrollY=scrollY-1 end
        elseif key==keys.down then local ml=math.floor((w.ch-16)/8) if scrollY<#output-ml then scrollY=scrollY+1 end
        elseif key==keys.q then D.destroyWindow(w) end
    end
end

return D
