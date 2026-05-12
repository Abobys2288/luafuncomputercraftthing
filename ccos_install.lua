--[[
    CCOS Installer v4 — MODULAR
    ============================
    Downloads all CCOS files including modular programs and network driver.
]]

local REPO = "Abobys2288/luafuncomputercraftthing"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/"

local FILES = {
    -- Core
    "init.lua",
    "render.lua",
    "desktop.lua",
    "api.lua",
    "kernel.lua",
    "gui.lua",
    -- Programs
    "programs/fm/program.lua",
    "programs/edit/program.lua",
    "programs/settings/program.lua",
    "programs/shell/program.lua",
    "programs/calc/program.lua",
    "programs/tasks/program.lua",
    -- Drivers
    "drivers/net.lua",
}

-- ============================================================
-- UI
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
    reset() term.clear() term.setCursorPos(1, 1)
end

local function fill(x, y, w2, h2, bg)
    if not C then return end
    set(bg)
    for row = 0, h2 - 1 do
        term.setCursorPos(x, y + row)
        term.write(string.rep(" ", w2))
    end
end

local function box(x, y, bw, bh, bg, border, fg)
    set(border, fg or colors.white)
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", bw - 2) .. "+")
    term.setCursorPos(x, y + bh - 1)
    term.write("+" .. string.rep("-", bw - 2) .. "+")
    for i = 1, bh - 2 do
        term.setCursorPos(x, y + i)
        term.write("|" .. string.rep(" ", bw - 2) .. "|")
    end
    if bg and C then fill(x+1, y+1, bw-2, bh-2, bg) end
end

local function progress(x, y, pw, done, total)
    done = math.min(done, total)
    local filled = math.floor((done / total) * pw)
    if C then
        term.setCursorPos(x, y)
        set(colors.cyan, colors.white)
        term.write(string.rep(" ", filled))
        set(colors.gray, colors.lightGray)
        term.write(string.rep(" ", pw - filled))
    else
        term.setCursorPos(x, y)
        term.write("[")
        term.write(string.rep("#", filled))
        term.write(string.rep("-", pw - filled))
        term.write("]")
    end
    reset()
end

-- ============================================================
-- LOGIC
-- ============================================================
local function downloadFile(url, path)
    local response = http.get(url)
    if not response then return false, "HTTP GET failed" end
    local c = response.readAll()
    response.close()
    -- Ensure parent directory exists
    local dir = path:match("(.+)/[^/]+")
    if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w")
    if not f then return false, "Write failed" end
    f.write(c)
    f.close()
    return true
end

local function main()
    cls()
    if C then fill(1, 1, W, H, colors.black) end

    local bw = math.min(60, W - 4)
    local bh = math.min(22, H - 4)
    local bx = math.floor((W - bw) / 2) + 1
    local by = math.floor((H - bh) / 2) + 1

    box(bx, by, bw, bh, colors.black, colors.cyan, colors.white)
    set(colors.black, colors.cyan)
    term.setCursorPos(bx + 2, by + 1)
    term.write("CCOS v3 Modular — Setup")
    set(colors.black, colors.lightGray)
    term.setCursorPos(bx + 2, by + 2)
    term.write("github.com/" .. REPO)
    reset()

    term.setCursorPos(bx + 2, by + 3)
    set(colors.black, colors.gray)
    term.write(string.rep("-", bw - 4))
    reset()

    local pbX = bx + 3
    local pbY = by + 5
    local pbW = bw - 6

    local fileX = bx + 3
    local fileY = by + 8

    if not http then
        term.setCursorPos(bx + 3, by + bh - 2)
        set(colors.black, colors.red)
        term.write("ERROR: HTTP API not enabled!")
        reset() sleep(5)
        return
    end

    -- Create directories
    if not fs.exists("/ccos") then fs.makeDir("/ccos") end
    if not fs.exists("/ccos/programs") then fs.makeDir("/ccos/programs") end
    if not fs.exists("/ccos/drivers") then fs.makeDir("/ccos/drivers") end
    if not fs.exists("/ccos/programs/fm") then fs.makeDir("/ccos/programs/fm") end
    if not fs.exists("/ccos/programs/edit") then fs.makeDir("/ccos/programs/edit") end
    if not fs.exists("/ccos/programs/settings") then fs.makeDir("/ccos/programs/settings") end
    if not fs.exists("/ccos/programs/shell") then fs.makeDir("/ccos/programs/shell") end
    if not fs.exists("/ccos/programs/calc") then fs.makeDir("/ccos/programs/calc") end
    if not fs.exists("/ccos/programs/tasks") then fs.makeDir("/ccos/programs/tasks") end

    local success, failed = 0, 0
    local logLines = {}
    local maxFiles = math.min(#FILES, 10)

    for i, file in ipairs(FILES) do
        progress(pbX, pbY, pbW, i, #FILES)

        local displayName = file
        if #displayName > 30 then displayName = "..." .. displayName:sub(-27) end

        local linePos = math.min(i, maxFiles - 1)
        local resX = bx + math.max(20, pbW - 12)

        term.setCursorPos(fileX, fileY + linePos - 1)
        set(colors.black, colors.lightGray)
        term.write(displayName)
        reset()

        local url = BASE_URL .. file
        local path = "/ccos/" .. file
        local ok, err2 = downloadFile(url, path)

        term.setCursorPos(resX, fileY + linePos - 1)
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

        if i > maxFiles - 1 then
            -- Scroll effect: move items up
            for j = 1, math.min(maxFiles - 1, #FILES - i + 1) do
                local src = FILES[i - maxFiles + 1 + j] or ""
                if #src > 30 then src = "..." .. src:sub(-27) end
                term.setCursorPos(fileX, fileY + j - 1)
                reset()
                term.write(src)
                reset()
            end
        end

        sleep(0.05)
    end

    local statusY = by + bh - 4
    term.setCursorPos(bx + 3, statusY)
    if failed == 0 then
        set(colors.black, colors.lime)
        term.write("Installation complete! ")
        set(colors.black, colors.white)
        term.write(success .. " files.")
    else
        set(colors.black, colors.red)
        term.write("Failed: " .. failed)
        for j, line in ipairs(logLines) do
            if j <= 2 then
                term.setCursorPos(bx + 3, statusY + j)
                set(colors.black, colors.red)
                term.write(line)
            end
        end
    end
    reset()

    if failed == 0 then
        term.setCursorPos(bx + 3, by + bh - 1)
        term.write("Start now? (Y/n): ")
        local ans = read()
        if ans == "" or ans:lower() == "y" or ans:lower() == "yes" then
            cls()
            shell.run("/ccos/init.lua")
        end
    else
        sleep(4)
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
