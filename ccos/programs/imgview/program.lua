-- CCOS Program: Image Viewer
-- Views .nfp, .nfp256, .nfpc, .nfpa images via the shared CCOS image library.
local API = _G.ccos_api
local D = _G._desktop
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local P = R.PAL

local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,DBLUE=19,RED=11,CYAN=7}

local LARGE_FILE_BYTES = 5 * 1024 * 1024
local HUGE_COMPRESSED_BYTES = 32 * 1024 * 1024
local MAX_DECODE_PIXELS = 1200000
local MAX_ANIM_DECODE_PIXELS = 5200000
local SAFE_PREVIEW_ROWS = 96

local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
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

local function safeSize(path)
    local ok, size = pcall(fs.getSize, path)
    return ok and tonumber(size) or 0
end

local function formatSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < 1024 then return tostring(bytes) .. " B" end
    if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.2f MB", bytes / (1024 * 1024))
end

local function img()
    return API and API.imageModule and API.imageModule()
end

-- Partial read of a large raw image (first N rows) for safe preview.
local function loadLargeRawPreview(path, ext)
    local image = img()
    if not image then return false end
    local f = fs.open(path, "r")
    if not f then return false end
    local rows, maxW, count = {}, 0, 0
    while count < SAFE_PREVIEW_ROWS do
        local line = f.readLine()
        if not line then break end
        if line ~= "" then
            local row = (ext == "nfp256") and image.parseNfp256Line(line) or image.parseNfp32Line(line)
            if #row > 0 then
                rows[#rows + 1] = row
                maxW = math.max(maxW, #row)
                count = count + 1
            end
        end
    end
    f.close()
    if #rows == 0 or maxW == 0 then return false end
    return rows, maxW, #rows
end

local function codecName(header)
    local c = header and header.codec or ""
    if c == "" then c = "RLE" end
    return c
end

local function appImageViewer(initialPath)
    if not API or not R then return end

    local fp = initialPath
    local pixels, imgW, imgH = {}, 0, 0
    local status = "Open an image file"
    local formatName = ""
    local scale, ox, oy = 1, 0, 0
    local fileSize = 0
    local largeMode = false
    local infoLines = {}

    -- Animation state
    local animFrames, animFrame, animDelay = {}, 1, 0
    local animTask, animTimer, isAnimation = nil, nil, false
    local win

    local function stopAnimation()
        if animTask then
            for i, t in ipairs(D.bgTasks or {}) do
                if t == animTask then table.remove(D.bgTasks, i); break end
            end
            animTask = nil
        end
        if animTimer then pcall(os.cancelTimer, animTimer); animTimer = nil end
    end

    local function startAnimation()
        if not isAnimation or #animFrames <= 1 then return end
        if animTask then return end
        animTask = function(e, a)
            if e == "timer" and a == animTimer then
                animFrame = animFrame + 1
                if animFrame > #animFrames then animFrame = 1 end
                pixels = animFrames[animFrame]
                status = imgW .. "x" .. imgH .. " " .. formatName .. " F" .. animFrame .. "/" .. #animFrames
                if win then API.redrawContent(win) end
                animTimer = os.startTimer(animDelay)
            end
        end
        D.bgTasks = D.bgTasks or {}
        table.insert(D.bgTasks, animTask)
        animTimer = os.startTimer(animDelay)
    end

    local function setInfoOnly(path, header, reason)
        pixels = {}
        largeMode = true
        infoLines = {}
        imgW = header and header.w or 0
        imgH = header and header.h or 0
        formatName = header and header.kind or "Image"
        if header and header.kind == "NFPA" then
            infoLines[#infoLines + 1] = "Animation: " .. header.w .. "x" .. header.h .. " x" .. header.frames
            infoLines[#infoLines + 1] = "Palette: " .. header.mode .. "  Codec: " .. codecName(header)
            infoLines[#infoLines + 1] = "Delay: " .. header.delay .. " ms"
        elseif header and header.kind == "NFPC" then
            infoLines[#infoLines + 1] = "Image: " .. header.w .. "x" .. header.h
            infoLines[#infoLines + 1] = "Palette: " .. header.mode .. "  Codec: " .. codecName(header)
        end
        infoLines[#infoLines + 1] = "File: " .. formatSize(fileSize)
        infoLines[#infoLines + 1] = reason or "Safe preview mode"
        infoLines[#infoLines + 1] = path
        status = (header and (header.kind .. " " .. header.w .. "x" .. header.h) or "Large image") .. " safe preview"
        if API and API.notify then API.notify("Image Viewer", "Opened in safe preview mode", "info", 5) end
        return true
    end

    local function loadImage(path, quiet)
        stopAnimation()
        pixels, imgW, imgH = {}, 0, 0
        formatName = ""
        ox, oy = 0, 0
        fileSize = 0
        largeMode = false
        infoLines = {}
        animFrames, animFrame, animDelay = {}, 1, 0
        isAnimation = false

        if not path or path == "" then
            fp = nil; status = "No image selected"; return false
        end
        fp = path
        if not fs.exists(fp) then
            status = "Not found: " .. fp
            if not quiet then API.showError("Image Viewer", "File not found: " .. fp) end
            return false
        end
        if fs.isDir(fp) then
            status = "Path is a folder"
            if not quiet then API.showError("Image Viewer", "Folder selected: " .. fp) end
            return false
        end

        local ext = (fp:match("%.([^%.]+)$") or ""):lower()
        fileSize = safeSize(fp)
        local header = API.detectImage(fp)
        local image = img()

        -- Guard: oversized images -> safe preview (no full decode)
        if header then
            local total = (header.w or 0) * (header.h or 0) * math.max(1, header.frames or 1)
            local maxPixels = header.kind == "NFPA" and MAX_ANIM_DECODE_PIXELS or MAX_DECODE_PIXELS
            if total > maxPixels then
                return setInfoOnly(fp, header, "Decoded pixels exceed safe limit")
            end
            if fileSize >= HUGE_COMPRESSED_BYTES then
                return setInfoOnly(fp, header, "Compressed file is over 32 MB")
            end
        elseif fileSize >= LARGE_FILE_BYTES and (ext == "nfp" or ext == "nfp256") and image then
            local rows, w, h = loadLargeRawPreview(fp, ext)
            if rows then
                pixels = rows; imgW = w; imgH = h; largeMode = true
                infoLines = {
                    "Large raw image: " .. formatSize(fileSize),
                    "Showing first " .. #rows .. " rows only",
                    "Convert to .nfpc C3 for full viewing",
                    fp,
                }
                formatName = ext == "nfp256" and "NFP256 preview" or "NFP preview"
                status = imgW .. "x" .. imgH .. " " .. formatName
                return true
            end
        end

        if not image then
            status = "Image library unavailable"
            if not quiet then API.showError("Image Viewer", status) end
            return false
        end

        -- Animation
        if header and header.kind == "NFPA" then
            local ok, frames, fw, fh, delay = pcall(image.loadAnimation, fp)
            if ok and frames and #frames > 0 then
                animFrames = frames; animFrame = 1
                pixels = animFrames[1]
                imgW = fw or 0; imgH = fh or #pixels
                animDelay = (delay or 100) / 1000
                isAnimation = true
                formatName = "NFPA " .. codecName(header)
                startAnimation()
            else
                status = "Invalid NFPA: " .. tostring(frames)
                if not quiet then API.showError("Image Viewer", status) end
                return false
            end
        else
            -- Static (NFP / NFP256 / NFPC)
            local ok, result, w, h = pcall(image.loadFile, fp)
            if ok and result then
                pixels = result; imgW = w or 0; imgH = h or #pixels
                if header and header.kind == "NFPC" then
                    formatName = "NFPC " .. codecName(header)
                else
                    formatName = (header and header.mode == 256) and "256-color" or "32-color"
                end
            else
                status = "Invalid image: " .. tostring(w)
                if not quiet then API.showError("Image Viewer", status) end
                return false
            end
        end

        if imgH == 0 or imgW == 0 then
            status = "Empty or invalid image"
            if not quiet then API.showError("Image Viewer", "No pixels found in: " .. fp) end
            return false
        end

        status = imgW .. "x" .. imgH .. " " .. formatName
        if isAnimation then status = status .. " F" .. animFrame .. "/" .. #animFrames end
        return true
    end

    local wx, wy, ww, wh = API.fitWindow(260, 180)
    win = API.window("Image Viewer", wx, wy, ww, wh)
    if not win then return end

    if fp then
        win.title = "Image: " .. API.getFileName(fp)
        loadImage(fp, true)
    end

    local function maxOffsets(cw, ch)
        local viewW = math.max(1, cw - 4)
        local viewH = math.max(1, ch - 42)
        return math.max(0, imgW - math.floor(viewW / scale)), math.max(0, imgH - math.floor(viewH / scale))
    end

    local function clampPan(cw, ch)
        local maxOX, maxOY = maxOffsets(cw, ch)
        ox = math.max(0, math.min(ox, maxOX))
        oy = math.max(0, math.min(oy, maxOY))
    end

    local function openDialog()
        stopAnimation()
        if API.chooseFile then
            API.chooseFile({title="Open Image", path="/", extensions={"nfp","nfp256","nfpc","nfpa"}}, function(path)
                if path and path ~= "" then
                    if loadImage(path, false) then win.title = "Image: " .. API.getFileName(path) end
                    API.redrawContent(win)
                end
            end)
        else
            D.inputDialog("Open Image", "Path:", fp or "/tools/smile.nfp", function(path)
                if path and path ~= "" then
                    if loadImage(path, false) then win.title = "Image: " .. API.getFileName(path) end
                    API.redrawContent(win)
                end
            end)
        end
    end

    local function drawImageViewport(viewX, viewY, viewW, viewH)
        local maxY = math.min(imgH - oy, math.floor(viewH / scale))
        local maxX = math.min(imgW - ox, math.floor(viewW / scale))
        for y = 1, maxY do
            local row = pixels[y + oy]
            if row then
                local screenY = viewY + (y - 1) * scale
                local x = 1
                while x <= maxX do
                    local color = row[x + ox]
                    if color == nil then
                        x = x + 1
                    else
                        local runEnd = x + 1
                        while runEnd <= maxX and row[runEnd + ox] == color do runEnd = runEnd + 1 end
                        R.fillRect(viewX + (x - 1) * scale, screenY, (runEnd - x) * scale, scale, color)
                        x = runEnd
                    end
                end
            end
        end
    end

    win.onDraw = function(_, cx, cy, cw, ch)
        button(cx, cy, math.min(42, cw), "Open")
        if cw >= 78 then button(cx + 46, cy, 28, "+") end
        if cw >= 110 then button(cx + 78, cy, 28, "-") end
        if isAnimation then
            if cw >= 182 then button(cx + 112, cy, 28, "<") end
            if cw >= 214 then button(cx + 144, cy, 28, ">") end
            if cw >= 246 then button(cx + 176, cy, 28, animTask and "||" or "|>") end
            if cw >= 150 then drawText(cx + 210, cy + 3, status, K.DBLUE, K.GRAY, math.max(0, cw - 214)) end
        else
            if cw >= 150 then drawText(cx + 112, cy + 3, status, K.DBLUE, K.GRAY, cw - 116) end
        end

        local viewX, viewY = cx + 2, cy + 24
        local viewW, viewH = math.max(1, cw - 4), math.max(1, ch - 38)
        R.fillRect(viewX, viewY, viewW, viewH, K.BLACK)

        if #pixels == 0 then
            if largeMode and #infoLines > 0 then
                drawText(viewX + 4, viewY + 4, "Safe preview", K.CYAN, K.BLACK, viewW - 8)
                for i, line in ipairs(infoLines) do
                    local yy = viewY + 16 + (i - 1) * 10
                    if yy > viewY + viewH - 10 then break end
                    drawText(viewX + 4, yy, line, i == #infoLines and K.DGRAY or K.LGRAY, K.BLACK, viewW - 8)
                end
            else
                drawText(viewX + 4, viewY + 4, "No image loaded.", K.WHITE, K.BLACK, viewW - 8)
                drawText(viewX + 4, viewY + 16, "Open .nfp/.nfp256/.nfpc/.nfpa", K.LGRAY, K.BLACK, viewW - 8)
            end
            drawText(cx + 4, cy + ch - 10, clip(status, cw - 8), K.DGRAY, K.GRAY)
            return
        end

        clampPan(cw, ch)
        drawImageViewport(viewX, viewY, viewW, viewH)
        local suffix = largeMode and "  SAFE" or ""
        drawText(cx + 4, cy + ch - 10, "Scale " .. scale .. "x  " .. status .. suffix, K.DGRAY, K.GRAY, cw - 8)
    end

    win.onClick = function(_, mx, my)
        if my >= 0 and my < 14 then
            if mx >= 0 and mx < 42 then openDialog()
            elseif mx >= 46 and mx < 74 then scale = math.min(8, scale + 1); API.redrawContent(win)
            elseif mx >= 78 and mx < 106 then scale = math.max(1, scale - 1); API.redrawContent(win)
            elseif isAnimation then
                if mx >= 112 and mx < 140 then
                    animFrame = animFrame - 1
                    if animFrame < 1 then animFrame = #animFrames end
                    pixels = animFrames[animFrame]
                    status = imgW .. "x" .. imgH .. " " .. formatName .. " F" .. animFrame .. "/" .. #animFrames
                    API.redrawContent(win)
                elseif mx >= 144 and mx < 172 then
                    animFrame = animFrame + 1
                    if animFrame > #animFrames then animFrame = 1 end
                    pixels = animFrames[animFrame]
                    status = imgW .. "x" .. imgH .. " " .. formatName .. " F" .. animFrame .. "/" .. #animFrames
                    API.redrawContent(win)
                elseif mx >= 176 and mx < 204 then
                    if animTask then stopAnimation() else startAnimation() end
                    API.redrawContent(win)
                end
            end
        end
    end

    win.onDrag = function(_, dx, dy)
        if #pixels == 0 then return end
        local step = math.max(1, math.floor(3 / scale))
        if dx > 0 then ox = ox - step elseif dx < 0 then ox = ox + step end
        if dy > 0 then oy = oy - step elseif dy < 0 then oy = oy + step end
        API.redrawContent(win)
    end

    win.onScroll = function(_, dir)
        if #pixels == 0 then return end
        local step = math.max(1, math.floor(8 / scale))
        if dir < 0 then oy = oy - step else oy = oy + step end
        API.redrawContent(win)
    end

    win.onKey = function(_, k, ch)
        local step = math.max(1, math.floor(4 / scale))
        if ch == "o" or ch == "O" then openDialog()
        elseif k == keys.escape then API.close(win)
        elseif k == keys.left then ox = ox - step; API.redrawContent(win)
        elseif k == keys.right then ox = ox + step; API.redrawContent(win)
        elseif k == keys.up then oy = oy - step; API.redrawContent(win)
        elseif k == keys.down then oy = oy + step; API.redrawContent(win)
        elseif k == keys.home then ox, oy = 0, 0; API.redrawContent(win)
        elseif k == keys.pageUp then scale = math.min(8, scale + 1); API.redrawContent(win)
        elseif k == keys.pageDown then scale = math.max(1, scale - 1); API.redrawContent(win)
        end
    end

    win.onClose = function() stopAnimation() end
end

return {name = "Image View", icon = "img", run = appImageViewer}
