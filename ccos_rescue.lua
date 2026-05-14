-- CCOS disk rescue utility.
-- Run with:
-- wget run https://raw.githubusercontent.com/Abobys2288/luafuncomputercraftthing/main/ccos_rescue.lua

local INSTALL_URL = "https://raw.githubusercontent.com/Abobys2288/luafuncomputercraftthing/main/ccos_install.lua"

local function fmt(bytes)
    if bytes == nil then return "unknown" end
    if bytes == "unlimited" then return "unlimited" end
    bytes = tonumber(bytes)
    if not bytes then return "unknown" end
    if bytes < 1024 then return tostring(bytes) .. " B" end
    if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.2f MB", bytes / (1024 * 1024))
end

local function getFree(path)
    local ok, value = pcall(fs.getFreeSpace, path or "/")
    if ok then return value end
    return nil
end

local function getCapacity(path)
    if not fs.getCapacity then return nil end
    local ok, value = pcall(fs.getCapacity, path or "/")
    if ok then return value end
    return nil
end

local function join(base, name)
    if base == "/" then return "/" .. name end
    return base .. "/" .. name
end

local function scan(path, out)
    out = out or {}
    local okDir, isDir = pcall(fs.isDir, path)
    if not okDir then return out, 0 end

    if isDir then
        local total = 0
        local okList, list = pcall(fs.list, path)
        if okList and list then
            for _, name in ipairs(list) do
                local child = join(path, name)
                local _, size = scan(child, out)
                total = total + size
            end
        end
        out[#out + 1] = {path = path, size = total, dir = true}
        return out, total
    end

    local okSize, size = pcall(fs.getSize, path)
    size = okSize and tonumber(size) or 0
    out[#out + 1] = {path = path, size = size, dir = false}
    return out, size
end

local function printSpace()
    local free = getFree("/")
    local cap = getCapacity("/")
    print("Free:     " .. fmt(free))
    print("Capacity: " .. fmt(cap))
    if tonumber(free) == 0 and tonumber(cap) == 0 then
        print("Capacity is 0. Check CC:Tweaked computer_space_limit.")
    end
end

local function listLargest()
    local items = {}
    scan("/", items)
    table.sort(items, function(a, b)
        if a.size == b.size then return a.path < b.path end
        return a.size > b.size
    end)

    print("Largest paths:")
    local shown = 0
    for _, it in ipairs(items) do
        if it.path ~= "/rom" and it.path:sub(1, 5) ~= "/rom/" then
            shown = shown + 1
            local suffix = it.dir and "/" or ""
            print(string.format("%2d. %9s  %s%s", shown, fmt(it.size), it.path, suffix))
            if shown >= 18 then break end
        end
    end
    if shown == 0 then print("(nothing outside /rom)") end
end

local function wipeUserRoot()
    local okList, list = pcall(fs.list, "/")
    if not okList or not list then
        print("Cannot list /")
        return
    end

    local removed, failed = 0, 0
    for _, name in ipairs(list) do
        if name ~= "rom" and name:sub(1, 4) ~= "disk" then
            local path = "/" .. name
            local ok, err = pcall(fs.delete, path)
            if ok then
                removed = removed + 1
                print("Deleted " .. path)
            else
                failed = failed + 1
                print("FAILED " .. path .. ": " .. tostring(err))
            end
        end
    end
    print("Removed: " .. removed .. ", failed: " .. failed)
    printSpace()
end

local function runInstaller()
    if not http then
        print("HTTP API is disabled.")
        return
    end
    print("Running CCOS installer...")
    local ok, err = pcall(shell.run, "wget", "run", INSTALL_URL)
    if not ok then print("Installer failed: " .. tostring(err)) end
end

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

while true do
    clear()
    print("CCOS Disk Rescue")
    print("================")
    printSpace()
    print("")
    print("1 - List largest paths")
    print("2 - Wipe user files except /rom and /disk*")
    print("3 - Run CCOS installer")
    print("4 - Exit")
    print("")
    write("> ")
    local choice = read()

    if choice == "1" then
        print("")
        listLargest()
        print("")
        print("Press Enter...")
        read()
    elseif choice == "2" then
        print("")
        print("This deletes all user files in / except /rom and /disk*.")
        write("Type WIPE to continue: ")
        if read() == "WIPE" then
            wipeUserRoot()
        else
            print("Cancelled.")
        end
        print("")
        print("Press Enter...")
        read()
    elseif choice == "3" then
        clear()
        runInstaller()
        print("")
        print("Press Enter...")
        read()
    elseif choice == "4" then
        return
    end
end
