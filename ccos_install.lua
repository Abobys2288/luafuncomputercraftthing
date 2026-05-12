--[[
    CCOS Installer v5 — CLEAN AUTOMATIC
    ======================================
    Auto-discovers all files, creates dirs automatically, nice UI.
]]

local REPO = "Abobys2288/luafuncomputercraftthing"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/"

-- ============================================================
-- FILE MANIFEST (relative to ccos/ in repo)
-- ============================================================
local FILES = {
    -- Core
    "init.lua",
    "render.lua",
    "desktop.lua",
    "api.lua",
    "kernel.lua",
    "gui.lua",
    "bootlogo.nfp256",
    -- Programs
    "programs/fm/program.lua",
    "programs/edit/program.lua",
    "programs/settings/program.lua",
    "programs/shell/program.lua",
    "programs/calc/program.lua",
    "programs/tasks/program.lua",
    "programs/netbrowse/program.lua",
    "programs/chat/program.lua",
    "programs/pkgman/program.lua",
    "programs/imgview/program.lua",
    "programs/music/program.lua",
    -- Drivers
    "drivers/net.lua",
}

local SERVER_FILE = "ccos_server.lua"
local SERVER_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/" .. SERVER_FILE

-- ============================================================
-- UI HELPERS
-- ============================================================
local W, H = term.getSize()
local C = term.isColor and term.isColor() or false

local function set(bg, fg)
    if not C then return end
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
end

local function reset()
    if not C then return end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function cls()
    reset()
    term.clear()
    term.setCursorPos(1, 1)
end

local function fill(x, y, w2, h2, bg)
    if not C then return end
    set(bg)
    for row = 0, h2 - 1 do
        term.setCursorPos(x, y + row)
        term.write(string.rep(" ", w2))
    end
end

local function box(x, y, bw, bh, bg, border)
    set(border)
    term.setCursorPos(x, y)
    term.write("\159" .. string.rep("\143", bw - 2) .. "\144")
    for i = 1, bh - 2 do
        term.setCursorPos(x, y + i)
        term.write("\149" .. string.rep(" ", bw - 2) .. "\149")
    end
    term.setCursorPos(x, y + bh - 1)
    term.write("\130" .. string.rep("\143", bw - 2) .. "\129")
    if bg and C then fill(x + 1, y + 1, bw - 2, bh - 2, bg) end
end

local function progress(x, y, pw, done, total)
    done = math.min(done, total)
    local filled = math.floor((done / total) * (pw - 2))
    if C then
        term.setCursorPos(x, y)
        set(colors.black, colors.white)
        term.write("[")
        set(colors.cyan, colors.black)
        term.write(string.rep("\127", filled))
        set(colors.gray, colors.lightGray)
        term.write(string.rep("\127", pw - 2 - filled))
        set(colors.black, colors.white)
        term.write("]")
    else
        term.setCursorPos(x, y)
        term.write("[")
        term.write(string.rep("#", filled))
        term.write(string.rep("-", pw - 2 - filled))
        term.write("]")
    end
    reset()
end

-- ============================================================
-- LOGIC
-- ============================================================
local function ensureDir(path)
    local dir = path:match("(.+)/[^/]+")
    if dir and dir ~= "" then
        local parts = {}
        for part in dir:gmatch("[^/]+") do
            table.insert(parts, part)
        end
        local build = ""
        for _, part in ipairs(parts) do
            build = build .. "/" .. part
            if not fs.exists(build) then fs.makeDir(build) end
        end
    end
end

local function downloadFile(url, path)
    local response = http.get(url)
    if not response then return false, "HTTP GET failed" end
    local c = response.readAll()
    response.close()
    ensureDir(path)
    local f = fs.open(path, "w")
    if not f then return false, "Write failed" end
    f.write(c)
    f.close()
    return true
end

