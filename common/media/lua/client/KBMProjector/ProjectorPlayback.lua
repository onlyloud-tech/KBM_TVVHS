-- Play KnoxBox tapes through the Movies & TV decoder on the projection screen.
require "TimedActions/ISDeviceMediaAction"
require "RadioCom/ISRadioAction"

local Registry = require "KBMGB/Movie/MovieRegistry"
local Cinema = require "KBMProjector/CinemaProjector"
local WorldAudio = require "KBMGB/Movie/WorldAudio"
local TAPE_KEY = "KBMProjectorTape"
local RECORDING = "KBM.RecordedVHS"
local FULL_VOLUME_TILES = 18
local SILENT_TILES = 24
local activeRadio = nil
local activeEntry = nil
local activeAudio = nil
local activeAudioSource = nil
local activeRemote = false
local activePaused = false
local audioSegment = -1
local audioTick = 0
local lastStatus = ""
local missingLinkLogs = 0

KBMProjectorPlayback = KBMProjectorPlayback or {}
KBMProjectorPlayback.isActive = function()
    return activeRadio ~= nil
end
KBMProjectorPlayback.getActiveDevice = function()
    return activeRadio
end


local function log(message)
    print("[KBMProjector][Playback] " .. tostring(message))
end

local function tap()
    if type(KBMProjectorFrameTap) == "table" then return KBMProjectorFrameTap end
    return type(com) == "table" and type(com.knoxboxprobe) == "table"
        and com.knoxboxprobe.KBMProjectorFrameTap or nil
end

local function playerBridge()
    if type(KBMMovieScreenBridge) == "table" then return KBMMovieScreenBridge end
    return type(com) == "table" and type(com.knoxboxprobe) == "table"
        and com.knoxboxprobe.KBMMovieScreenBridge or nil
end

local function audioBridge()
    if type(KBMMovieAudio) == "table" then return KBMMovieAudio end
    return type(com) == "table" and type(com.knoxboxgb) == "table"
        and com.knoxboxgb.KBMMovieAudio or nil
end

local function projector(device)
    local data = device and device.getModData and device:getModData() or nil
    if data and data.KBMProjectorDevice == true then return device end
end

local function deviceFor(action)
    if projector(action.device) then return action.device end
    local data = action.deviceData
    local parent = data and data.getParent and data:getParent() or nil
    local linked = projector(parent)
    if linked then return linked end
    -- Media actions hold the square, rather than the IsoRadio, as parameter.
    local square = action.parameter
    local objects = square and square.getObjects and square:getObjects() or nil
    if not objects then return nil end
    local candidate = nil
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if projector(object) then
            if object.getDeviceData and object:getDeviceData() == data then return object end
            candidate = candidate or object
        end
    end
    return candidate
end

local function worldItem(device)
    local data = device and device:getModData() or nil
    local id = data and data.RadioItemID
    local square = device and device:getSquare() or nil
    local objects = square and square:getWorldObjects() or nil
    if not id or not objects then return nil end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local item = object and object:getItem() or nil
        if item and item:getID() == id then return item end
    end
end

local function tapeState(device)
    local item = worldItem(device)
    local state = item and item:getModData()[TAPE_KEY]
    if state then return state end
    return device and device:getModData()[TAPE_KEY] or nil
end

local function setTape(device, fullType, recordingId, label)
    local state = {fullType=fullType or "", recordingId=recordingId or "", label=label or ""}
    device:getModData()[TAPE_KEY] = state
    if device.transmitModData then pcall(device.transmitModData, device) end
    local item = worldItem(device)
    if item then item:getModData()[TAPE_KEY] = state end
end

local function entryFor(device)
    local state = tapeState(device)
    local entry = state and Registry.get(state.fullType) or nil
    if not entry then return nil end
    if state.fullType ~= RECORDING then return entry end
    if not state.recordingId or state.recordingId == "" then return nil end
    return {itemType=RECORDING, label=state.label, recordingId=state.recordingId}
end

