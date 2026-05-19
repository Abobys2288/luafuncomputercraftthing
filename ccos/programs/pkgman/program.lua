-- CCOS Program: Package Manager
-- Install/remove built-in programs, URLs, local folders, program.lua files, and simple .ccpkg files.
local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,GREEN=9}

local REPO = "Abobys2288/luafuncomputercraftthing"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/programs/"
local ICON_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/icons/"
local MANIFEST_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/packages.lua"
local CORE = {fm=true, shell=true, settings=true, pkgman=true, tasks=true, imgview=true}

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
        {name="fm", title="File Explorer", desc="Explorer 2.0 with preview", icon="files"},
        {name="edit", title="Text Editor", desc="Edit text files", icon="edit"},
        {name="settings", title="Settings", desc="System, appearance and logs", icon="settings"},
        {name="shell", title="Shell", desc="Terminal emulator", icon="shell"},
        {name="calc", title="Calculator", desc="Calculator app", icon="calc"},
        {name="tasks", title="Task Manager", desc="Manage windows and background tasks", icon="tasks"},
        {name="netbrowse", title="Network Browser", desc="Browse network", icon="net"},
        {name="chat", title="Chat", desc="Network chat", icon="chat"},
        {name="pkgman", title="Packages", desc="Install or run packages from URL, disk or folder", icon="pkg"},
        {name="imgview", title="Image Viewer Pro", desc="View images safely", icon="img"},
        {name="music", title="Music", desc="Speaker player", icon="music"},
        {name="fastfetch", title="Fastfetch", desc="System overview", icon="fastfetch"},
        {name="sites", title="Sites Browser", desc="Browse pages", icon="sites"},
        {name="sitebuilder", title="Site Builder", desc="Create and host pages", icon="sitebuild"},
    }
end

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizePath(path)
    path = trim(path):gsub("\\", "/")
    if path == "" then return nil end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    while path:find("//", 1, true) do path = path:gsub("//", "/") end
    if #path > 1 then path = path:gsub("/+$", "") end
    return path
end

local function baseName(path)
    path = normalizePath(path) or tostring(path or "")
    if path == "/" then return "root" end
    return path:match("([^/]+)$") or "local"
end

local function stripExt(name)
    return tostring(name or ""):gsub("%.[^%.]+$", "")
end

local function safeName(name)
    name = stripExt(name):gsub("[^%w_%-%.]", "_"):gsub("^_+", ""):gsub("_+$", "")
    if name == "" or name == "." or name == ".." then name = "localpkg" end
    return name:sub(1, 32)
end

local function safeRelPath(path)
    path = tostring(path or ""):gsub("\\", "/"):gsub("^%./", "")
    if path == "" or path:sub(1, 1) == "/" then return nil end
    for part in path:gmatch("[^/]+") do
        if part == "." or part == ".." or part == "" then return nil end
    end
    return path
end

local function readAll(path)
    if API and API.readFile then return API.readFile(path) end
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    return content
end

local function loadChunk(content, name, env)
    if _VERSION == "Lua 5.1" and loadstring then
        local fn, err = loadstring(content, name)
        if fn and env and setfenv then setfenv(fn, env) end
        return fn, err
    end
    return load(content, name, "t", env)
end

local function parsePackage(content)
    local ok, pkg = pcall(textutils.unserialize, content)
    if ok and type(pkg) == "table" and pkg.name then return pkg end
    local fn = loadChunk(content, "ccpkg", {})
    if fn then
        local ok2, pkg2 = pcall(fn)
        if ok2 and type(pkg2) == "table" and pkg2.name then return pkg2 end
    end
    return nil
end

