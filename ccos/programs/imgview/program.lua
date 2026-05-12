-- CCOS Program: Image Viewer
-- View .nfp (NPaintPro) and pixel art files
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local function appImageViewer(fp)
    fp = fp or "/image.nfp"
    local pixels = {}
    local imgW, imgH = 0, 0

    local function loadImage()
        if not fs.exists(fp) then return end
        local f = fs.open(fp, "r")
        if not f then return end
        local y = 1
        while true do
            local line = f.readLine()
            if not line then break end
            local row = {}
            for x = 1, #line do
                local ch = line:sub(x,x)
                local color = K.BLACK
                if ch == "0" then color = K.WHITE
                elseif ch == "1" then color = K.BLACK
                elseif ch == "2" then color = K.GRAY
                elseif ch == "3" then color = K.LGRAY
                elseif ch == "4" then color = K.DGRAY
                elseif ch == "5" then color = K.BLUE
                elseif ch == "6" then color = K.DBLUE
                elseif ch == "7" then color = K.CYAN
                elseif ch == "8" then color = K.LIGHT_BLUE
                elseif ch == "9" then color = K.GREEN
                elseif ch == "a" then color = K.DARK_GREEN
                elseif ch == "b" then color = K.RED
                elseif ch == "c" then color = K.DARK_RED
                elseif ch == "d" then color = K.YELLOW
                elseif ch == "e" then color = K.ORANGE
                elseif ch == "f" then color = K.BROWN
                elseif ch == "g" then color = K.PURPLE
                elseif ch == "h" then color = K.PINK
                end
                table.insert(row, color)
            end
            table.insert(pixels, row)
            imgW = math.max(imgW, #row)
            imgH = imgH + 1
            y = y + 1
        end
        f.close()
    end

    loadImage()

    local scale = 1
    local ox, oy = 0, 0

    local wx, wy, ww, wh = D.fitWin(200, 160)
    local w = D.createWindow("Image: " .. fp, wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,36,14,false)
        R.drawText(cx+2,cy+3,"Open",K.BLACK,K.GRAY)
        R.drawButton(cx+42,cy,36,14,false)
        R.drawText(cx+46,cy+3,"+",K.BLACK,K.GRAY)
        R.drawButton(cx+80,cy,36,14,false)
        R.drawText(cx+84,cy+3,"-",K.BLACK,K.GRAY)
        R.drawText(cx+120,cy+3,imgW.."x"..imgH.." @"..scale.."x",K.BLACK,K.GRAY)

        local viewX, viewY = cx+2, cy+16
        local viewW, viewH = cw-4, ch-28

        if #pixels == 0 then
            R.drawText(viewX+10, viewY+10, "No image loaded", K.BLACK, K.GRAY)
            return
        end

        for y = 1, math.min(imgH, math.floor(viewH/scale)) do
            for x = 1, math.min(imgW, math.floor(viewW/scale)) do
                local row = pixels[y + oy]
                if row then
                    local color = row[x + ox] or K.BLACK
                    R.fillRect(viewX + (x-1)*scale, viewY + (y-1)*scale, scale, scale, color)
                end
            end
        end
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 then
            if mx>=0 and mx<36 then
                D.inputDialog("Open Image", "Enter path:", "/image.nfp", function(path)
                    if path then fp=path; pixels={}; imgW=0; imgH=0; loadImage(); D.markContentDirty(w) end
                end)
            elseif mx>=42 and mx<78 then scale=math.min(4,scale+1); D.markContentDirty(w)
            elseif mx>=80 and mx<116 then scale=math.max(1,scale-1); D.markContentDirty(w) end
        end
    end

    w.onKey = function(_,k)
        -- Image Viewer is view-only; close only via X button
    end
end

return {name = "Image View", icon = "img", run = appImageViewer}