local function stopProjector(stopMovie)
    if not activeRadio then return end
    local bridge = tap()
    if bridge then pcall(bridge.stop) end
    if stopMovie then
        if activeAudio then pcall(activeAudio.stop) end
        local movie = playerBridge()
        if movie then pcall(movie.stop) end
    end
    activeRadio = nil
    activeEntry = nil
    activeAudio = nil
    activeAudioSource = nil
    activeRemote, activePaused = false, false
    audioSegment = -1
end

local function startProjector(device, remoteEntry)
    if isClient and isClient() and _G.KBMMPClient and not remoteEntry then
        return _G.KBMMPClient.request(device, "Play")
    end
    local entry = remoteEntry or entryFor(device)
    local bridge = tap()
    local movie = playerBridge()
    if not entry or not movie or not bridge then
        log("movie entry or playback bridge unavailable")
        return
    end
    stopProjector(true)
    local md = device:getModData()
    if md.KBMStaticProjector then
        local target = Cinema.screen(device:getSquare())
        if not target or (not remoteEntry and not Cinema.fixture(device:getSquare())) then
            log("cinema fixture or configured screen is unavailable")
            return
        end
        md.KBMProjectorScreenId = target.id
        if bridge.setScreenModel then bridge.setScreenModel(target.itemType) end
    elseif bridge.setScreenModel then
        bridge.setScreenModel("") -- Legacy movable projectors keep automatic targeting.
    end
    local sound = audioBridge()
    if sound then pcall(sound.stop) end
    pcall(movie.stop)
    local ok, loaded
    if entry.recordingId and entry.recordingId ~= "" then
        ok, loaded = pcall(movie.playRecording, tostring(entry.recordingId))
    elseif entry.modId and entry.video then
        ok, loaded = pcall(movie.playFromMod, tostring(entry.modId), tostring(entry.video))
    end
    if not ok or loaded ~= true then
        log("video load failed: " .. tostring(movie.getStatus and movie.getStatus() or loaded))
        return
    end
    -- The movie decoder only accepts TV targets. Choose a legacy model that
    -- is absent in this test setup; the frame tap paints the projector screen.
    if movie.setTvDisplay then pcall(movie.setTvDisplay, "KBMViewpointProbe.ScreenTVPlaying") end
    bridge.start()
    activeRadio = device
    activeRemote = remoteEntry ~= nil
    local target = Cinema.screen(device:getSquare())
    if target then
        -- A drive-in booth is far from its audience. Emit movie audio at the
        -- linked screen's tile, with a wider audience radius than televisions.
        local sourceSquare = {
            getX=function() return target.x end,
            getY=function() return target.y end,
            getZ=function() return target.z end,
        }
        activeAudioSource = {getSquare=function() return sourceSquare end}
    else
        activeAudioSource = device
    end
    activeEntry = entry
    activeAudio = sound
    audioSegment = -1
    audioTick = 0
    log("started " .. tostring(entry.label or entry.itemType))
end

local function updateAudio(movie)
    if not activeEntry or not activeAudio or activePaused or movie.isFinished() then return end
    local frame = tonumber(movie.getCurrentFrame()) or 0
    if frame <= 0 then return end
    local fps = math.max(1, tonumber(movie.getFps()) or 12)
    local seconds = math.max(0, (frame - 1) / fps)
    local chunkSeconds = tonumber(activeEntry.audioChunkSeconds) or 30
    local single = activeEntry.recordingId or activeEntry.audioLayout == "single"
    local segment = single and 0 or math.floor(seconds / chunkSeconds)
    local offsetMs = math.floor((seconds - (single and 0 or segment * chunkSeconds)) * 1000)
    if segment ~= audioSegment then
        pcall(activeAudio.stop)
        local ok, started = false, false
        if activeEntry.recordingId then
            ok, started = pcall(activeAudio.playRecording,
                tostring(activeEntry.recordingId), offsetMs)
        elseif activeEntry.soundName then
            ok, started = pcall(activeAudio.playSoundId,
                string.format("KBM_Movie_%s_%03d", tostring(activeEntry.soundName), segment), offsetMs)
        end
        if ok and started then
            audioSegment = segment
            log("audio segment " .. segment)
        end
    end
    if audioSegment == segment then
        local volume = activeRadio and activeRadio.getDeviceData
            and activeRadio:getDeviceData():getDeviceVolume() or 1
        volume = volume * WorldAudio.gain(activeAudioSource, getPlayer(), FULL_VOLUME_TILES, SILENT_TILES)
        pcall(activeAudio.setVolume, volume)
        if movie.setAudioClockMs then
            local ok, positionMs = pcall(activeAudio.getPositionMs)
            if ok and tonumber(positionMs) and tonumber(positionMs) >= 0 then
                local absoluteMs = tonumber(positionMs)
                    + (single and 0 or segment * chunkSeconds * 1000)
                pcall(movie.setAudioClockMs, math.floor(absoluteMs))
            end
        end
    end
