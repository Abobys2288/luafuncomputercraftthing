-- CCOS Program: Package Manager
-- Install/remove built-in programs, direct program.lua URLs, and simple .ccpkg files.
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,GREEN=9}

local REPO = "Abobys2288/luafuncomputercraftthing"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/programs/"
local MANIFEST_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/packages.lua"

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    else R.drawText(x, y, w and clip(text, w) or text, fg, bg) end
end

local function button(x, y, w, text)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, text, K.BLACK, K.GRAY, w - 8) end
end

local function loadManifestFromString(content)
    local fn, err = load(content, "packages", "t", {})
    if not fn then return nil, err end
    local ok, packages = pcall(fn)
    if not ok then return nil, packages end
    if type(packages) ~= "table" then return nil, "manifest is not a table" end
    return packages
end

local function loadLocalManifest()
    if fs.exists("/ccos/packages.lua") then
        local fn = loadfile("/ccos/packages.lua")
        if fn then
            local ok, packages = pcall(fn)
            if ok and type(packages) == "table" then return packages end
        end
    end
    return {
        {name="fm", title="File Manager", desc="Browse files"},
        {name="edit", title="Text Editor", desc="Edit text files"},
        {name="settings", title="System Info", desc="System settings"},
        {name="shell", title="Shell", desc="Terminal emulator"},
        {name="calc", title="Calculator", desc="Calculator app"},
        {name="tasks", title="Task Manager", desc="Manage windows"},
        {name="netbrowse", title="Network Browser", desc="Browse network"},
        {name="chat", title="Chat", desc="Network chat"},
        {name="pkgman", title="Packages", desc="Install packages"},
        {name="imgview", title="Image Viewer", desc="View images"},
        {name="music", title="Music", desc="Speaker player"},
        {name="fastfetch", title="Fastfetch", desc="System overview"},
        {name="sites", title="Sites", desc="Host and browse pages"},
    }
end

local function parsePackage(content)
    local ok, pkg = pcall(textutils.unserialize, content)
    if ok and type(pkg) == "table" and pkg.name then return pkg end
    local fn = load(content, "ccpkg", "t", {})
    if fn then
        local ok2, pkg2 = pcall(fn)
        if ok2 and type(pkg2) == "table" and pkg2.name then return pkg2 end
    end
    return nil
end