local function appPkgMan(initialSource)
    local packages = {}
    local installed = {}
    local sel, scroll = 1, 0
    local status = "F5 refresh  Enter install/remove"
    local detail = "Select a package"

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

    local function rememberPackage(pkg, desc)
        if not pkg or not pkg.name then return end
        local found = false
        for _, item in ipairs(packages or {}) do
            if item.name == pkg.name then
                item.title = pkg.title or item.title or pkg.name
                item.desc = pkg.desc or item.desc or desc
                item.icon = pkg.icon or item.icon
                found = true
                break
            end
        end
        if not found then
            packages[#packages + 1] = {
                name = pkg.name,
                title = pkg.title or pkg.name,
                desc = pkg.desc or desc or "Local package",
                icon = pkg.icon or "pkg",
            }
        end
        table.sort(packages, function(a, b) return tostring(a.title or a.name) < tostring(b.title or b.name) end)
    end

    local function writePackage(pkg)
        if not pkg or not pkg.name then return false, "Invalid package" end
        pkg.name = safeName(pkg.name)
        local base = "/ccos/programs/" .. pkg.name
        if not fs.isDir(base) then fs.makeDir(base) end
        local wroteProgram = false
        if pkg.files then
            for path, content in pairs(pkg.files) do
                local rel = safeRelPath(path)
                if rel then
                    API.writeFile(base .. "/" .. rel, tostring(content or ""))
                    if rel == "program.lua" then wroteProgram = true end
                end
            end
        elseif pkg.content then
            API.writeFile(base .. "/program.lua", pkg.content)
            wroteProgram = true
        else
            return false, "Package has no files"
        end
        if not wroteProgram then return false, "Package has no program.lua" end
        installed[pkg.name] = true
        D.loadPrograms()
        rememberPackage(pkg, "Local package")
        if API and API.notify then API.notify("Packages", "Installed " .. pkg.name, "ok", 4) end
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
            if okWrite and pkg.icon and http then
                local okIcon, iconResp = pcall(http.get, ICON_URL .. pkg.icon .. ".nfp256")
                if okIcon and iconResp then
                    API.writeFile("/ccos/icons/" .. pkg.icon .. ".nfp256", iconResp.readAll())
                    iconResp.close()
                end
            end
            status = okWrite and "Installed: " .. pkg.name or tostring(err)
        else
            status = "Download failed"
        end
        scanInstalled()
        D.markDirty()
    end

    local function removePackage(pkg)
        if not pkg then return end
        if CORE[pkg.name] then
            status = "Core package protected"
            if API and API.notify then API.notify("Packages", pkg.name .. " is protected", "error", 4) end
            D.markDirty()
            return
        end
        local path = "/ccos/programs/" .. pkg.name
        if fs.exists(path) then
            fs.delete(path)
            installed[pkg.name] = nil
            status = "Removed: " .. pkg.name
            D.loadPrograms()
            if API and API.notify then API.notify("Packages", "Removed " .. pkg.name, "ok", 4) end
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

    local function collectFiles(dir, prefix, out)
        local ok, list = pcall(fs.list, dir)
        if not ok or not list then return end
        table.sort(list)
        for _, name in ipairs(list) do
            local fp = dir .. "/" .. name
            local rel = prefix == "" and name or (prefix .. "/" .. name)
            if fs.isDir(fp) then
                collectFiles(fp, rel, out)
            else
                out[rel] = readAll(fp) or ""
            end
        end
    end

    local function packageFromFile(path)
        local content = readAll(path)
        if not content then return nil, "Cannot read file" end
        local pkg = parsePackage(content)
        if not pkg then
            local name = safeName(path:match("/([^/%?]+)%.lua$") or path:match("/([^/%?]+)%.ccpkg$") or baseName(path))
            pkg = {name=name, content=content}
        end
        return pkg
    end

    local function packageFromDirectory(path)
        local pkgFile = path .. "/package.ccpkg"
        if fs.exists(pkgFile) and not fs.isDir(pkgFile) then
            local pkg, err = packageFromFile(pkgFile)
            if pkg and (pkg.files or pkg.content) then return pkg end
            if err then return nil, err end
        end

        local programPath = path .. "/program.lua"
        if not fs.exists(programPath) or fs.isDir(programPath) then
            return nil, "Folder has no program.lua"
        end

        local pkg = {name=safeName(baseName(path)), files={}}
        collectFiles(path, "", pkg.files)

        local manifestPath = path .. "/package.lua"
        if fs.exists(manifestPath) and not fs.isDir(manifestPath) then
            local meta = parsePackage(readAll(manifestPath) or "")
            if meta then
                pkg.name = meta.name or pkg.name
                pkg.title = meta.title
                pkg.desc = meta.desc
                pkg.icon = meta.icon
            end
        end
        return pkg
    end

    local function packageFromSource(path)
        path = normalizePath(path)
        if not path then return nil, "Path is empty" end
        if not fs.exists(path) then return nil, "Path not found" end
        if fs.isDir(path) then return packageFromDirectory(path) end
        return packageFromFile(path)
    end

    local function loadProgramFromCode(content, source)
        local fn, err = loadChunk(content, "@" .. tostring(source or "local package"), _ENV or _G)
        if not fn then return nil, err end
        local ok, prog = pcall(fn)
        if not ok then return nil, prog end
        if type(prog) == "function" then return {name=baseName(source), run=prog} end
        if type(prog) == "table" and type(prog.run) == "function" then return prog end
        return nil, "Package has no run()"
    end

    local function runProgramTable(prog, source)
        status = "Running: " .. tostring(prog.name or baseName(source))
        D.markDirty()
        D.safeRun(function() prog.run(source) end)
    end

    local function runFromSource(path)
        path = normalizePath(path)
        if not path then return end
        if not fs.exists(path) then status = "Path not found"; D.markDirty(); return end

        if fs.isDir(path) then
            local programPath = path .. "/program.lua"
            if not fs.exists(programPath) then status = "Folder has no program.lua"; D.markDirty(); return end
            local ok, prog = pcall(function()
                local fn, err = loadfile(programPath)
                if not fn then error(err) end
                return fn()
            end)
            if ok and type(prog) == "table" and type(prog.run) == "function" then
                prog._sourceDir = path
                runProgramTable(prog, path)
            else
                status = "Run failed: " .. tostring(prog)
                D.markDirty()
            end
            return
        end

        local pkg, err = packageFromFile(path)
        if not pkg then status = tostring(err); D.markDirty(); return end
        local content = pkg.content or (pkg.files and pkg.files["program.lua"])
        if not content then status = "Package has no program.lua"; D.markDirty(); return end
        local prog, loadErr = loadProgramFromCode(content, path)
        if not prog then status = "Run failed: " .. tostring(loadErr); D.markDirty(); return end
        runProgramTable(prog, path)
    end

    local function installFromSource(path)
        if not path or path == "" then return end
        local pkg, err = packageFromSource(path)
        if not pkg then status = tostring(err); D.markDirty(); return end
        local okWrite, writeErr = writePackage(pkg)
        status = okWrite and ("Installed: " .. pkg.name) or tostring(writeErr)
        scanInstalled()
        D.markDirty()
    end

    local function promptLocalInstall()
        D.inputDialog("Install Local", ".ccpkg, program.lua or folder:", "/disk", installFromSource)
    end

    local function promptLocalRun()
        D.inputDialog("Run Local", ".ccpkg, program.lua or folder:", "/disk", runFromSource)
    end

    local function promptOpenedSource(path)
        if not path or path == "" then return end
        D.inputDialog("Package Source", "I install, R run:", "I", function(answer)
            answer = trim(answer):lower()
            if answer == "r" or answer == "run" then runFromSource(path)
            elseif answer ~= "" then installFromSource(path) end
        end)
    end

    local wx, wy, ww, wh = API.fitWindow(360, 200)
    local w = API.window("Packages", wx, wy, ww, wh)
    if not w then return end

    w.onDraw = function(_, cx, cy, cw, ch)
        button(cx, cy, math.min(50, cw), "Refresh")
        if cw >= 130 then button(cx + 54, cy, 70, "Install URL") end
        if cw >= 188 then button(cx + 128, cy, 54, "Local") end
        if cw >= 232 then button(cx + 186, cy, 40, "Run") end
        if cw >= 290 then button(cx + 230, cy, 54, "Remove") end
        if cw >= 330 then drawText(cx + 290, cy + 3, status, K.DGRAY, K.GRAY, cw - 294) end

        local listY = cy + 20
        local detailW = cw >= 330 and math.max(96, math.floor(cw * 0.34)) or 0
        local listW = detailW > 0 and (cw - detailW - 6) or cw
        local rows = math.max(1, math.floor((ch - 34) / 8))
        local hasHit = false
        for i = 1, rows do
            local iy = listY + (i - 1) * 8
            if D.mouse.x >= cx + 2 and D.mouse.x < cx + listW - 2 and D.mouse.y >= iy and D.mouse.y < iy + 8 then hasHit = true; break end
        end

        for i = 1, rows do
            local idx = scroll + i
            local pkg = packages[idx]
            if not pkg then break end
            local iy = listY + (i - 1) * 8
            local hit = D.mouse.x >= cx + 2 and D.mouse.x < cx + listW - 2 and D.mouse.y >= iy and D.mouse.y < iy + 8
            local active = (hasHit and hit) or (not hasHit and idx == sel)
            if active then R.fillRect(cx + 2, iy, listW - 4, 8, K.DBLUE) end
            local fg, bg = active and K.WHITE or K.BLACK, active and K.DBLUE or K.GRAY
            local mark = installed[pkg.name] and "[+] " or "[ ] "
            if CORE[pkg.name] then mark = "[*] " end
            local text = mark .. (pkg.title or pkg.name) .. " - " .. (pkg.desc or "")
            drawText(cx + 4, iy, text, fg, bg, listW - 8)
        end

        local pkg = packages[sel]
        if detailW > 0 then
            local px = cx + listW + 6
            R.drawW95Sunken(px, listY, detailW, ch - 34)
            if pkg then
                detail = (pkg.title or pkg.name or "?")
                drawText(px + 4, listY + 5, detail, K.BLACK, K.GRAY, detailW - 8)
                drawText(px + 4, listY + 17, "Name: " .. tostring(pkg.name or "?"), K.DGRAY, K.GRAY, detailW - 8)
                drawText(px + 4, listY + 29, installed[pkg.name] and "Installed" or "Not installed", installed[pkg.name] and K.GREEN or K.RED, K.GRAY, detailW - 8)
                drawText(px + 4, listY + 41, CORE[pkg.name] and "Core package" or "Optional", K.DGRAY, K.GRAY, detailW - 8)
                drawText(px + 4, listY + 53, tostring(pkg.desc or ""), K.DGRAY, K.GRAY, detailW - 8)
            else
                drawText(px + 4, listY + 5, detail, K.DGRAY, K.GRAY, detailW - 8)
            end
        end

        drawText(cx + 4, cy + ch - 10, "Enter toggles  F5 refresh  U URL  L install  R run", K.DGRAY, K.GRAY, cw - 8)
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
            elseif mx >= 128 and mx < 182 then
                promptLocalInstall()
                return
            elseif mx >= 186 and mx < 226 then promptLocalRun(); return
            elseif mx >= 230 and mx < 284 then removePackage(packages[sel]); return end
        end

        local rows = math.max(1, math.floor((w.ch - 21 - 34) / 8))
        local cw = w.cw - 6
        local detailW = cw >= 330 and math.max(96, math.floor(cw * 0.34)) or 0
        local listW = detailW > 0 and (cw - detailW - 6) or cw
        for i = 1, rows do
            local iy = 20 + (i - 1) * 8
            if mx < listW and my >= iy and my < iy + 8 then sel = math.min(#packages, scroll + i); D.markContentDirty(w); return end
        end
    end

    w.onKey = function(_, k, ch)
        local rows = math.max(1, math.floor((w.ch - 21 - 34) / 8))
        if k == keys.f5 then fetchList()
        elseif ch == "u" or ch == "U" then
            D.inputDialog("Install URL", "program.lua or .ccpkg URL:", "https://", function(url)
                if url then D.inputDialog("Package name", "Name if plain Lua:", "", function(name) installFromUrl(url, name ~= "" and name or nil) end) end
            end)
        elseif ch == "l" or ch == "L" then
            promptLocalInstall()
        elseif ch == "r" or ch == "R" then
            promptLocalRun()
        elseif k == keys.up and sel > 1 then sel = sel - 1; if sel <= scroll then scroll = math.max(0, scroll - 1) end; D.markContentDirty(w)
        elseif k == keys.down and sel < #packages then sel = sel + 1; if sel > scroll + rows then scroll = scroll + 1 end; D.markContentDirty(w)
        elseif k == keys.enter then
            local pkg = packages[sel]
            if pkg then if installed[pkg.name] then removePackage(pkg) else installBuiltIn(pkg) end end
        elseif k == keys.delete then removePackage(packages[sel])
        elseif k == keys.escape then API.close(w) end
    end

    w.onScroll = function(_, dir)
        local rows = math.max(1, math.floor((w.ch - 21 - 34) / 8))
        local maxScroll = math.max(0, #packages - rows)
        if dir < 0 then scroll = math.max(0, scroll - 3)
        else scroll = math.min(maxScroll, scroll + 3) end
        sel = math.max(1, math.min(#packages, math.max(sel, scroll + 1)))
        D.markContentDirty(w)
    end

    fetchList()
    if initialSource then promptOpenedSource(initialSource) end
end

return {name = "Packages", icon = "pkg", run = appPkgMan}
