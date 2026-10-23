local VTUtils = require("KBMGB/System/VTUtils")
local WatchReward = require("KBMGB/Movie/WatchReward")
local WorldAudio = require("KBMGB/Movie/WorldAudio")

local JavaMoviePlayerApp = {}
JavaMoviePlayerApp.__index = JavaMoviePlayerApp

local function bridge()
    if type(KBMMoviePlayer) == "table" then return KBMMoviePlayer end
    if type(com) == "table" and type(com.knoxboxgb) == "table" then
        return com.knoxboxgb.KBMMoviePlayer
    end
    return nil
end

local function audioBridge()
    if type(KBMMovieAudio) == "table" then return KBMMovieAudio end
    if type(com) == "table" and type(com.knoxboxgb) == "table" then
        return com.knoxboxgb.KBMMovieAudio
    end
    return nil
end

function JavaMoviePlayerApp.new(_, args)
    local self = setmetatable({}, JavaMoviePlayerApp)
    self.args = args or {}
    self.kbm = nil
    self.err = nil
    self.signal = false
    self.powered = true
    self.volume = VTUtils.DEFAULT_VOLUME
    self._lastAudioSegment = -1
    self._activeSoundHandle = nil
    self.audio = nil
    self.recordingAudio = false
    self.watchReward = WatchReward.new()
    return self
end

function JavaMoviePlayerApp:_stopAudio()
    if self.audio then pcall(self.audio.stop) end
    if self._activeSoundHandle and getSoundManager then
        pcall(function() getSoundManager():stopUISound(self._activeSoundHandle) end)
    end
    self._activeSoundHandle = nil
    self._lastAudioSegment = -1
end

function JavaMoviePlayerApp:_applyVolume()
    local player = self.args.playerObj or (getPlayer and getPlayer())
    local volume = self.volume * WorldAudio.gain(self.args.tv, player)
    if self.audio then pcall(self.audio.setVolume, volume) end
    if self._activeSoundHandle then
        VTUtils.applyHandleVolume(self._activeSoundHandle, volume)
    end
end

function JavaMoviePlayerApp:_soundUpdate()
    if not self.kbm or not self.signal or (not self.args.soundName and not self.recordingAudio) then
        self:_stopAudio()
        return
    end
    local playing, finished, frame, fps = false, false, 1, 24
    pcall(function()
        playing = self.kbm.isPlaying() == true
        finished = self.kbm.isFinished() == true
        frame = tonumber(self.kbm.getCurrentFrame()) or 1
        fps = tonumber(self.kbm.getFps()) or 24
    end)
    if finished then self:_stopAudio(); return end
    if not playing then
        if self.audio and self._lastAudioSegment >= 0 then pcall(self.audio.pause)
        else self:_stopAudio() end
        return
    end
    local seconds = (frame - 1) / math.max(fps, 1)
    local chunkSeconds = tonumber(self.args.audioChunkSeconds) or 30
    local singleAudio = self.recordingAudio or self.args.audioLayout == "single"
    local segment = singleAudio and 0 or math.floor(seconds / chunkSeconds)
    local offsetMs = math.max(0, math.floor((seconds - segment * chunkSeconds) * 1000))
    if segment == self._lastAudioSegment then
        self:_applyVolume()
        if self.audio then
            local ok, actual = pcall(self.audio.getPositionMs)
            if ok and actual and math.abs(tonumber(actual) - offsetMs) > 350 then
                pcall(self.audio.seekMs, offsetMs)
            end
        end
        return
    end
    self:_stopAudio()
    self._lastAudioSegment = segment
    local soundId = not self.recordingAudio and
        string.format("KBM_Movie_%s_%03d", tostring(self.args.soundName), segment) or nil
    if self.audio then
        local ok, started
        if self.recordingAudio then
            ok, started = pcall(self.audio.playRecording, tostring(self.args.recordingId), offsetMs)
        else
            ok, started = pcall(self.audio.playSoundId, soundId, offsetMs)
        end
        if ok and started then self:_applyVolume(); return end
        local detail = "unknown error"
        pcall(function() detail = tostring(self.audio.getError()) end)
        print("[KBMGB][TVMovie] direct audio failed; using UI sound: " .. detail)
        self.audio = nil
    end
    if singleAudio then return end
    if not getSoundManager then return end
    local ok, handle = pcall(function() return getSoundManager():playUISound(soundId) end)
    if ok then self._activeSoundHandle = handle; self:_applyVolume() end
