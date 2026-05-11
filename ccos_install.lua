--[[
    CCOS Installer
    ==============
    Downloads all CCOS files from GitHub and installs them.
    Run: pastebin run <code>  or  ccos_install
]]

local REPO = "Abobys2288/luafuncomputercraftthing"
local BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/ccos/"

local FILES = {
    "init.lua",
    "render.lua",
    "desktop.lua",
    "api.lua",
}

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function printC(text, color)
    if term.isColor and term.isColor() then
        term.setTextColor(color or colors.white)
    end
    print(text)
    term.setTextColor(colors.white)
end

local function downloadFile(url, path)
    local response = http.get(url)
    if not response then
        return false, "Failed to download: " .. url
    end
    local content = response.readAll()
    response.close()

    local f = fs.open(path, "w")
    if not f then
        return false, "Failed to write: " .. path
    end
    f.write(content)
    f.close()
    return true
end

local function main()
    clear()
    printC("============================", colors.cyan)
    printC("  CCOS Installer v1.0", colors.cyan)
    printC("============================", colors.cyan)
    print("")

    -- Check if http is available
    if not http then
        printC("ERROR: HTTP API is not enabled!", colors.red)
        print("Enable it in ComputerCraft config or")
        print("use 'http_enable=true' in server.properties")
        return
    end

    -- Create ccos directory
    if not fs.exists("/ccos") then
        fs.makeDir("/ccos")
        printC("Created /ccos/ directory", colors.green)
    else
        printC("/ccos/ already exists, updating...", colors.yellow)
    end

    print("")
    print("Downloading files from GitHub...")
    print("")

    local success = 0
    local failed = 0

    for _, file in ipairs(FILES) do
        local url = BASE_URL .. file
        local path = "/ccos/" .. file

        write("  " .. file .. " ... ")

        local ok, err = downloadFile(url, path)
        if ok then
            printC("OK", colors.green)
            success = success + 1
        else
            printC("FAIL", colors.red)
            if err then print("    " .. err) end
            failed = failed + 1
        end

        sleep(0.1)
    end

    print("")
    printC("============================", colors.cyan)
    print("  Download complete!")
    print("  Success: " .. success .. " | Failed: " .. failed)
    printC("============================", colors.cyan)
    print("")

    if failed == 0 then
        printC("CCOS installed successfully!", colors.green)
        print("")
        print("Run with: ccos/init")
        print("")

        write("Start CCOS now? (Y/n): ")
        local answer = read()
        if answer == "" or answer:lower() == "y" or answer:lower() == "yes" then
            print("")
            printC("Starting CCOS...", colors.cyan)
            sleep(0.5)
            shell.run("/ccos/init.lua")
        end
    else
        printC("Some files failed to download.", colors.red)
        print("Check your internet connection and try again.")
    end
end

-- Run installer
local ok, err = pcall(main)
if not ok then
    printC("INSTALLER ERROR:", colors.red)
    print(err)
end
