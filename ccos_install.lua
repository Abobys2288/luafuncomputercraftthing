--[[
    CCOS Installer v3 — STYLISH
    ============================
    W95-style text installer with progress bar, colored log and logo.
    Works in regular ComputerCraft terminal (no CC:Graphics needed).
]]

local REPO = "Abobys2288/luafuncomputercraftthing"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/"

local FILES = {
    "init.lua",
    "render.lua",
    "desktop.lua",
    "api.lua",
    "kernel.lua",
    "gui.lua",
}

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

-- Fill area with bg color (color mode only)
local function fill(x, y, w2, h2, bg)
    if not C then return end
    set(bg)
    for row = 0, h2 - 1 do
        term.setCursorPos(x, y + row)
        term.write(string.rep(" ", w2))
    end
end

-- Draw box with border chars
local function box(x, y, bw, bh, bg, border, fg)
    set(border, fg or colors.white)
    -- top
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", bw - 2) .. "+")
    -- bottom
    term.setCursorPos(x, y + bh - 1)
    term.write("+" .. string.rep("-", bw - 2) .. "+")
    -- sides
    for i = 1, bh - 2 do
        term.setCursorPos(x, y + i)
        term.write("|" .. string.rep(" ", bw - 2) .. "|")
    end

    if bg and C then
        fill(x + 1, y + 1, bw - 2, bh - 2, bg)
    end
end

-- Colored progress bar inside a box
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
    local f = fs.open(path, "w")
    if not f then return false, "Write failed" end
    f.write(c)
    f.close()
    return true
end

local function main()
    cls()

    -- Dark background for whole screen
    if C then fill(1, 1, W, H, colors.black) end

    -- Main dialog box
    local bw = math.min(58, W - 4)
    local bh = math.min(20, H - 4)
    local bx = math.floor((W - bw) / 2) + 1
    local by = math.floor((H - bh) / 2) + 1

    box(bx, by, bw, bh, colors.black, colors.cyan, colors.white)

    -- Logo / Title
    set(colors.black, colors.cyan)
    term.setCursorPos(bx + 2, by + 1)
    term.write("CCOS v3 — Setup Utility")
    set(colors.black, colors.lightGray)
    term.setCursorPos(bx + 2, by + 2)
    term.write("github.com/" .. REPO)
    reset()

    -- Divider line
    term.setCursorPos(bx + 2, by + 3)
    set(colors.black, colors.gray)
    term.write(string.rep("-", bw - 4))
    reset()

    -- Progress bar empty
    local pbX = bx + 3
    local pbY = by + 5
    local pbW = bw - 6
    progress(pbX, pbY, pbW, 0, #FILES)

    -- File list area
    local fileX = bx + 3
    local fileY = by + 7
    local maxFiles = math.min(#FILES, 8)
    for i = 1, #FILES do
        term.setCursorPos(fileX, fileY + i - 1)
        reset()
        term.write("  " .. FILES[i])
    end

    sleep(0.2)

    if not http then
        term.setCursorPos(bx + 3, by + bh - 2)
        set(colors.black, colors.red)
        term.write("ERROR: HTTP API not enabled!")
        reset()
        sleep(5)
        return
    end

    if not fs.exists("/ccos") then
        fs.makeDir("/ccos")
    end

    local success, failed = 0, 0
    local logLines = {}

    for i, file in ipairs(FILES) do
        -- Update progress bar
        progress(pbX, pbY, pbW, i, #FILES)

        -- Highlight current file
        term.setCursorPos(fileX, fileY + i - 1)
        set(colors.black, colors.yellow)
        term.write("> " .. file)
        reset()

        -- Scroll if too many files
        if i > maxFiles then
            -- Shift text up one line (simple scroll effect)
            for j = 1, maxFiles - 1 do
                term.setCursorPos(fileX, fileY + j - 1)
                reset()
                local idx = i - maxFiles + j + 1
                local f2 = FILES[idx] or ""
                if f2 == file then
                    set(colors.black, colors.yellow)
                    term.write("> " .. f2)
                else
                    term.write("  " .. f2)
                end
                reset()
            end
        end

        -- Download
        local url = BASE_URL .. file
        local path = "/ccos/" .. file
        local ok, err2 = downloadFile(url, path)

        -- Result after the file name
        local resX = fileX + math.max(20, pbW - 12)
        term.setCursorPos(resX, fileY + math.min(i, maxFiles) - 1)
        if ok then
            set(colors.black, colors.green)
            term.write("[OK]  ")
            success = success + 1
        else
            set(colors.black, colors.red)
            term.write("[FAIL]")
            failed = failed + 1
            table.insert(logLines, file .. ": " .. tostring(err2))
        end
        reset()

        sleep(0.05)
    end

    -- Final status
    local statusY = by + bh - 3
    term.setCursorPos(bx + 3, statusY)
    if failed == 0 then
        set(colors.black, colors.lime)
        term.write("Installation complete! ")
        set(colors.black, colors.white)
        term.write(success .. " files installed.")
    else
        set(colors.black, colors.red)
        term.write("Some files failed: " .. failed)
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

reset()
cls()
local ok, err = pcall(main)
if not ok then
    print("INSTALLER ERROR:")
    print(err)
    sleep(3)
end
reset()