local function main()
    cls()
    if C then fill(1, 1, W, H, colors.black) end

    local bw = math.min(64, W - 4)
    local bh = math.min(18, H - 4)
    local bx = math.floor((W - bw) / 2) + 1
    local by = math.floor((H - bh) / 2) + 1

    box(bx, by, bw, bh, colors.black, colors.cyan)
    set(colors.black, colors.cyan)
    term.setCursorPos(bx + 2, by + 1)
    term.write("  CCOS v3 Installer")
    set(colors.black, colors.lightGray)
    term.setCursorPos(bx + 2, by + 2)
    term.write("  github.com/" .. REPO)
    reset()

    term.setCursorPos(bx + 2, by + 3)
    set(colors.black, colors.gray)
    term.write(string.rep("\143", bw - 4))
    reset()

    local pbX = bx + 3
    local pbY = by + 5
    local pbW = bw - 6

    if not http then
        term.setCursorPos(bx + 3, by + bh - 2)
        set(colors.black, colors.red)
        term.write("ERROR: HTTP API not enabled!")
        reset() sleep(5)
        return
    end

    local total = #FILES + 1
    local success, failed = 0, 0
    local logLines = {}
    local listY = by + 7
    local maxLines = math.min(6, bh - 10)

    for i, file in ipairs(FILES) do
        progress(pbX, pbY, pbW, i, total)

        local display = file
        if #display > 34 then display = "..." .. display:sub(-31) end
        local pct = math.floor((i / total) * 100)

        -- Scroll file list if too many
        local listIdx = math.min(i, maxLines)
        if i > maxLines then
            -- shuffle up, remove oldest from screen
            for j = 2, maxLines do
                term.setCursorPos(bx + 3, listY + j - 1)
                set(colors.black, colors.gray)
                local old = FILES[i - maxLines + j] or ""
                if #old > 34 then old = "..." .. old:sub(-31) end
                term.write(old)
            end
            listIdx = maxLines
        end

        term.setCursorPos(bx + 3, listY + listIdx - 1)
        set(colors.black, colors.lightGray)
        term.write(display)

        local url = BASE_URL .. file
        local path = "/ccos/" .. file
        local ok, err2 = downloadFile(url, path)

        local okX = bx + bw - 8
        term.setCursorPos(okX, listY + listIdx - 1)
        if ok then
            set(colors.black, colors.lime)
            term.write("[OK]")
            success = success + 1
        else
            set(colors.black, colors.red)
            term.write("[ERR]")
            failed = failed + 1
            table.insert(logLines, file .. ": " .. tostring(err2))
        end
        reset()

        term.setCursorPos(pbX + pbW - 6, pbY)
        set(colors.black, colors.white)
        term.write(string.format("%3d%%", pct))
        reset()

        sleep(0.05)
    end

    -- Download server script separately (goes to root)
    do
        local url = SERVER_URL
        local path = "/" .. SERVER_FILE
        term.setCursorPos(bx + 3, by + bh - 5)
        set(colors.black, colors.lightGray)
        term.write("Server: " .. SERVER_FILE)
        local ok2, err2 = downloadFile(url, path)
        term.setCursorPos(bx + bw - 8, by + bh - 5)
        if ok2 then
            set(colors.black, colors.lime)
            term.write("[OK]")
            success = success + 1
        else
            set(colors.black, colors.red)
            term.write("[ERR]")
            failed = failed + 1
            table.insert(logLines, SERVER_FILE .. ": " .. tostring(err2))
        end
        reset()
        progress(pbX, pbY, pbW, total, total)
    end

    local statusY = by + bh - 4
    term.setCursorPos(bx + 3, statusY)
    if failed == 0 then
        set(colors.black, colors.lime)
        term.write("Install complete! ")
        set(colors.black, colors.white)
        term.write(success .. "/" .. total .. " files.")
    else
        set(colors.black, colors.red)
        term.write("Failed: " .. failed .. "  See errors below.")
        for j, line in ipairs(logLines) do
            if j <= 2 then
                term.setCursorPos(bx + 3, statusY + j)
                set(colors.black, colors.red)
                term.write(line:sub(1, bw - 6))
            end
        end
    end
    reset()

    if failed == 0 then
        term.setCursorPos(bx + 3, by + bh - 1)
        set(colors.black, colors.lightGray)
        term.write("Press any key to start CCOS...")
        reset()
        os.pullEvent("key")
        cls()
        shell.run("/ccos/init.lua")
    else
        term.setCursorPos(bx + 3, by + bh - 1)
        set(colors.black, colors.lightGray)
        term.write("Press any key to exit...")
        reset()
        os.pullEvent("key")
    end
end

reset() cls()
local ok, err = pcall(main)
if not ok then
    print("INSTALLER ERROR:")
    print(err)
    sleep(3)
end
reset()