end

-- Server snapshots control multiplayer playback; these functions only render
-- the approved state locally and never create or change a world device.
KBMProjectorPlayback.mpVersion = 1
KBMProjectorPlayback.startRemote = startProjector
KBMProjectorPlayback.stopRemote = function() stopProjector(true) end
KBMProjectorPlayback.position = function()
    local movie = playerBridge()
    return movie and math.max(0,(movie.getCurrentFrame()-1)/math.max(1,movie.getFps())) or 0
end
KBMProjectorPlayback.seekRemote = function(seconds)
    local movie = playerBridge()
    if not movie or not movie.seekSeconds then return false end
    local delta = math.floor(seconds-KBMProjectorPlayback.position()+0.5)
    if delta == 0 then return true end
    if activeAudio then pcall(activeAudio.stop) end
    audioSegment = -1
    if movie.setAudioClockMs then pcall(movie.setAudioClockMs, -1) end
    return movie.seekSeconds(delta)
end
KBMProjectorPlayback.pauseRemote = function(paused)
    if activePaused == paused then return end
    local movie = playerBridge()
    if movie then pcall(paused and movie.pause or movie.resume) end
    if activeAudio then pcall(paused and activeAudio.pause or activeAudio.resume) end
    activePaused = paused
end
KBMProjectorPlayback.diagnostics = function()
    local movie = playerBridge()
    return movie and movie.getCurrentFrame() or 0, -1, movie and movie.isFinished() or false
end

local function inventorySnapshot(character)
    local seen = {}
    local inv = character and character:getInventory() or nil
    local items = inv and inv:getItems() or nil
    if items then
        for i = 0, items:size() - 1 do seen[tostring(items:get(i))] = true end
    end
    return seen
end

local function restoreRecording(character, before, id, label)
    if not before or not id or id == "" then return end
    local inv = character and character:getInventory() or nil
    local items = inv and inv:getItems() or nil
    if not items then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == RECORDING and not before[tostring(item)] then
            item:getModData().KBMRecordingId = id
            item:getModData().KBMRecordingLabel = label
            if label and label ~= "" then item:setName("VHS - " .. label) end
            return
        end
    end
    log("could not restore ejected recording metadata")
end