local function appPkgMan()
    local packages = {}
    local installed = {}
    local sel, scroll = 1, 0
    local status = "F5 refresh  Enter install/remove"

    local function scanInstalled()
        installed = {}
        if fs.isDir("/ccos/programs") then
            for _, name in ipairs(fs.list("/ccos/programs")) do
                if fs.exists("/ccos/programs/" .. name .. "/program.lua") then installed[name] = true end
            end
        end
    end

    local function fetchList()
        status = "Loading manifest..."
        D.markDirty()
        packages = nil
        if http then
            local ok, response = pcall(http.get, MANIFEST_URL)
            if ok and response then
                local content = response.readAll()
                response.close()
                local parsed = loadManifestFromString(content)
                if parsed then packages = parsed end
            end
        end
        packages = packages or loadLocalManifest()
        table.sort(packages, function(a, b) return tostring(a.title or a.name) < tostring(b.title or b.name) end)
        scanInstalled()
        sel, scroll = 1, 0
        status = #packages .. " package(s)"
        D.markDirty()
    end

    local function writePackage(pkg)
        if not pkg or not pkg.name then return false, "Invalid package" end
        local base = "/ccos/programs/" .. pkg.name
        if not fs.isDir(base) then fs.makeDir(base) end
        if pkg.files then
            for path, content in pairs(pkg.files) do
                API.writeFile(base .. "/" .. path, content)
            end
        elseif pkg.content then
            API.writeFile(base .. "/program.lua", pkg.content)
        else
            return false, "Package has no files"
        end
        installed[pkg.name] = true
        D.loadPrograms()
        return true
    end

    local function installBuiltIn(pkg)
        status = "Installing " .. pkg.name .. "..."
        D.markDirty()
        local url = BASE_URL .. pkg.name .. "/program.lua"
        local ok, response = pcall(http.get, url)
        if ok and response then
            local content = response.readAll()
            response.close()
            local okWrite, err = writePackage({name=pkg.name, content=content})
            status = okWrite and "Installed: " .. pkg.name or tostring(err)
        else
            status = "Download failed"
        end
        scanInstalled()
        D.markDirty()
    end

    local function removePackage(pkg)
        if not pkg then return end
        local path = "/ccos/programs/" .. pkg.name
        if fs.exists(path) then
            fs.delete(path)
            installed[pkg.name] = nil
            status = "Removed: " .. pkg.name
            D.loadPrograms()
        else
            status = "Not installed"
        end
        D.markDirty()
    end

    local function installFromUrl(url, explicitName)
        if not http then status = "HTTP disabled"; D.markDirty(); return end
        status = "Downloading URL..."
        D.markDirty()
        local ok, response = pcall(http.get, url)
        if not ok or not response then status = "Download failed"; D.markDirty(); return end
        local content = response.readAll()
        response.close()

        local pkg = parsePackage(content)
        if not pkg then
            local name = explicitName or (url:match("/([^/%?]+)%.lua") or "external")
            pkg = {name=name, content=content}
        end
        local okWrite, err = writePackage(pkg)
        status = okWrite and ("Installed: " .. pkg.name) or tostring(err)
        fetchList()
    end

    local wx, wy, ww, wh = API.fitWindow(290, 180)
    local w = API.window("Packages", wx, wy, ww, wh)
    if not w then return end

    w.onDraw = function(_, cx, cy, cw, ch)
        button(cx, cy, math.min(50, cw), "Refresh")
        if cw >= 130 then button(cx + 54, cy, 70, "Install URL") end
        if cw >= 188 then button(cx + 128, cy, 54, "Remove") end
        if cw >= 226 then drawText(cx + 188, cy + 3, status, K.DGRAY, K.GRAY, cw - 192) end

        local listY = cy + 20
        local rows = math.max(1, math.floor((ch - 34) / 8))
        local hasHit = false
        for i = 1, rows do
            local iy = listY + (i - 1) * 8
            if D.mouse.x >= cx + 2 and D.mouse.x < cx + cw - 2 and D.mouse.y >= iy and D.mouse.y < iy + 8 then hasHit = true; break end
        end

        for i = 1, rows do
            local idx = scroll + i
            local pkg = packages[idx]
            if not pkg then break end
            local iy = listY + (i - 1) * 8
            local hit = D.mouse.x >= cx + 2 and D.mouse.x < cx + cw - 2 and D.mouse.y >= iy and D.mouse.y < iy + 8
            local active = (hasHit and hit) or (not hasHit and idx == sel)
            if active then R.fillRect(cx + 2, iy, cw - 4, 8, K.DBLUE) end
            local fg, bg = active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY
            local mark = installed[pkg.name] and "[+] " or "[ ] "
            local text = mark .. (pkg.title or pkg.name) .. " - " .. (pkg.desc or "")
            drawText(cx + 4, iy, text, fg, bg, cw - 8)
        end

        drawText(cx + 4, cy + ch - 10, "Enter toggles  F5 refresh  U install URL", K.DGRAY, K.GRAY, cw - 8)
    end

    w.onClick = function(_, mx, my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 50 then fetchList(); return
            elseif mx >= 54 and mx < 124 then
                D.inputDialog("Install URL", "program.lua or .ccpkg URL:", "https://", function(url)
                    if url then
                        D.inputDialog("Package name", "Name if plain Lua:", "", function(name)
                            installFromUrl(url, name ~= "" and name or nil)
                        end)
                    end
                end)
                return
            elseif mx >= 128 and mx < 182 then removePackage(packages[sel]); return end
        end

        local rows = math.max(1, math.floor((w.ch - 21 - 34) / 8))
        for i = 1, rows do
            local iy = 20 + (i - 1) * 8
            if my >= iy and my < iy + 8 then sel = math.min(#packages, scroll + i); D.markContentDirty(w); return end
        end
    end

    w.onKey = function(_, k, ch)
        local rows = math.max(1, math.floor((w.ch - 21 - 34) / 8))
        if k == keys.f5 then fetchList()
        elseif ch == "u" or ch == "U" then
            D.inputDialog("Install URL", "program.lua or .ccpkg URL:", "https://", function(url)
                if url then D.inputDialog("Package name", "Name if plain Lua:", "", function(name) installFromUrl(url, name ~= "" and name or nil) end) end
            end)
        elseif k == keys.up and sel > 1 then sel = sel - 1; if sel <= scroll then scroll = math.max(0, scroll - 1) end; D.markContentDirty(w)
        elseif k == keys.down and sel < #packages then sel = sel + 1; if sel > scroll + rows then scroll = scroll + 1 end; D.markContentDirty(w)
        elseif k == keys.enter then
            local pkg = packages[sel]
            if pkg then if installed[pkg.name] then removePackage(pkg) else installBuiltIn(pkg) end end
        elseif k == keys.delete then removePackage(packages[sel])
        elseif k == keys.escape then API.close(w) end
    end

    fetchList()
end

return {name = "Packages", icon = "pkg", run = appPkgMan}
