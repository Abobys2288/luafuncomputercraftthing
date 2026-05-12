-- CCOS Program: Shell
local D = _G._desktop
local R = _G.ccos_render
local API = _G.ccos_api
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function getDir(p)
    if not p or p=="/" then return "/" end
    local t={}
    for s in p:gmatch("[^/]+") do t[#t+1]=s end
    if #t<=1 then return "/" end
    t[#t]=nil
    return "/"..table.concat(t,"/")
end

local function appShell()
    local out = {"> CCOS Shell — type 'help'"}
    local inp = ""
    local sy = 0
    local cwd = "/"
    local wx, wy, ww, wh = D.fitWin(280, 160)
    local w = D.createWindow("Shell", wx, wy, ww, wh)

    w.onDraw = function(win, cx, cy, cw, ch)
        local ml = math.floor((ch-20)/8)
        for i=1, ml do
            R.drawText(cx+2, cy+(i-1)*8, out[sy+i] or "", K.BLACK, K.GRAY)
        end
        R.fillRect(cx, cy+ch-14, cw, 12, K.GRAY)
        local prompt = cwd .. "> "
        if #prompt > 12 then prompt = "> " end
        R.drawText(cx+2, cy+ch-12, prompt .. inp, K.BLACK, K.GRAY)
    end

    w.onKey = function(win, k, ch)
        if ch then
            inp = inp .. ch
            D.markContentDirty(win)
        elseif k == keys.backspace then
            inp = inp:sub(1, -2)
            D.markContentDirty(win)
        elseif k == keys.enter then
            table.insert(out, cwd .. "> " .. inp)
            local cmdLine = inp
            inp = ""

            local args = {}
            for arg in cmdLine:gmatch("%S+") do table.insert(args, arg) end
            local cmd = args[1] or ""
            table.remove(args, 1)

            if cmd == "" then
                -- noop
            elseif cmd == "exit" then
                D.destroyWindow(win)
                return
            elseif cmd == "help" then
                table.insert(out, "Commands:")
                table.insert(out, "  ls [path]  cd <path>  pwd")
                table.insert(out, "  cat <file>  mkdir <dir>  rm <name>")
                table.insert(out, "  mv <src> <dst>  cp <src> <dst>")
                table.insert(out, "  wget <url> <file>  label [name]")
                table.insert(out, "  id  clear  reboot  shutdown")
            elseif cmd == "clear" then
                out = {cwd .. "> "}
                sy = 0
            elseif cmd == "ls" then
                local path = args[1] or cwd
                if path:sub(1,1) ~= "/" then path = (cwd=="/" and ("/"..path) or (cwd.."/"..path)) end
                local list = fs.list(path)
                if list then
                    table.sort(list)
                    local line = ""
                    for _, f in ipairs(list) do
                        local fp = path=="/" and ("/"..f) or (path.."/"..f)
                        local prefix = fs.isDir(fp) and "[DIR] " or "      "
                        local entry = prefix .. f
                        if #line + #entry + 2 > 50 then
                            table.insert(out, line)
                            line = entry
                        else
                            if line ~= "" then line = line .. "  " end
                            line = line .. entry
                        end
                    end
                    if line ~= "" then table.insert(out, line) end
                else
                    table.insert(out, "No such directory")
                end
            elseif cmd == "cd" then
                local d = args[1] or "/"
                if d == ".." then
                    cwd = getDir(cwd)
                elseif d:sub(1,1) == "/" then
                    if fs.isDir(d) then cwd = d else table.insert(out, "Not a directory") end
                else
                    local test = cwd=="/" and ("/"..d) or (cwd.."/"..d)
                    if fs.isDir(test) then cwd = test else table.insert(out, "Not a directory") end
                end
            elseif cmd == "pwd" then
                table.insert(out, cwd)
            elseif cmd == "cat" then
                local f = args[1]
                if f then
                    if f:sub(1,1) ~= "/" then f = (cwd=="/" and ("/"..f) or (cwd.."/"..f)) end
                    local c = API.readFile(f)
                    if c then
                        for line in c:gmatch("[^\n]*") do table.insert(out, line) end
                    else
                        table.insert(out, "No such file")
                    end
                else
                    table.insert(out, "Usage: cat <file>")
                end
            elseif cmd == "mkdir" then
                local d = args[1]
                if d then
                    if d:sub(1,1) ~= "/" then d = (cwd=="/" and ("/"..d) or (cwd.."/"..d)) end
                    fs.makeDir(d)
                else
                    table.insert(out, "Usage: mkdir <name>")
                end
            elseif cmd == "rm" then
                local f = args[1]
                if f then
                    if f:sub(1,1) ~= "/" then f = (cwd=="/" and ("/"..f) or (cwd.."/"..f)) end
                    if fs.exists(f) then fs.delete(f) else table.insert(out, "No such file") end
                else
                    table.insert(out, "Usage: rm <name>")
                end
            elseif cmd == "mv" then
                local src, dst = args[1], args[2]
                if src and dst then
                    if src:sub(1,1) ~= "/" then src = (cwd=="/" and ("/"..src) or (cwd.."/"..src)) end
                    if dst:sub(1,1) ~= "/" then dst = (cwd=="/" and ("/"..dst) or (cwd.."/"..dst)) end
                    if fs.exists(src) then fs.move(src, dst) else table.insert(out, "No such file") end
                else
                    table.insert(out, "Usage: mv <src> <dst>")
                end
            elseif cmd == "cp" then
                local src, dst = args[1], args[2]
                if src and dst then
                    if src:sub(1,1) ~= "/" then src = (cwd=="/" and ("/"..src) or (cwd.."/"..src)) end
                    if dst:sub(1,1) ~= "/" then dst = (cwd=="/" and ("/"..dst) or (cwd.."/"..dst)) end
                    if fs.exists(src) then fs.copy(src, dst) else table.insert(out, "No such file") end
                else
                    table.insert(out, "Usage: cp <src> <dst>")
                end
            elseif cmd == "wget" then
                local url, fileName = args[1], args[2]
                if url and fileName then
                    if fileName:sub(1,1) ~= "/" then fileName = (cwd=="/" and ("/"..fileName) or (cwd.."/"..fileName)) end
                    table.insert(out, "Downloading...")
                    local ok, response = pcall(http.get, url)
                    if ok and response then
                        local c = response.readAll()
                        response.close()
                        API.writeFile(fileName, c)
                        table.insert(out, "Saved: " .. fileName)
                    else
                        table.insert(out, "Download failed")
                    end
                else
                    table.insert(out, "Usage: wget <url> <file>")
                end
            elseif cmd == "label" then
                if args[1] then
                    if os.setComputerLabel then os.setComputerLabel(args[1]) end
                    table.insert(out, "Label: " .. args[1])
                else
                    local l = os.getComputerLabel and os.getComputerLabel() or "None"
                    table.insert(out, "Label: " .. l)
                end
            elseif cmd == "id" then
                table.insert(out, "Computer ID: " .. os.getComputerID())
            elseif cmd == "reboot" then
                os.reboot()
            elseif cmd == "shutdown" then
                os.shutdown()
            else
                local fn, err = load("return " .. cmdLine, "shell", "t", _G)
                if not fn then fn, err = load(cmdLine, "shell", "t", _G) end
                if fn then
                    local ok, r = pcall(fn)
                    if ok and r ~= nil then table.insert(out, tostring(r))
                    elseif not ok then table.insert(out, "Error: " .. tostring(r)) end
                else
                    table.insert(out, "Unknown: " .. cmd)
                    table.insert(out, "Type 'help' for commands")
                end
            end

            local ml = math.floor((w.ch - 20) / 8)
            if #out > ml then sy = #out - ml end
            D.markContentDirty(win)
        elseif k == keys.up then
            if sy > 0 then sy = sy - 1 end
            D.markContentDirty(win)
        elseif k == keys.down then
            local ml = math.floor((w.ch - 20) / 8)
            if sy < #out - ml then sy = sy + 1 end
            D.markContentDirty(win)
        elseif k == keys.escape then
            D.destroyWindow(win)
        end
    end
end

return {
    name = "Shell",
    icon = "shell",
    run = appShell
}
