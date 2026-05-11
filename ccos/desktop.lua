--[[
    CCOS Desktop — Window Manager & Event Loop
    ============================================
    Pure logic: window management, mouse handling, event routing.
    Rendering uses ccos_render (R), API uses ccos_api (A).
]]

local R = _G.ccos_render
local A = _G.ccos_api
local desktop = {}

desktop.R = R
desktop.windows = {}
desktop.activeWin = nil
desktop.taskbarH = 20
desktop.startMenuOpen = false
desktop.clock = ""
desktop.nextWinId = 1
desktop.dirty = true
desktop.dragWin = nil
desktop.dragOX = 0
desktop.dragOY = 0
desktop.lastDragRect = nil
desktop.mouse = {x=0, y=0}

-- FS helpers
local function getDir(path)
    if not path or path == "/" then return "/" end
    local parts = {}
    for p in path:gmatch("[^/]+") do table.insert(parts, p) end
    if #parts <= 1 then return "/" end
    table.remove(parts)
    return "/" .. table.concat(parts, "/")
end

local function getFileName(path)
    if not path or path == "/" then return "" end
    for p in path:gmatch("[^/]+") do end
    return p or ""
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local c = f.readAll(); f.close(); return c
end
desktop.activeWin = nil
desktop.taskbarH = 20
desktop.startMenuOpen = false
desktop.clock = ""
desktop.nextWinId = 1
desktop.dirty = true
desktop.dragWin = nil  -- window being dragged
desktop.dragOX = 0     -- offset from window origin
desktop.dragOY = 0
desktop.lastDragRect = nil  -- last drag outline position for cleanup
desktop.mouse = {x=0, y=0}

-- Make desktop accessible from api.lua
_G._desktop = desktop

-- ============================================================
-- WINDOW MANAGEMENT
-- ============================================================
function desktop.createWindow(title, cx, cy, cw, ch)
    local id = desktop.nextWinId; desktop.nextWinId = desktop.nextWinId + 1
    local win = {
        id=id, title=title or "Window",
        cx=cx or 30, cy=cy or 20, cw=cw or 200, ch=ch or 120,
        minW=80, minH=50,
        visible=true, maximized=false, minimized=false, prevState=nil,
        resizing=false,
        onDraw=nil, onKey=nil, onClick=nil,
    }
    table.insert(desktop.windows, win)
    desktop.activeWin = win
    desktop.dirty = true
    return win
end