end

function JavaMoviePlayerApp:init(_ui, _x, _y, _w, _h, args)
    self.args = args or self.args
    self.audio = audioBridge()
    if self.args.recordingId and self.audio and self.audio.hasRecordingAudio then
        local ok, available = pcall(self.audio.hasRecordingAudio, tostring(self.args.recordingId))
        self.recordingAudio = ok and available == true
    end
    self.kbm = bridge()
    if not self.kbm then
        self.err = "KBMMoviePlayer was not exposed. Approve the updated KBMGB.jar and restart PZ."
        print("[KBMGB][TVMovie] " .. self.err)
        return
    end
    local ok, loaded
    if self.args.recordingId and self.kbm.loadRecording then
        ok, loaded = pcall(self.kbm.loadRecording, tostring(self.args.recordingId))
    elseif self.args.modId and self.kbm.loadFromMod then
        ok, loaded = pcall(self.kbm.loadFromMod, tostring(self.args.modId), tostring(self.args.video or ""))
    else
        ok, loaded = pcall(self.kbm.load, tostring(self.args.video or ""))
    end
    if not ok or loaded ~= true then
        local detail = "unknown error"
        pcall(function() detail = tostring(self.kbm.getError()) end)
        self.err = "Movie load failed: " .. detail
        print("[KBMGB][TVMovie] " .. self.err)
        return
    end
    self.signal = true
    pcall(self.kbm.play)
end

function JavaMoviePlayerApp:update(_ui)
    if self.kbm and self.signal and not self.err then pcall(self.kbm.update) end
    self:_soundUpdate()
    if self.kbm and self.signal and not self.err then
        local ok, playing, finished, frame, fps = pcall(function()
            return self.kbm.isPlaying(), self.kbm.isFinished(),
                self.kbm.getCurrentFrame(), self.kbm.getFps()
        end)
        if ok then
            local player = self.args.playerObj or (getPlayer and getPlayer())
            WatchReward.tick(self.watchReward, player, playing and not finished, frame, fps)
        end
    end
end

function JavaMoviePlayerApp:render(ui, x, y, w, h)
    if not self.signal then return end
    if self.err then
        ui:drawRect(x, y, w, h, 1, 0.02, 0.02, 0.02)
        ui:drawText(self.err, x + 8, y + 8, 1, 0.3, 0.3, 1, UIFont.Small)
        return
    end
    local ok, tex = pcall(self.kbm.getRenderTexture)
    if not ok or not tex then return end
    if self.args.recordingId then
        local videoW, videoH = 0, 0
        pcall(function()
            videoW = tonumber(self.kbm.getWidth()) or 0
            videoH = tonumber(self.kbm.getHeight()) or 0
        end)
        if videoW > 0 and videoH > 0 then
            local scale = math.min(w / videoW, h / videoH)
            local drawW, drawH = math.floor(videoW * scale), math.floor(videoH * scale)
            ui:drawTextureScaled(tex, x + math.floor((w - drawW) / 2),
                y + math.floor((h - drawH) / 2), drawW, drawH, 1)
            return
        end
    end
    ui:drawTextureScaled(tex, x, y, w, h, 1)
end

function JavaMoviePlayerApp:isSignalActive()
    return self.signal == true and self.err == nil
end

