-- CCOS Program: Shell
-- A small terminal-like console for CCOS.
local D = _G._desktop
local R = _G.ccos_render
local API = _G.ccos_api
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,GREEN=9,RED=11,CYAN=7}

local unpackArgs = table.unpack or unpack

local function drawText(x, y, text, fg, bg, w)
    if API and API.drawText then API.drawText(x, y, text, fg, bg, w)
    elseif R.drawTextClipped and w then R.drawTextClipped(x, y, text, fg, bg, w)
    else R.drawText(x, y, tostring(text or ""), fg, bg) end
end

local function popChar(text)
    if API and API.utf8Pop then return API.utf8Pop(text) end
    if R.utf8Pop then return R.utf8Pop(text) end
    return tostring(text or ""):sub(1, -2)
end

local function splitArgs(line)
    local args = {}
    for arg in tostring(line or ""):gmatch("%S+") do args[#args + 1] = arg end
    return args
end

local function normalizePath(path)
    local absolute = tostring(path or "/"):sub(1, 1) == "/"
    local parts = {}
    for part in tostring(path or ""):gmatch("[^/]+") do
        if part == ".." then table.remove(parts)
        elseif part ~= "." and part ~= "" then parts[#parts + 1] = part end
    end
    local out = table.concat(parts, "/")
    if absolute then out = "/" .. out end
    if out == "" then out = "/" end
    return out
end

local function absPath(cwd, path)
    path = tostring(path or "")
    if path == "" then return cwd end
    if path:sub(1, 1) == "/" then return normalizePath(path) end
    if cwd == "/" then return normalizePath("/" .. path) end
    return normalizePath(cwd .. "/" .. path)
end

local function appShell()
    local out = {}
    local input = ""
    local history = {}
    local histIndex = 0
    local sy = 0
    local cwd = "/"
    local wx, wy, ww, wh = D.fitWin(300, 175)
    local w = D.createWindow("Shell", wx, wy, ww, wh)

    local function rows()
        return math.max(1, math.floor((w.ch - 21 - 16) / 8))
    end

    local function maxScroll()
        return math.max(0, #out - rows())
    end

    local function followBottom()
        sy = maxScroll()
    end

    local function add(text, color)
        out[#out + 1] = {text = tostring(text or ""), color = color or K.WHITE}
        followBottom()
    end

    local function prompt()
        return "CCOS:" .. cwd .. "$ "
    end

    local function listDir(path)
        local ok, list = pcall(fs.list, path)
        if not ok or not list then add("ls: cannot access " .. path, K.RED); return end
        table.sort(list, function(a, b)
            local ap, bp = absPath(path, a), absPath(path, b)
            local ad, bd = fs.isDir(ap), fs.isDir(bp)
            if ad ~= bd then return ad end
            return a:lower() < b:lower()
        end)
        if #list == 0 then add("(empty)", K.DGRAY); return end
        for _, name in ipairs(list) do
            local fp = absPath(path, name)
            local mark = fs.isDir(fp) and "<DIR> " or "      "
            local size = ""
            if not fs.isDir(fp) then
                local okSize, got = pcall(fs.getSize, fp)
                size = okSize and (" " .. got .. "b") or ""
            end
            add(mark .. name .. size, fs.isDir(fp) and K.CYAN or K.WHITE)
        end
    end

    local function openProgram(name, args)
        name = tostring(name or ""):lower()
        for _, prog in ipairs(D.programs or {}) do
            local names = {
                tostring(prog.name or ""):lower(),
                tostring(prog.icon or ""):lower(),
                tostring(prog._dirName or ""):lower(),
            }
            for _, candidate in ipairs(names) do
                if candidate == name then
                    add("opening " .. prog.name, K.GREEN)
                    D.safeRun(function() prog.run(unpackArgs(args or {})) end)
                    return true
                end
            end
        end
        add("open: program not found: " .. name, K.RED)
        return false
    end

    local function execute(line)
        line = tostring(line or "")
        add(prompt() .. line, K.GREEN)
        if line:match("^%s*$") then return end
        history[#history + 1] = line
        histIndex = #history + 1

        local args = splitArgs(line)
        local cmd = tostring(table.remove(args, 1) or ""):lower()

        if cmd == "help" then
            add("commands: help clear pwd cd ls dir cat type mkdir rm del mv ren cp copy")
            add("          wget label id programs open lua echo reboot shutdown exit")
        elseif cmd == "clear" or cmd == "cls" then
            out = {}
            sy = 0
        elseif cmd == "exit" then
            D.destroyWindow(w)
            return
        elseif cmd == "pwd" then
            add(cwd)
        elseif cmd == "cd" then
            local target = absPath(cwd, args[1] or "/")
            if fs.isDir(target) then cwd = target else add("cd: not a directory: " .. target, K.RED) end
        elseif cmd == "ls" or cmd == "dir" then
            listDir(absPath(cwd, args[1] or cwd))
        elseif cmd == "cat" or cmd == "type" then
            local fp = absPath(cwd, args[1] or "")
            if fp == cwd then add("usage: cat <file>", K.RED)
            elseif not fs.exists(fp) or fs.isDir(fp) then add("cat: file not found: " .. fp, K.RED)
            else
                local c = API.readFile(fp) or ""
                local printed = false
                for line2 in (c .. "\n"):gmatch("([^\n]*)\n") do add(line2); printed = true end
                if not printed then add("") end
            end
        elseif cmd == "mkdir" then
            local fp = absPath(cwd, args[1] or "")
            if fp == cwd then add("usage: mkdir <dir>", K.RED) else fs.makeDir(fp); add("created " .. fp, K.GREEN) end
        elseif cmd == "rm" or cmd == "del" then
            local fp = absPath(cwd, args[1] or "")
            if fp == cwd then add("usage: rm <path>", K.RED)
            elseif fs.exists(fp) then fs.delete(fp); add("removed " .. fp, K.GREEN)
            else add("rm: not found: " .. fp, K.RED) end
        elseif cmd == "mv" or cmd == "ren" then
            local src, dst = args[1], args[2]
            if not src or not dst then add("usage: mv <src> <dst>", K.RED)
            else
                src, dst = absPath(cwd, src), absPath(cwd, dst)
                if fs.exists(src) then fs.move(src, dst); add("moved " .. src .. " -> " .. dst, K.GREEN)
                else add("mv: not found: " .. src, K.RED) end
            end
        elseif cmd == "cp" or cmd == "copy" then
            local src, dst = args[1], args[2]
            if not src or not dst then add("usage: cp <src> <dst>", K.RED)
            else
                src, dst = absPath(cwd, src), absPath(cwd, dst)
                if fs.exists(src) then fs.copy(src, dst); add("copied " .. src .. " -> " .. dst, K.GREEN)
                else add("cp: not found: " .. src, K.RED) end
            end
        elseif cmd == "wget" then
            local url, dst = args[1], args[2]
            if not http then add("wget: HTTP API disabled", K.RED)
            elseif not url or not dst then add("usage: wget <url> <file>", K.RED)
            else
                dst = absPath(cwd, dst)
                add("downloading...", K.DGRAY)
                local ok, response = pcall(http.get, url)
                if ok and response then
                    API.writeFile(dst, response.readAll())
                    response.close()
                    add("saved " .. dst, K.GREEN)
                else add("download failed", K.RED) end
            end
        elseif cmd == "label" then
            if args[1] then
                if os.setComputerLabel then os.setComputerLabel(table.concat(args, " ")) end
                add("label set", K.GREEN)
            else add("label: " .. tostring(os.getComputerLabel and os.getComputerLabel() or "none")) end
        elseif cmd == "id" then
            add("computer id: " .. os.getComputerID())
        elseif cmd == "programs" then
            for _, prog in ipairs(D.programs or {}) do add((prog._dirName or "?") .. " - " .. (prog.name or "?")) end
        elseif cmd == "open" then
            openProgram(args[1], {select(2, unpackArgs(args))})
        elseif cmd == "lua" then
            local expr = table.concat(args, " ")
            if expr == "" then add("usage: lua <expr>", K.RED)
            else
                local fn, err = load("return " .. expr, "shell", "t", _G)
                if not fn then fn, err = load(expr, "shell", "t", _G) end
                if not fn then add("lua: " .. tostring(err), K.RED)
                else
                    local ok, result = pcall(fn)
                    if ok and result ~= nil then add(tostring(result), K.CYAN)
                    elseif not ok then add("lua: " .. tostring(result), K.RED) end
                end
            end
        elseif cmd == "echo" then
            add(table.concat(args, " "))
        elseif cmd == "reboot" then os.reboot()
        elseif cmd == "shutdown" then os.shutdown()
        else
            add(cmd .. ": command not found", K.RED)
        end
        followBottom()
    end

    add("CCOS Shell")
    add("type 'help' for commands")

    w.onDraw = function(_, cx, cy, cw, ch)
        R.fillRect(cx, cy, cw, ch, K.BLACK)
        local count = rows()
        for i = 1, count do
            local item = out[sy + i]
            if not item then break end
            drawText(cx + 3, cy + 3 + (i - 1) * 8, item.text, item.color, K.BLACK, cw - 8)
        end
        local inputY = cy + ch - 11
        R.drawLine(cx, inputY - 3, cx + cw - 1, inputY - 3, K.DGRAY)
        drawText(cx + 3, inputY, prompt() .. input .. "_", K.GREEN, K.BLACK, cw - 8)
    end

    w.onKey = function(_, k, ch)
        if ch then
            input = input .. ch
            D.markContentDirty(w)
        elseif k == keys.backspace then
            input = popChar(input)
            D.markContentDirty(w)
        elseif k == keys.enter then
            local line = input
            input = ""
            execute(line)
            D.markContentDirty(w)
        elseif k == keys.up then
            if #history > 0 then
                histIndex = math.max(1, histIndex - 1)
                input = history[histIndex] or input
            end
            D.markContentDirty(w)
        elseif k == keys.down then
            if #history > 0 then
                histIndex = math.min(#history + 1, histIndex + 1)
                input = history[histIndex] or ""
            end
            D.markContentDirty(w)
        elseif k == keys.pageUp then
            sy = math.max(0, sy - rows())
            D.markContentDirty(w)
        elseif k == keys.pageDown then
            sy = math.min(maxScroll(), sy + rows())
            D.markContentDirty(w)
        elseif k == keys.home then
            sy = 0
            D.markContentDirty(w)
        elseif k == keys["end"] then
            followBottom()
            D.markContentDirty(w)
        elseif k == keys.escape then
            D.destroyWindow(w)
        end
    end

    w.onScroll = function(_, dir)
        if dir < 0 then sy = math.max(0, sy - 3)
        else sy = math.min(maxScroll(), sy + 3) end
        D.markContentDirty(w)
    end
end

return {
    name = "Shell",
    icon = "shell",
    run = appShell
}