function desktop.destroyWindow(win)
    for i,w in ipairs(desktop.windows) do
        if w.id==win.id then table.remove(desktop.windows,i); break end
    end
    if desktop.activeWin and desktop.activeWin.id==win.id then
        desktop.activeWin = desktop.windows[#desktop.windows]
    end
    desktop.dirty = true
end

function desktop.bringToFront(win)
    for i,w in ipairs(desktop.windows) do
        if w.id==win.id then
            table.remove(desktop.windows,i)
            table.insert(desktop.windows,win)
            desktop.activeWin=win; desktop.dirty=true; return
        end
    end
end

function desktop.getWindowAt(mx,my)
    for i=#desktop.windows,1,-1 do
        local w=desktop.windows[i]
        if w.visible and not w.minimized and mx>=w.cx and mx<w.cx+w.cw and my>=w.cy and my<w.cy+w.ch then
            return w
        end
    end
    return nil
end

-- ============================================================
-- RENDER: DESKTOP
-- ============================================================
local SYM = R.PAL  -- shortcut

function desktop.drawDesktop()
    R.clear()
    local by = R.h - desktop.taskbarH

    -- Background
    R.fillRect(0, 0, R.w, by, SYM.W95_DESKTOP)

    -- Desktop icons in grid
    local icons = {{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw, ih = 48, 42
    local cols = math.max(1, math.floor((R.w-10)/(iw+10)))
    for i, icon in ipairs(icons) do
        local col=(i-1)%cols; local row=math.floor((i-1)/cols)
        local ix=8+col*(iw+10); local iy=8+row*(ih+8)
        if iy+ih>by-4 then break end
        local hover = desktop.mouse.x>=ix-2 and desktop.mouse.x<ix+iw+2 and desktop.mouse.y>=iy-2 and desktop.mouse.y<iy+ih+2
        if hover then R.fillRect(ix-2,iy-2,iw+4,ih+4,SYM.DARK_BLUE) end
        R.fillRect(ix,iy,iw,24,SYM.LIGHT_GRAY)
        R.drawW95Sunken(ix,iy,iw,24)
        R.drawText(ix+16,iy+7,icon[1]:sub(1,1),SYM.DARK_BLUE)
        R.drawText(ix,iy+28,icon[1],SYM.WHITE)
    end

    -- Windows
    for _,win in ipairs(desktop.windows) do
        if win.visible and not win.minimized then desktop.drawWindow(win) end
    end

    -- Taskbar
    R.fillRect(0,by,R.w,desktop.taskbarH,SYM.GRAY)
    R.drawLine(0,by,R.w-1,by,SYM.WHITE)

    -- Start button
    R.drawButton(2,by+2,54,16,desktop.startMenuOpen)
    R.drawText(6,by+6,"Start",SYM.BLACK)

    -- Window buttons in taskbar
    local btnX=60
    for _,win in ipairs(desktop.windows) do
        local bw=math.min(100,R.w-btnX-55)
        if bw<25 then break end
        local ia=(desktop.activeWin and desktop.activeWin.id==win.id)
        R.drawButton(btnX,by+3,bw,14,ia)
        local tt=#win.title>12 and win.title:sub(1,10)..".." or win.title
        if win.minimized then tt="("..tt..")" end
        R.drawText(btnX+4,by+6,tt,ia and SYM.WHITE or SYM.BLACK)
        btnX=btnX+bw+2
    end

    -- Clock
    R.drawW95Sunken(R.w-48,by+3,44,14)
    R.drawText(R.w-44,by+6,desktop.clock,SYM.BLACK)

    -- Start menu
    if desktop.startMenuOpen then
        local my=by-100; if my<1 then my=1 end
        R.fillRect(2,my,140,96,SYM.GRAY)
        R.drawW95Raised(2,my,140,96)
        R.fillRect(4,my+2,20,92,SYM.DARK_BLUE)
        R.drawText(5,my+30,"CC",SYM.WHITE)
        local items={{"File Manager","files"},{"Text Editor","edit"},{"Settings","settings"},{"Shell","shell"},{"Reboot","reboot"},{"Shutdown","shutdown"}}
        local iy=my+4
        for _,item in ipairs(items) do
            local hover=desktop.mouse.x>=26 and desktop.mouse.x<138 and desktop.mouse.y>=iy and desktop.mouse.y<iy+12
            if hover then R.fillRect(26,iy,112,12,SYM.DARK_BLUE) end
            R.drawText(28,iy+2,item[1],hover and SYM.WHITE or SYM.BLACK)
            iy=iy+14
        end
    end

    desktop.dirty=false
    desktop.lastDragRect=nil
end

-- ============================================================
-- RENDER: SINGLE WINDOW
-- ============================================================
function desktop.drawWindow(win)
    local x,y,w,h=win.cx,win.cy,win.cw,win.ch
    local by=R.h-desktop.taskbarH
    if y+h>by then h=math.max(20,by-y) end

    R.fillRect(x,y,w,h,SYM.LIGHT_BG)
    local active=(desktop.activeWin and desktop.activeWin.id==win.id)
    R.drawTitleBar(x,y,w,active)
    R.drawText(x+4,y+4,win.title,active and SYM.WHITE or SYM.GRAY)

    -- Title bar buttons
    R.drawButton(x+w-18,y+1,16,14,false); R.drawText(x+w-13,y+4,"X",SYM.BLACK)
    R.drawButton(x+w-36,y+1,16,14,false); R.drawRect(x+w-32,y+4,8,8,SYM.BLACK)
    R.drawButton(x+w-54,y+1,16,14,false); R.fillRect(x+w-49,y+6,6,2,SYM.BLACK)

    R.drawW95Raised(x,y,w,h)
    R.fillRect(x+2,y+17,w-4,h-19,SYM.LIGHT_BG)
    if win.onDraw then pcall(win.onDraw,win,x+3,y+18,w-6,h-21) end
end

-- ============================================================
-- MOUSE HANDLING
-- ============================================================
function desktop.handleClick(mx,my,button)
    -- Start menu
    if desktop.startMenuOpen then
        local my2=R.h-desktop.taskbarH-100; if my2<1 then my2=1 end
        local items={"files","edit","settings","shell","reboot","shutdown"}
        local iy=my2+4
        for _,action in ipairs(items) do
            if mx>=26 and mx<138 and my>=iy and my<iy+12 then
                desktop.startMenuOpen=false; return action
            end
            iy=iy+14
        end
        desktop.startMenuOpen=false; return nil
    end

    -- Start button
    local by=R.h-desktop.taskbarH
    if mx>=2 and mx<56 and my>=by+2 and my<by+18 then
        desktop.startMenuOpen=true; return nil
    end

    -- Taskbar window buttons
    if my>=by then
        local btnX=60
        for _,win in ipairs(desktop.windows) do
            local bw=math.min(100,R.w-btnX-55)
            if bw<25 then break end
            if mx>=btnX and mx<btnX+bw and my>=by+3 and my<by+17 then
                if win.minimized then
                    win.minimized=false; win.visible=true
                    desktop.bringToFront(win); desktop.dirty=true
                elseif desktop.activeWin and desktop.activeWin.id==win.id then
                    win.minimized=true; desktop.dirty=true
                else
                    desktop.bringToFront(win); desktop.dirty=true
                end
                return nil
            end
            btnX=btnX+bw+2
        end
        return nil
    end

    -- Desktop icons
    local icons={{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw,ih=48,42
    local cols=math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,icon in ipairs(icons) do
        local col=(i-1)%cols; local row=math.floor((i-1)/cols)
        local ix=8+col*(iw+10); local iy=8+row*(ih+8)
        if mx>=ix-2 and mx<ix+iw+2 and my>=iy-2 and my<iy+ih+2 then return icon[2] end
    end

    -- Windows
    local win=desktop.getWindowAt(mx,my)
    if win then
        desktop.bringToFront(win)
        -- Title bar
        if my>=win.cy and my<win.cy+16 then
            if mx>=win.cx+win.cw-18 then desktop.destroyWindow(win); return nil end  -- close
            if mx>=win.cx+win.cw-36 and mx<win.cx+win.cw-20 then  -- maximize
                if win.maximized then
                    if win.prevState then win.cx=win.prevState.x;win.cy=win.prevState.y;win.cw=win.prevState.w;win.ch=win.prevState.h;win.prevState=nil end
                    win.maximized=false
                else
                    win.prevState={x=win.cx,y=win.cy,w=win.cw,h=win.ch}
                    win.cx=1;win.cy=1;win.cw=R.w;win.ch=R.h-desktop.taskbarH-1;win.maximized=true
                end
                desktop.dirty=true; return nil
            end
            if mx>=win.cx+win.cw-54 and mx<win.cx+win.cw-38 then  -- minimize
                win.minimized=true; desktop.dirty=true; return nil
            end
            -- Drag start
            if not win.maximized then
                desktop.dragWin=win
                desktop.dragOX=mx-win.cx; desktop.dragOY=my-win.cy
            end
            return nil
        end
        -- Resize
        if mx>=win.cx+win.cw-8 and my>=win.cy+win.ch-8 and not win.maximized then
            win.resizing=true; return nil
        end
        -- Client click
        if win.onClick then pcall(win.onClick,win,mx-win.cx-3,my-win.cy-18) end
        return nil
    end

    return nil  -- empty space
end

function desktop.handleDrag(mx,my)
    local win=desktop.dragWin
    if not win then return end
    local nx=mx-desktop.dragOX; local ny=my-desktop.dragOY
    if ny<1 then ny=1 end
    local by=R.h-desktop.taskbarH
    if ny+win.ch>by+1 then ny=by-win.ch+2 end

    -- Clear old drag outline
    if desktop.lastDragRect then
        local r=desktop.lastDragRect
        local cx=math.max(1,r.x); local cy=math.max(1,r.y)
        local cw=math.min(r.w,R.w-cx); local ch=math.min(r.h,by-cy)
        if cw>0 and ch>0 then R.fillRect(cx,cy,cw,ch,SYM.W95_DESKTOP) end
        -- Redraw any windows that were under the old rect
        for _,w in ipairs(desktop.windows) do
            if w.id~=win.id and w.visible and not w.minimized then
                -- Simple overlap check
                if not (w.cx+w.cw < r.x or w.cx > r.x+r.w or w.cy+w.ch < r.y or w.cy > r.y+r.h) then
                    desktop.drawWindow(w)
                end
            end
        end
    end

    -- Draw new drag outline
    R.drawDragOutline(nx,ny,win.cw,win.ch)
    desktop.lastDragRect={x=nx,y=ny,w=win.cw,h=win.ch}
end

function desktop.handleMouseUp()
    if desktop.dragWin then
        local win=desktop.dragWin
        local nx=desktop.mouse.x-desktop.dragOX
        local ny=desktop.mouse.y-desktop.dragOY
        if ny<1 then ny=1 end
        local by=R.h-desktop.taskbarH
        if ny+win.ch>by+1 then ny=by-win.ch+2 end
        win.cx=nx; win.cy=ny
        desktop.dragWin=nil
        desktop.lastDragRect=nil
        desktop.dirty=true  -- full redraw to place window at final position
    end
    -- Stop resize
    for _,w in ipairs(desktop.windows) do w.resizing=false end
end

function desktop.handleKey(key,char)
    if desktop.activeWin and desktop.activeWin.onKey then
        pcall(desktop.activeWin.onKey,desktop.activeWin,key,char)
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
function desktop.run()
    R.init()
    local running=true
    local timer=os.startTimer(1)
    desktop.drawDesktop()

    while running do
        local event,p1,p2,p3,p4=os.pullEvent()

        if event=="mouse_click" then
            desktop.mouse.x=p2; desktop.mouse.y=p3
            local action=desktop.handleClick(p2,p3,p1)
            if action=="reboot" then
                R.clear();R.drawText(10,10,"Rebooting...",SYM.WHITE);sleep(0.5);os.reboot()
            elseif action=="shutdown" then running=false
            elseif action=="files" then desktop.app_fm()
            elseif action=="edit" then desktop.app_editor()
            elseif action=="settings" then desktop.app_settings()
            elseif action=="shell" then desktop.app_shell()
            end
            if desktop.dirty then desktop.drawDesktop() end

        elseif event=="mouse_drag" then
            desktop.mouse.x=p2; desktop.mouse.y=p3
            desktop.handleDrag(p2,p3)
            -- No full redraw — drag outline is drawn directly

        elseif event=="mouse_up" then
            desktop.handleMouseUp()
            if desktop.dirty then desktop.drawDesktop() end

        elseif event=="key" then
            if p1==keys.q and desktop.startMenuOpen then
                desktop.startMenuOpen=false; desktop.dirty=true
            else
                desktop.handleKey(p1,nil)
            end

        elseif event=="char" then
            desktop.handleKey(nil,p1)

        elseif event=="timer" then
            local t=os.time and os.time() or 0
            local h=math.floor(t); local m=math.floor((t-h)*60)
            local nc=string.format("%02d:%02d",h,m)
            if nc~=desktop.clock then
                desktop.clock=nc
                -- Partial redraw: just clock area
                local by=R.h-desktop.taskbarH
                R.drawW95Sunken(R.w-48,by+3,44,14)
                R.drawText(R.w-44,by+6,nc,SYM.BLACK)
            end
            timer=os.startTimer(1)
        end
    end

    R.clear();R.fillRect(0,0,R.w,R.h,SYM.BLACK)
    R.drawText(10,10,"CCOS shutdown.",SYM.WHITE)
end

-- ============================================================
-- APPS
-- ============================================================

function desktop.app_fm()
    local path="/"
    local selected=1
    local scroll=0
    local items={}

    local function refresh()
        local list=fs.list(path); table.sort(list)
        items={}
        if path~="/" then table.insert(items,"..") end
        for _,item in ipairs(list) do
            local fp=path=="/" and ("/"..item) or (path.."/"..item)
            table.insert(items,fs.isDir(fp) and ("/"..item) or item)
        end
        if #items==0 then items={"(empty)"} end
        selected=math.max(1,math.min(selected,#items))
    end
    refresh()

    local win=desktop.createWindow("File Manager",30,25,220,130)
    win.onDraw=function(w,cx,cy,cw,ch)
        local lh=math.floor((ch-20)/8)
        for i=1,lh do
            local idx=scroll+i; local item=items[idx]
            if not item then break end
            local iy=cy+(i-1)*8
            local hover=desktop.mouse.x>=cx and desktop.mouse.x<cx+cw and desktop.mouse.y>=iy-1 and desktop.mouse.y<iy+8
            if idx==selected or hover then
                R.fillRect(cx,iy-1,cw,9,SYM.DARK_BLUE)
                R.drawText(cx+2,iy,item,SYM.WHITE)
            else
                R.drawText(cx+2,iy,item,SYM.BLACK)
            end
        end
        R.fillRect(cx,cy+ch-12,cw,10,SYM.GRAY)
        R.drawText(cx+2,cy+ch-10," "..path,SYM.BLACK)
    end
    win.onKey=function(w,key,char)
        if key==keys.up and selected>1 then selected=selected-1; if selected<=scroll then scroll=scroll-1 end
        elseif key==keys.down and selected<#items then selected=selected+1; local lh=math.floor((w.ch-20)/8); if selected>scroll+lh then scroll=scroll+1 end
        elseif key==keys.enter then
            local item=items[selected]; if not item then return end
            if item==".." then path=getDir(path);selected=1;scroll=0;refresh()
            elseif item:sub(1,1)=="/" then local np=path=="/" and item or (path..item); if fs.isDir(np) then path=np;selected=1;scroll=0;refresh() end
            else local fp=path=="/" and ("/"..item) or (path.."/"..item); desktop.app_editor(fp) end
        elseif key==keys.backspace then path=getDir(path);selected=1;scroll=0;refresh()
        elseif key==keys.f5 then refresh()
        elseif key==keys.escape or key==keys.q then desktop.destroyWindow(w) end
    end
    win.onClick=function(w,mx,my)
        local lh=math.floor((w.ch-20)/8)
        for i=1,lh do
            local idx=scroll+i; local iy=18+(i-1)*8
            if my>=iy-1 and my<iy+8 then
                selected=idx; local item=items[idx]
                if not item then return end
                if item==".." then path=getDir(path);selected=1;scroll=0;refresh()
                elseif item:sub(1,1)=="/" then local np=path=="/" and item or (path..item); if fs.isDir(np) then path=np;selected=1;scroll=0;refresh() end
                else local fp=path=="/" and ("/"..item) or (path.."/"..item); desktop.app_editor(fp) end
                return
            end
        end
    end
end

function desktop.app_editor(filePath)
    filePath=filePath or "/untitled.txt"
    local lines={}
    local content=readFile(filePath)
    if content then for line in content:gmatch("[^\n]*") do table.insert(lines,line) end end
    if #lines==0 then table.insert(lines,"") end
    local cL,cC,sY=1,1,0
    local modified=false

    local win=desktop.createWindow("Edit: "..getFileName(filePath),40,20,250,140)
    win.onDraw=function(w,cx,cy,cw,ch)
        local eh=math.floor((ch-16)/8)
        for i=1,eh do local li=sY+i; R.drawText(cx+2,cy+(i-1)*8,lines[li] or "",SYM.BLACK) end
        if cL>sY and cL<=sY+eh then
            local cy2=cy+(cL-sY-1)*8; local cx2=cx+(cC-1)*6
            if cx2>=cx and cx2<cx+cw then
                R.fillRect(cx2,cy2,6,8,SYM.DARK_BLUE)
                local c=(lines[cL] or ""):sub(cC,cC)
                R.drawText(cx2,cy2,c=="" and " " or c,SYM.WHITE)
            end
        end
        R.fillRect(cx,cy+ch-12,cw,10,SYM.GRAY)
        local ms=modified and " [mod]" or ""
        R.drawText(cx+2,cy+ch-10,"Ln "..cL..ms.." | F2=Save F3=Quit",SYM.BLACK)
    end
    win.onKey=function(w,key,char)
        if char then local l=lines[cL] or ""; lines[cL]=l:sub(1,cC-1)..char..l:sub(cC); cC=cC+1; modified=true
        elseif key==keys.backspace then
            if cC>1 then local l=lines[cL] or ""; lines[cL]=l:sub(1,cC-2)..l:sub(cC); cC=cC-1; modified=true
            elseif cL>1 then local pl=#lines[cL-1]; lines[cL-1]=lines[cL-1]..(lines[cL] or ""); table.remove(lines,cL); cL=cL-1; cC=pl+1; modified=true end
        elseif key==keys.enter then local l=lines[cL] or ""; lines[cL]=l:sub(1,cC-1); table.insert(lines,cL,l:sub(cC)); cL=cL+1; cC=1; modified=true
        elseif key==keys.up and cL>1 then cL=cL-1; cC=math.min(cC,#(lines[cL] or "")+1); if cL<=sY then sY=sY-1 end
        elseif key==keys.down and cL<#lines then cL=cL+1; cC=math.min(cC,#(lines[cL] or "")+1); local eh=math.floor((w.ch-16)/8); if cL>sY+eh then sY=sY+1 end
        elseif key==keys.left then if cC>1 then cC=cC-1 elseif cL>1 then cL=cL-1; cC=#(lines[cL] or "")+1 end
        elseif key==keys.right then if cC<=#(lines[cL] or "") then cC=cC+1 elseif cL<#lines then cL=cL+1; cC=1 end
        elseif key==keys.home then cC=1
        elseif key==keys["end"] then cC=#(lines[cL] or "")+1
        elseif key==keys.tab then local l=lines[cL] or ""; lines[cL]=l:sub(1,cC-1).."  "..l:sub(cC); cC=cC+2; modified=true
        elseif key==keys.f2 then local f=fs.open(filePath,"w"); if f then f.write(table.concat(lines,"\n")); f.close(); modified=false end
        elseif key==keys.f3 then if modified then local f=fs.open(filePath,"w"); if f then f.write(table.concat(lines,"\n")); f.close() end end; desktop.destroyWindow(w)
        end
    end
end

function desktop.app_settings()
    local lt=os.getComputerLabel and os.getComputerLabel() or "No Label"
    local win=desktop.createWindow("Settings",50,30,180,100)
    win.onDraw=function(w,cx,cy,cw,ch)
        R.drawText(cx+4,cy+4,"Computer Label:",SYM.BLACK)
        R.drawW95Sunken(cx+4,cy+16,cw-8,12)
        R.drawText(cx+6,cy+18,lt,SYM.BLACK)
        R.drawText(cx+4,cy+36,"Display: "..R.w.."x"..R.h,SYM.BLACK)
        R.drawText(cx+4,cy+48,"Color: "..(R.isColor and "Yes" or "No"),SYM.BLACK)
        R.drawText(cx+4,cy+60,"Graphics: "..(R.hasGraphics and "Yes" or "No"),SYM.BLACK)
    end
    win.onKey=function(w,key)
        if key==keys.escape or key==keys.q or key==keys.f3 then desktop.destroyWindow(w) end
    end
end

function desktop.app_shell()
    local output={"> "}
    local inputLine=""
    local scrollY=0

    local win=desktop.createWindow("Shell",30,25,250,130)
    win.onDraw=function(w,cx,cy,cw,ch)
        local ml=math.floor((ch-16)/8)
        for i=1,ml do R.drawText(cx+2,cy+(i-1)*8,output[scrollY+i] or "",SYM.BLACK) end
        R.fillRect(cx,cy+ch-12,cw,10,SYM.GRAY)
        R.drawText(cx+2,cy+ch-10,"> "..inputLine,SYM.BLACK)
    end
    win.onKey=function(w,key,char)
        if char then inputLine=inputLine..char
        elseif key==keys.backspace then inputLine=inputLine:sub(1,-2)
        elseif key==keys.enter then
            table.insert(output,"> "..inputLine)
            local cmd=inputLine; inputLine=""
            if cmd=="exit" then desktop.destroyWindow(w); return end
            local fn,err=load("return "..cmd,"shell","t",_G)
            if not fn then fn,err=load(cmd,"shell","t",_G) end
            if fn then local ok,res=pcall(fn); if ok then if res~=nil then table.insert(output,tostring(res)) end else table.insert(output,"Error: "..tostring(res)) end
            else table.insert(output,"Error: "..tostring(err)) end
            local ml=math.floor((w.ch-16)/8)
            if #output>ml then scrollY=#output-ml end
        elseif key==keys.up then if scrollY>0 then scrollY=scrollY-1 end
        elseif key==keys.down then local ml=math.floor((w.ch-16)/8); if scrollY<#output-ml then scrollY=scrollY+1 end
        elseif key==keys.q then desktop.destroyWindow(w)
        end
    end
end

return desktop