local function installActions()
    if _G.KBMProjectorPlaybackActionsInstalled then return end
    _G.KBMProjectorPlaybackActionsInstalled = true
    local published = _G.KBMViewpointTVPlayback
    if published and published.isActive then
        local priorIsActive = published.isActive
        published.isActive = function()
            if activeRadio then return true end
            return priorIsActive()
        end
    end

    local priorMedia = ISDeviceMediaAction.invoke
    function ISDeviceMediaAction:invoke()
        if isClient and isClient() and _G.KBMMPClient then return priorMedia(self) end
        local device = deviceFor(self)
        if not device and missingLinkLogs < 4 then
            missingLinkLogs = missingLinkLogs + 1
            log("media action has no projector link; parameter=" .. tostring(self.parameter)
                .. " parent=" .. tostring(self.deviceData and self.deviceData.getParent
                    and self.deviceData:getParent() or nil))
        end
        local old = device and tapeState(device) or nil
        local before = device and self.isRemove and old and old.recordingId ~= ""
            and inventorySnapshot(self.character) or nil
        local item = self.secondaryItem
        priorMedia(self)
        if not device then return end
        if self.isRemove then
            if old and old.fullType ~= "" then
                restoreRecording(self.character, before, old.recordingId, old.label)
                setTape(device, "")
                if activeRadio == device then stopProjector(true) end
            end
            return
        end
        local fullType = item and item:getFullType() or nil
        if not Registry.isTape(fullType) then return end
        local data = item:getModData()
        local recordingId = fullType == RECORDING and data and data.KBMRecordingId or nil
        local label = fullType == RECORDING and data and data.KBMRecordingLabel or item:getName()
        if label and label:sub(1, 6) == "VHS - " then label = label:sub(7) end
        setTape(device, fullType, recordingId, label)
        log("inserted " .. fullType)
    end

    local priorPlay = ISRadioAction.performTogglePlayMedia
    function ISRadioAction:performTogglePlayMedia()
        local device = deviceFor(self)
        if device and isClient and isClient() and _G.KBMMPClient then
            return _G.KBMMPClient.request(device, "Toggle")
        end
        local wasPlaying = self.deviceData and self.deviceData.isPlayingMedia
            and self.deviceData:isPlayingMedia()
        priorPlay(self)
        local nowPlaying = self.deviceData and self.deviceData.isPlayingMedia
            and self.deviceData:isPlayingMedia()
        if not device then
            if nowPlaying and not wasPlaying and missingLinkLogs < 4 then
                missingLinkLogs = missingLinkLogs + 1
                log("play action has no projector link; device=" .. tostring(self.device))
            end
            if activeRadio and nowPlaying and not wasPlaying then stopProjector(false) end
            return
        end
        if nowPlaying and not wasPlaying then startProjector(device)
        elseif wasPlaying and not nowPlaying and activeRadio == device then stopProjector(true) end
    end

    local priorPower = ISRadioAction.performToggleOnOff
    function ISRadioAction:performToggleOnOff()
        local device = deviceFor(self)
        priorPower(self)
        if device and activeRadio == device and self.deviceData
                and not self.deviceData:getIsTurnedOn() then stopProjector(true) end
    end
    -- Native mute buttons play sounds through the character, rather than the
    -- device emitter. Keep those changes quiet only for cinema projectors.
    for _, mode in ipairs({"MuteVolume", "UnMuteVolume"}) do
        local selectedMode = mode
        local previous = ISRadioAction["perform" .. selectedMode]
        ISRadioAction["perform" .. selectedMode] = function(self)
            local device = deviceFor(self)
            if device and device:getModData().KBMStaticProjector then
                if isClient and isClient() and _G.KBMMPClient then
                    return _G.KBMMPClient.request(device, "Volume", selectedMode == "MuteVolume" and 0 or self.secondaryItem)
                end
                if self["isValid" .. selectedMode](self) then
                    self.deviceData:setDeviceVolume(selectedMode == "MuteVolume" and 0 or self.secondaryItem)
                end
                return
            end
            if previous then return previous(self) end
        end
    end
    log("native projector playback actions installed")
end

Events.OnGameStart.Add(installActions)
Events.OnRenderTick.Add(function()
    if not activeRadio then return end
    local data = activeRadio:getDeviceData()
    if not data or not data:getIsTurnedOn() then
        stopProjector(true)
        return
    end
    if not activeRemote and activeRadio:getModData().KBMStaticProjector then
        local square = activeRadio:getSquare()
        if not square or not Cinema.fixture(square)
                or (data:getIsBatteryPowered() and (not data:getHasBattery() or data:getPower() <= 0)) then
            stopProjector(true)
            return
        end
    end
    local bridge = tap()
    if not bridge then return end
    local movie = playerBridge()
    -- KBM_ViewpointProbe owns the shared movie decoder tick, including projectors.
    bridge.update()
    local status = tostring(bridge.getStatus())
    if status ~= lastStatus then lastStatus = status; log(status) end
    if movie and movie.isFinished and movie.isFinished() then
        stopProjector(true)
        return
    end
    audioTick = audioTick + 1
    if movie and (audioSegment < 0 or audioTick % 15 == 0) then updateAudio(movie) end
end)
