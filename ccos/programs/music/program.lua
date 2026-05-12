-- CCOS Program: Music Player
-- Play .nbs or simple note sequences via speaker
local D = _G._desktop
local R = _G.ccos_render
local K = {BLACK=0,WHITE=1,GRAY=2,LGRAY=3,DGRAY=4,BLUE=5,DBLUE=6,DESKTOP=30}

local NOTES = {
    ["1"]={note="harp",pitch=0.5}, ["2"]={note="harp",pitch=0.53},
    ["3"]={note="harp",pitch=0.56}, ["4"]={note="harp",pitch=0.6},
    ["5"]={note="harp",pitch=0.63}, ["6"]={note="harp",pitch=0.67},
    ["7"]={note="harp",pitch=0.7}, ["8"]={note="harp",pitch=0.75},
    ["9"]={note="harp",pitch=0.8}, ["0"]={note="harp",pitch=0.85},
    ["q"]={note="flute",pitch=0.5}, ["w"]={note="flute",pitch=0.6},
    ["e"]={note="flute",pitch=0.7}, ["r"]={note="flute",pitch=0.8},
    ["t"]={note="flute",pitch=0.9},
}

local function appMusicPlayer()
    local speaker = peripheral.find("speaker")
    local playlist = {}
    local current = 1
    local playing = false
    local status = speaker and "Ready" or "No speaker!"

    local function loadPlaylist()
        playlist = {}
        if fs.isDir("/music") then
            for _,f in ipairs(fs.list("/music")) do
                if f:match("%.nbs$") or f:match("%.txt$") then table.insert(playlist,f) end
            end
        end
    end

    local function playNote(noteData)
        if not speaker then return end
        pcall(function()
            speaker.playNote(noteData.note, 1, noteData.pitch)
        end)
    end

    local wx, wy, ww, wh = D.fitWin(200, 120)
    local w = D.createWindow("Music", wx, wy, ww, wh)

    w.onDraw = function(_,cx,cy,cw,ch)
        R.drawButton(cx,cy,36,14,false)
        R.drawText(cx+2,cy+3,playing and "Stop" or "Play",K.BLACK,K.GRAY)
        R.drawButton(cx+42,cy,36,14,false)
        R.drawText(cx+46,cy+3,"Next",K.BLACK,K.GRAY)
        R.drawText(cx+84,cy+3,status,K.BLACK,K.GRAY)

        local song = playlist[current] or "(none)"
        R.drawText(cx+2,cy+16,"Now: "..song,K.DBLUE,K.GRAY)

        R.drawText(cx+2,cy+30,"Keyboard:",K.BLACK,K.GRAY)
        R.drawText(cx+2,cy+42,"1-9,0 = notes",K.BLACK,K.GRAY)
        R.drawText(cx+2,cy+54,"q-t = flute",K.BLACK,K.GRAY)
        R.drawText(cx+2,cy+66,"Space = stop",K.BLACK,K.GRAY)
    end

    w.onClick = function(_,mx,my)
        if my>=0 and my<14 then
            if mx>=0 and mx<36 then
                playing = not playing
                if playing then status = "Playing..." else status = "Stopped" end
                D.markContentDirty(w)
            elseif mx>=42 and mx<78 then
                current = current + 1; if current > #playlist then current = 1 end
                status = "Next: " .. (playlist[current] or "none")
                D.markContentDirty(w)
            end
        end
    end

    w.onKey = function(_,k,ch)
        if ch then
            local note = NOTES[ch]
            if note then playNote(note); status = "Note: "..ch; D.markContentDirty(w)
            else status = "Key: "..ch; D.markContentDirty(w) end
        elseif k == keys.space then
            playing = false; status = "Stopped"; D.markContentDirty(w)
        -- Music Player closes only via X button
        end
    end

    loadPlaylist()
end

return {name = "Music", icon = "music", run = appMusicPlayer}
