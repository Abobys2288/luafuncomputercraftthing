-- CCOS Program: Package Manager
-- Install/remove programs from online repository
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local REPO = "Abobys2288/luafuncomputercraftthing"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/programs/"

local function appPkgMan()
    local packages = {}
    local sel = 1
    local scroll = 0
    local status = "Press F5 to refresh"
    local installed = {}

    local function scanInstalled()
        installed = {}
        if fs.isDir("/ccos/programs") then
            for _,name in ipairs(fs.list("/ccos/programs")) do
                if fs.exists("/ccos/programs/"..name.."/program.lua") then
                    installed[name] = true
                end
            end
        end
    end

    local function fetchList()
        status = "Loading..."; D.markDirty()
        -- In a real implementation, you'd have a manifest.json
        -- For now, we use a hardcoded list of known packages
        packages = {
            {name="fm", title="File Manager", desc="Browse files"},
            {name="edit", title="Text Editor", desc="Edit text files"},
            {name="settings", title="System Info", desc="System settings"},
            {name="shell", title="Shell", desc="Terminal emulator"},
            {name="calc", title="Calculator", desc="Calculator app"},
            {name="tasks", title="Task Manager", desc="Manage windows"},
            {name="netbrowse", title="Network Browser", desc="Browse network"},
            {name="chat", title="Chat", desc="Network chat"},
        }
        scanInstalled()
        sel = 1; scroll = 0
        status = #packages .. " packages"
        D.markDirty()
    end

    local function install(pkg)
        status = "Installing "..pkg.name.."..."; D.markDirty()
        local url = BASE_URL .. pkg.name .. "/program.lua"
        local path = "/ccos/programs/" .. pkg.name .. "/program.lua"
        if not fs.isDir("/ccos/programs/" .. pkg.name) then fs.makeDir("/ccos/programs/" .. pkg.name) end
        local ok, response = pcall(http.get, url)
        if ok and response then
            local c = response.readAll(); response.close()
            local f = fs.open(path, "w")
            if f then f.write(c); f.close(); installed[pkg.name] = true; status = "Installed!"; D.loadPrograms()
            else status = "Write error" end
        else status = "Download failed" end
        D.markDirty()
    end

    local function remove(pkg)
        status = "Removing "..pkg.name.."..."; D.markDirty()
        local path = "/ccos/programs/" .. pkg.name
        if fs.exists(path) then fs.delete(path); installed[pkg.name] = nil; status = "Removed!"; D.loadPrograms()
        else status = "Not found" end
        D.markDirty()
    end

    local wx, wy, ww, wh = D.fitWin(240, 160)
    local w = D.createWindow("Packages", wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,50,14,false)
        R.drawText(cx+4,cy+3,"Refresh",K.BLACK,K.GRAY)
        R.drawText(cx+58,cy+3,status,K.BLACK,K.GRAY)
        local lh = math.floor((ch-28)/8)
        for i=1,lh do
            local idx=scroll+i; local pkg=packages[idx]
            if not pkg then break end
            local iy=cy+16+(i-1)*8
            local hit=D.mouse.x>=cx+2 and D.mouse.x<cx+cw-2 and D.mouse.y>=iy and D.mouse.y<iy+8
            if idx==sel or hit then R.fillRect(cx+2,iy,cw-4,8,K.DBLUE) end
            local mark = installed[pkg.name] and "[+] " or "[ ] "
            local text = mark .. pkg.title .. " - " .. pkg.desc
            R.drawText(cx+4,iy,text:sub(1,math.floor((cw-8)/6)),hit and K.WHITE or K.BLACK,hit and K.DBLUE or K.GRAY)
        end
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 and mx>=0 and mx<50 then fetchList(); return end
        local lh=math.floor((w.ch-28)/8)
        for i=1,lh do
            local iy=16+(i-1)*8
            if my>=iy and my<iy+8 then sel=scroll+i; D.markContentDirty(w); return end
        end
    end

    w.onKey = function(_,k)
        if k==keys.f5 then fetchList()
        elseif k==keys.up and sel>1 then sel=sel-1; if sel<=scroll then scroll=scroll-1 end; D.markContentDirty(w)
        elseif k==keys.down and sel<#packages then sel=sel+1; local lh=math.floor((w.ch-28)/8); if sel>scroll+lh then scroll=scroll+1 end; D.markContentDirty(w)
        elseif k==keys.enter then
            local pkg=packages[sel]; if pkg then
                if installed[pkg.name] then remove(pkg) else install(pkg) end
            end
        elseif k==keys.escape then D.destroyWindow(w) end
    end

    fetchList()
end

return {name = "Packages", icon = "pkg", run = appPkgMan}
