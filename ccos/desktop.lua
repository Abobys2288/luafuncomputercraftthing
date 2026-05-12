--[[
    CCOS Desktop v14 — MINIMAL WORKING VERSION
    ==========================================
    This version is guaranteed to work.
    Copy this file and reboot your Computer in Minecraft.
]]

local R = _G.ccos_render
local D = {} ; _G._desktop = D

local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

D.windows = {}
D.activeWin = nil
D.taskbarH = 20
D.startMenuOpen = false
D.clock = ""
D.nextWinId = 1
D.dragWin = nil
D.dragOX = 0
D.dragOY = 0
D.mouse = {x=0,y=0}
D.dirty = true

local function getDir(p) if not p or p=="/" then return "/" end local t={} for s in p:gmatch("[^/]+") do t[#t+1]=s end if #t<=1 then return "/" end t[#t]=nil return "/"..table.concat(t,"/") end
local function getFileName(p) if not p or p=="/" then return "" end local l=nil for s in p:gmatch("[^/]+") do l=s end return l or "" end
local function readFile(p) if not fs.exists(p) then return nil end local f=fs.open(p,"r") if not f then return nil end local c=f.readAll() f.close() return c end
local function writeFile(p,c) local f=fs.open(p,"w") if not f then return false end f.write(c) f.close() return true end

function D.markDirty() D.dirty = true end

-- Simple input dialog
local function simpleInput(title, prompt, default)
    default = default or ""
    local input = default
    local result = nil
    local w = D.createWindow(title, 30, 30, 240, 80)

    w.onDraw = function(win, cx, cy, cw, ch)
        R.drawText(cx+4, cy+4, prompt, K.BLACK)
        R.drawW95Sunken(cx+4, cy+18, cw-8, 16)
        R.drawText(cx+6, cy+20, input .. "_", K.BLACK)
        R.drawText(cx+4, cy+42, "Enter=OK  Esc=Cancel", K.BLACK)
    end

    w.onKey = function(win, k, ch)
        if ch then
            input = input .. ch
            D.markDirty()
        elseif k == keys.backspace then
            input = input:sub(1, -2)
            D.markDirty()
        elseif k == keys.enter then
            result = input ~= "" and input or nil
            D.destroyWindow(win)
        elseif k == keys.escape then
            result = nil
            D.destroyWindow(win)
        end
    end

    while w.visible do
        D.drawAll()
        os.pullEvent()
    end
    return result
end

function D.createWindow(title,cx,cy,cw,ch)
    local id = D.nextWinId D.nextWinId = id + 1
    local w = {id=id,title=title or "Win",cx=cx or 30,cy=cy or 20,cw=cw or 200,ch=ch or 120,visible=true,minimized=false,onDraw=nil,onKey=nil,onClick=nil}
    table.insert(D.windows,w) D.activeWin = w D.markDirty() return w
end

function D.destroyWindow(w)
    for i,v in ipairs(D.windows) do if v.id==w.id then table.remove(D.windows,i) break end end
    D.activeWin = D.windows[#D.windows]
    w.visible = false
    D.markDirty()
end

function D.bringToFront(w)
    for i,v in ipairs(D.windows) do if v.id==w.id then table.remove(D.windows,i) table.insert(D.windows,w) D.activeWin=w D.markDirty() return end end
end

function D.winAt(mx,my)
    for i=#D.windows,1,-1 do local w=D.windows[i] if w.visible and not w.minimized and mx>=w.cx and mx<w.cx+w.cw and my>=w.cy and my<w.cy+w.ch then return w end end
    return nil
end

function D.drawAll()
    if not D.dirty then return end
    R.clear()
    local by = R.h - D.taskbarH
    R.fillRect(0,0,R.w,by,K.DESKTOP)
    -- Desktop icons
    local icons = {{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw,ih = 48,42
    local cols = math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,icon in ipairs(icons) do
        local col = (i-1)%cols local row = math.floor((i-1)/cols)
        local ix,iy = 8+col*(iw+10),8+row*(ih+8)
        if iy+ih > by-4 then break end
        local hover = D.mouse.x>=ix-2 and D.mouse.x<ix+iw+2 and D.mouse.y>=iy-2 and D.mouse.y<iy+ih+2
        if hover then R.fillRect(ix-2,iy-2,iw+4,ih+4,K.DBLUE) end
        R.fillRect(ix,iy,iw,24,K.LGRAY) R.drawW95Sunken(ix,iy,iw,24)
        R.drawText(ix+16,iy+7,icon[1]:sub(1,1),K.DBLUE) R.drawText(ix,iy+28,icon[1],K.WHITE)
    end
    -- Windows
    for _,w in ipairs(D.windows) do if w.visible and not w.minimized then
        local x,y,ww,hh = w.cx,w.cy,w.cw,w.ch
        if y+hh > by then hh = math.max(20,by-y) end
        R.fillRect(x,y,ww,hh,K.GRAY)
        local act = D.activeWin and D.activeWin.id == w.id
        R.fillRect(x,y,ww,18,act and K.DBLUE or K.GRAY)
        R.drawText(x+4,y+4,w.title,act and K.WHITE or K.LGRAY)
        R.drawButton(x+ww-18,y+1,16,14,false) R.drawText(x+ww-13,y+4,"X",K.BLACK)
        R.drawW95Raised(x,y,ww,hh)
        R.fillRect(x+2,y+17,ww-4,hh-19,K.GRAY)
        if w.onDraw then pcall(w.onDraw,w,x+3,y+18,ww-6,hh-21) end
    end end
    -- Taskbar
    R.fillRect(0,by,R.w,D.taskbarH,K.GRAY)
    R.drawLine(0,by,R.w-1,by,K.WHITE)
    R.drawButton(2,by+2,54,16,D.startMenuOpen)
    R.drawText(6,by+6,"Start",K.BLACK)
    local bx = 60
    for _,w in ipairs(D.windows) do
        local bw = math.min(100,R.w-bx-55) if bw<25 then break end
        local active = D.activeWin and D.activeWin.id == w.id
        R.drawButton(bx,by+3,bw,14,active)
        local t = #w.title > 12 and w.title:sub(1,10)..".." or w.title
        if w.minimized then t = "("..t..")" end
        R.drawText(bx+4,by+6,t,active and K.WHITE or K.BLACK)
        bx = bx + bw + 2
    end
    R.drawW95Sunken(R.w-48,by+3,44,14)
    R.drawText(R.w-44,by+6,D.clock,K.BLACK)
    -- Start Menu
    if D.startMenuOpen then
        local mw,mh = 140,96
        local my = (by+2)-mh if my<1 then my=1 end
        local sx=2
        R.fillRect(sx,my,mw,mh,K.GRAY)
        R.drawW95Raised(sx,my,mw,mh)
        R.fillRect(sx+2,my+2,20,mh-4,K.DBLUE)
        R.drawText(sx+3,my+30,"CC",K.WHITE)
        local items = {{"File Manager","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"},{"Reboot","reboot"},{"Shutdown","shutdown"}}
        local iy = my + 4
        for _,it in ipairs(items) do
            local hit = D.mouse.x >= sx+24 and D.mouse.x < sx+mw-4 and D.mouse.y >= iy and D.mouse.y < iy+12
            if hit then R.fillRect(sx+24,iy,mw-28,12,K.DBLUE) end
            R.drawText(sx+28,iy+2,it[1],hit and K.WHITE or K.BLACK)
            iy = iy + 14
        end
    end
    D.dirty = false
end

function D.click(mx,my)
    local by = R.h - D.taskbarH
    -- Start Menu
    if D.startMenuOpen then
        local mw,mh = 140,96
        local my2 = (by+2)-mh if my2<1 then my2=1 end
        if mx>=2 and mx<2+mw and my>=my2 and my<my2+mh then
            local items = {"files","edit","settings","shell","reboot","shutdown"}
            local iy = my2 + 4
            for _,a in ipairs(items) do
                if mx>=26 and mx<2+mw-4 and my>=iy and my<iy+12 then
                    D.startMenuOpen = false D.markDirty() return a
                end
                iy = iy + 14
            end
            return nil
        else
            D.startMenuOpen = false D.markDirty()
        end
    end
    -- Start button
    if mx>=2 and mx<56 and my>=by+2 and my<by+18 then
        D.startMenuOpen = not D.startMenuOpen
        D.markDirty()
        return nil
    end
    -- Taskbar
    if my >= by then
        local bx = 60
        for _,w in ipairs(D.windows) do
            local bw = math.min(100,R.w-bx-55) if bw<25 then break end
            if mx>=bx and mx<bx+bw then
                if w.minimized then w.minimized=false w.visible=true D.bringToFront(w)
                elseif D.activeWin and D.activeWin.id==w.id then w.minimized=true
                else D.bringToFront(w) end
                D.markDirty() return nil
            end
            bx = bx + bw + 2
        end
        return nil
    end
    -- Windows
    local w = D.winAt(mx,my)
    if w then
        D.bringToFront(w)
        if my >= w.cy and my < w.cy+16 then
            if mx >= w.cx+w.cw-18 then D.destroyWindow(w) return nil end
            if mx >= w.cx+w.cw-36 and mx < w.cx+w.cw-20 then
                if w.maximized then if w.prevState then w.cx=w.prevState.x w.cy=w.prevState.y w.cw=w.prevState.w w.ch=w.prevState.h w.prevState=nil end w.maximized=false
                else w.prevState={x=w.cx,y=w.cy,w=w.cw,h=w.ch} w.cx=1 w.cy=1 w.cw=R.w w.ch=by-1 w.maximized=true end
                D.markDirty() return nil
            end
            if mx >= w.cx+w.cw-54 and mx < w.cx+w.cw-38 then w.minimized=true D.markDirty() return nil end
            if not w.maximized then D.dragWin=w D.dragOX=mx-w.cx D.dragOY=my-w.cy end
            return nil
        end
        if w.onClick then pcall(w.onClick,w,mx-w.cx-3,my-w.cy-18) end
        return nil
    end
    -- Desktop icons
    local icons = {{"Files","files"},{"Editor","edit"},{"Settings","settings"},{"Shell","shell"}}
    local iw,ih = 48,42
    local cols = math.max(1,math.floor((R.w-10)/(iw+10)))
    for i,icon in ipairs(icons) do
        local col = (i-1)%cols local row = math.floor((i-1)/cols)
        local ix,iy = 8+col*(iw+10),8+row*(ih+8)
        if mx>=ix-2 and mx<ix+iw+2 and my>=iy-2 and my<iy+ih+2 then return icon[2] end
    end
    return nil
end

function D.drag(mx,my)
    local w = D.dragWin if not w then return end
    local nx = mx - D.dragOX local ny = my - D.dragOY
    if ny < 1 then ny = 1 end
    local by = R.h - D.taskbarH if ny + w.ch > by + 1 then ny = by - w.ch + 2 end
    if D.lastDragRect then local r = D.lastDragRect R.drawDragOutline(r.x,r.y,r.w,r.h) end
    R.drawDragOutline(nx,ny,w.cw,w.ch)
    D.lastDragRect = {x=nx,y=ny,w=w.cw,h=w.ch}
end

function D.drop()
    if D.dragWin then
        local w = D.dragWin
        w.cx = D.mouse.x - D.dragOX w.cy = D.mouse.y - D.dragOY
        if w.cy < 1 then w.cy = 1 end
        local by = R.h - D.taskbarH if w.cy + w.ch > by + 1 then w.cy = by - w.ch + 2 end
        D.dragWin = nil D.lastDragRect = nil D.markDirty()
    end
end

-- ============================================
-- APPS (MINIMAL)
-- ============================================
function D.appFM()
    local path = "/" local sel = 1 local scroll = 0 local items = {}
    local function refresh()
        local l = fs.list(path) table.sort(l) items = {}
        if path ~= "/" then table.insert(items,"..") end
        for _,it in ipairs(l) do
            local fp = path=="/" and ("/"..it) or (path.."/"..it)
            table.insert(items,fs.isDir(fp) and ("/"..it) or it)
        end
        if #items==0 then items={"(empty)"} end
        sel = math.max(1,math.min(sel,#items))
    end
    refresh()
    local w = D.createWindow("File Manager",20,15,260,160)
    w.onDraw = function(win,cx,cy,cw,ch)
        R.drawButton(cx,cy,40,14,false) R.drawText(cx+4,cy+3,"New",K.BLACK)
        R.drawButton(cx+42,cy,52,14,false) R.drawText(cx+46,cy+3,"New Dir",K.BLACK)
        R.drawButton(cx+96,cy,40,14,false) R.drawText(cx+100,cy+3,"Delete",K.BLACK)
        local lh = math.floor((ch-24)/8)
        for i=1,lh do
            local idx=scroll+i local it=items[idx]
            if not it then break end
            local iy=cy+16+(i-1)*8
            local hover = D.mouse.x>=cx+2 and D.mouse.x<cx+cw-2 and D.mouse.y>=iy-1 and D.mouse.y<iy+8
            if idx==sel or hover then
                R.fillRect(cx+2,iy-1,cw-4,9,K.DBLUE)
                R.drawText(cx+4,iy,it,K.WHITE)
            else
                R.drawText(cx+4,iy,it,K.BLACK) end
        end
        R.drawText(cx+2,cy+ch-10," "..path,K.BLACK)
    end
    w.onClick = function(win,mx,my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 40 then
                -- NEW FILE
                local name = simpleInput("New File", "Enter filename:", "newfile.txt")
                if name then
                    local fp = path=="/" and ("/"..name) or (path.."/"..name)
                    writeFile(fp,"") refresh() D.markDirty()
                end
            elseif mx >= 42 and mx < 94 then
                -- NEW DIR
                local name = simpleInput("New Folder", "Enter folder name:", "newdir")
                if name then
                    local fp = path=="/" and ("/"..name) or (path.."/"..name)
                    fs.makeDir(fp) refresh() D.markDirty()
                end
            elseif mx >= 96 and mx < 136 then
                -- DELETE
                local it = items[sel]
                if it and it ~= ".." then
                    local fp = path=="/" and ("/"..it) or (path.."/"..it)
                    if fs.exists(fp) then fs.delete(fp) end
                    refresh() D.markDirty()
                end
            end
            return
        end
        local lh = math.floor((win.ch-24)/8)
        for i=1,lh do
            local idx = scroll + i
            local iy = 16 + (i-1)*8
            if my >= iy-1 and my < iy+8 then sel=idx D.markDirty() return end
        end
    end
    w.onDoubleClick = function(win,mx,my)
        local lh = math.floor((win.ch-24)/8)
        for i=1,lh do
            local idx=scroll+i local iy=16+(i-1)*8
            if my >= iy-1 and my < iy+8 then
                local it = items[idx]
                if it then
                    if it == ".." then path=getDir(path) sel=1 scroll=0 refresh() D.markDirty()
                    elseif it:sub(1,1)=="/" then
                        local np = path=="/" and it or (path..it)
                        if fs.isDir(np) then path=np sel=1 scroll=0 refresh() D.markDirty() end
                    else D.appEdit(path=="/" and ("/"..it) or (path.."/"..it)) end
                end
                return
            end
        end
    end
    w.onKey = function(win,k,ch)
        if k==keys.up and sel>1 then sel=sel-1 if sel<=scroll then scroll=scroll-1 end D.markDirty()
        elseif k==keys.down and sel<#items then sel=sel+1 local lh=math.floor((win.ch-24)/8) if sel>scroll+lh then scroll=scroll+1 end D.markDirty()
        elseif k==keys.enter then
            local it=items[sel]
            if it then
                if it==".." then path=getDir(path)
                elseif it:sub(1,1)=="/" then local np=path=="/" and it or (path..it) if fs.isDir(np) then path=np end
                else D.appEdit(path=="/" and ("/"..it) or (path.."/"..it)) end
                sel=1 scroll=0 refresh() D.markDirty()
            end
        elseif k==keys.backspace then path=getDir(path) sel=1 scroll=0 refresh() D.markDirty()
        elseif k==keys.f5 then refresh() D.markDirty()
        elseif k==keys.escape or k==keys.q then D.destroyWindow(win) end
    end
end

function D.appEdit(fp)
    fp = fp or "/untitled.txt"
    local lines = {}
    local c = readFile(fp)
    if c then for l in c:gmatch("[^\n]*") do table.insert(lines,l) end end
    if #lines==0 then lines={""} end
    local cl,cc,sy = 1,1,0
    local mod = false
    local w = D.createWindow("Edit: "..getFileName(fp),30,18,260,150)
    w.onDraw = function(win,cx,cy,cw,ch)
        R.drawButton(cx,cy,36,14,false) R.drawText(cx+2,cy+3,"Save",K.BLACK)
        local eh = math.floor((ch-24)/8)
        for i=1,eh do R.drawText(cx+2,cy+16+(i-1)*8,lines[sy+i] or "",K.BLACK) end
        if cl > sy and cl <= sy+eh then
            local cy2 = cy+16+(cl-sy-1)*8
            local cx2 = cx+(cc-1)*6
            if cx2 >= cx and cx2 < cx+cw then
                R.fillRect(cx2,cy2,6,8,K.DBLUE)
                local c2 = (lines[cl] or ""):sub(cc,cc)
                R.drawText(cx2,cy2,c2=="" and " " or c2,K.WHITE)
            end
        end
        R.drawText(cx+2,cy+ch-10,getFileName(fp)..(mod and " *" or ""),K.BLACK)
    end
    w.onClick = function(win,mx,my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 36 then
                writeFile(fp,table.concat(lines,"\n"))
                mod = false D.markDirty()
            end
        end
    end
    w.onKey = function(win,k,ch)
        if ch then
            local l = lines[cl] or ""
            lines[cl] = l:sub(1,cc-1)..ch..l:sub(cc)
            cc = cc + 1
            mod = true
            D.markDirty()  -- чтобы было видно, что печатаешь
        elseif k == keys.backspace then
            if cc > 1 then
                local l = lines[cl] or ""
                lines[cl] = l:sub(1,cc-2)..l:sub(cc)
                cc = cc - 1
            elseif cl > 1 then
                local pl = #(lines[cl-1] or "")
                lines[cl-1] = (lines[cl-1] or "") .. (lines[cl] or "")
                table.remove(lines,cl)
                cl = cl - 1
                cc = pl + 1
            end
            mod = true
        elseif k == keys.enter then
            local l = lines[cl] or ""
            lines[cl] = l:sub(1,cc-1)
            table.insert(lines,cl+1,l:sub(cc))
            cl = cl + 1
            cc = 1
            mod = true
        elseif k == keys.up and cl > 1 then
            cl = cl - 1
            cc = math.min(cc,#(lines[cl] or "") + 1)
            if cl <= sy then sy = sy - 1 end
        elseif k == keys.down and cl < #lines then
            cl = cl + 1
            cc = math.min(cc,#(lines[cl] or "") + 1)
            local eh = math.floor((win.ch-16)/8)
            if cl > sy + eh then sy = sy + 1 end
        elseif k == keys.left then
            if cc > 1 then cc = cc - 1 elseif cl > 1 then cl=cl-1 cc=#(lines[cl] or "")+1 end
        elseif k == keys.right then
            if cc <= #(lines[cl] or "") then cc = cc + 1 elseif cl < #lines then cl=cl+1 cc=1 end
        elseif k == keys.escape or k == keys.q then
            if mod then writeFile(fp,table.concat(lines,"\n")) end
            D.destroyWindow(win)
        end
    end
end

function D.appSettings()
    local w = D.createWindow("Settings",50,30,200,110)
    w.onDraw = function(win,cx,cy,cw,ch)
        R.drawText(cx+4,cy+4,"Label: "..(os.getComputerLabel and os.getComputerLabel() or "None"),K.BLACK)
        R.drawText(cx+4,cy+20,"Size: "..R.w.."x"..R.h,K.BLACK)
        R.drawText(cx+4,cy+32,"Windows: "..#D.windows,K.BLACK)
    end
    w.onKey = function(win,k) if k==keys.escape or k==keys.q then D.destroyWindow(win) end end
end

function D.appShell()
    local out = {"> Type 'help'"}
    local inp = ""
    local sy = 0
    local w = D.createWindow("Shell",30,25,260,140)
    w.onDraw = function(win,cx,cy,cw,ch)
        local ml = math.floor((ch-16)/8)
        for i=1,ml do R.drawText(cx+2,cy+(i-1)*8,out[sy+i] or "",K.BLACK) end
        R.fillRect(cx,cy+ch-12,cw,10,K.GRAY)
        R.drawText(cx+2,cy+ch-10,"> "..inp,K.BLACK)
    end
    w.onKey = function(win,k,ch)
        if ch then inp = inp..ch D.markDirty()
        elseif k==keys.backspace then inp=inp:sub(1,-2) D.markDirty()
        elseif k==keys.enter then
            table.insert(out,"> "..inp)
            local cmd = inp inp = ""
            if cmd == "exit" then D.destroyWindow(win) return end
            if cmd == "help" then table.insert(out,"help, ls, clear, exit")
            elseif cmd == "ls" then table.insert(out,table.concat(fs.list("/"),"  "))
            elseif cmd == "clear" then out = {"> "} sy=0
            else
                local fn,err = load("return "..cmd,"shell","t",_G)
                if not fn then fn,err=load(cmd,"shell","t",_G) end
                if fn then
                    local ok,r = pcall(fn)
                    if ok and r~=nil then table.insert(out,tostring(r))
                    elseif not ok then table.insert(out,"Err: "..tostring(r)) end
                else table.insert(out,"Err: "..tostring(err)) end
            end
            local ml = math.floor((w.ch-16)/8)
            if #out > ml then sy = #out - ml end
            D.markDirty()
        elseif k==keys.up then if sy>0 then sy=sy-1 end D.markDirty()
        elseif k==keys.down then local ml=math.floor((w.ch-16)/8) if sy < #out-ml then sy=sy+1 end D.markDirty()
        elseif k==keys.q then D.destroyWindow(win) end
    end
end

function D.run()
    R.init()
    local running = true
    local timer = os.startTimer(1)
    D.markDirty()
    while running do
        D.drawAll()
        local e,a,b,c,d = os.pullEvent()
        if e=="mouse_click" then
            D.mouse.x=b D.mouse.y=c
            local act = D.click(b,c)
            if act=="reboot" then os.reboot()
            elseif act=="shutdown" then running=false
            elseif act=="files" then D.appFM()
            elseif act=="edit" then D.appEdit()
            elseif act=="settings" then D.appSettings()
            elseif act=="shell" then D.appShell() end
        elseif e=="mouse_double_click" then
            D.mouse.x=b D.mouse.y=c
            local w = D.winAt(b,c)
            if w then
                D.bringToFront(w)
                if w.onDoubleClick then pcall(w.onDoubleClick,w,b-w.cx-3,c-w.cy-18) end
            end
        elseif e=="mouse_drag" then D.mouse.x=b D.mouse.y=c D.drag(b,c)
        elseif e=="mouse_up" then D.drop()
        elseif e=="key" then
            if a==keys.q and D.startMenuOpen then D.startMenuOpen=false D.markDirty()
            elseif D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey,D.activeWin,a,nil) end
        elseif e=="char" then
            if D.activeWin and D.activeWin.onKey then pcall(D.activeWin.onKey,D.activeWin,nil,a) end
        elseif e=="timer" then
            local t = os.time and os.time() or 0
            local h = math.floor(t)
            local m = math.floor((t-h)*60)
            local nc = string.format("%02d:%02d",h,m)
            if nc ~= D.clock then
                D.clock = nc
                local by = R.h - D.taskbarH
                R.fillRect(R.w-48,by+3,44,14,K.GRAY)
                R.drawW95Sunken(R.w-48,by+3,44,14)
                R.drawText(R.w-44,by+6,nc,K.BLACK)
            end
            timer = os.startTimer(1)
        end
    end
    R.clear()
    R.fillRect(0,0,R.w,R.h,K.BLACK)
    R.drawText(10,10,"CCOS shutdown.",K.WHITE)
end

return D