function JavaMoviePlayerApp:play()
    if not self.kbm or self.err then return end
    self.powered, self.signal = true, true
    pcall(self.kbm.play)
    if self.audio and self._lastAudioSegment >= 0 then pcall(self.audio.resume) end
end

function JavaMoviePlayerApp:pause()
    if self.kbm then pcall(self.kbm.pause) end
    if self.audio and self._lastAudioSegment >= 0 then pcall(self.audio.pause)
    else self:_stopAudio() end
end

function JavaMoviePlayerApp:stop()
    self:pause()
    self:_stopAudio()
    if self.kbm then pcall(self.kbm.seekFrame, 1) end
end

function JavaMoviePlayerApp:togglePause()
    if (self.args.recordingId or self.audio) and self.kbm then
        local ok, playing = pcall(self.kbm.isPlaying)
        if ok and playing then self:pause() else self:play() end
        return true
    end
    -- Legacy UI-sound fallback cannot resume inside a 30-second OGG.
    return false
end

function JavaMoviePlayerApp:togglePower()
    self.powered = not self.powered
    self.signal = self.powered and self.err == nil
    if self.powered then
        self:seekChunk(0)
        self:play()
    else
        self:pause()
    end
end

function JavaMoviePlayerApp:seekChunk(direction)
    if not self.kbm then return end
    local frame, totalFrames, fps = 1, 1, 24
    pcall(function()
        frame = tonumber(self.kbm.getCurrentFrame()) or 1
        totalFrames = tonumber(self.kbm.getTotalFrames()) or 1
        fps = tonumber(self.kbm.getFps()) or 24
    end)
    local chunkSeconds = tonumber(self.args.audioChunkSeconds) or 30
    local seconds = (frame - 1) / math.max(fps, 1)
    direction = tonumber(direction) or 0
    if self.args.recordingId or self.args.audioLayout == "single" then
        local maxSeconds = math.max(0, (totalFrames - 1) / math.max(fps, 1))
        local targetSeconds = math.max(0, math.min(maxSeconds, seconds + direction * 5))
        local target = math.max(1, math.min(totalFrames, math.floor(targetSeconds * fps) + 1))
        pcall(self.kbm.seekFrame, target)
        self:_stopAudio()
        return
    end
    local chunkIndex = math.floor(seconds / chunkSeconds)
    if direction < 0 then
        -- From inside a chunk, rewind to its start. From its start, go back one.
        local atBoundary = math.abs(seconds - (chunkIndex * chunkSeconds)) < (1 / math.max(fps, 1))
        if atBoundary then chunkIndex = chunkIndex - 1 end
    elseif direction > 0 then
        chunkIndex = chunkIndex + 1
    end
    local maxSeconds = math.max(0, (totalFrames - 1) / math.max(fps, 1))
    local maxChunkIndex = math.floor(maxSeconds / chunkSeconds)
    chunkIndex = math.max(0, math.min(maxChunkIndex, chunkIndex))
    local target = math.floor(chunkIndex * chunkSeconds * fps) + 1
    target = math.max(1, math.min(totalFrames, target))
    pcall(self.kbm.seekFrame, target)
    self:_stopAudio()
end

function JavaMoviePlayerApp:adjustVolume(delta)
    self.volume = VTUtils.clampVolume(self.volume + (tonumber(delta) or 0))
    self:_applyVolume()
end

function JavaMoviePlayerApp:onKey(_ui, key)
    if key == Keyboard.KEY_SPACE then return true end
    if key == Keyboard.KEY_LEFT then self:seekChunk(-1); return true end
    if key == Keyboard.KEY_RIGHT then self:seekChunk(1); return true end
    if key == Keyboard.KEY_R then self:stop(); self:play(); return true end
    return false
end

function JavaMoviePlayerApp:shutdown(_ui)
    self:_stopAudio()
    if self.kbm then pcall(self.kbm.close) end
    self.signal = false
end

return JavaMoviePlayerApp
