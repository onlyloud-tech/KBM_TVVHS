-- Viewpoint TV integration. The placed model is a radio item with a native
-- VHS slot; KnoxBox tapes keep their normal registry and eject path.
if _G.KBMViewpointTVPatchLoaded then return end
_G.KBMViewpointTVPatchLoaded = true
require "TimedActions/ISDeviceMediaAction"
require "RadioCom/ISRadioAction"
require "RadioCom/ISRadioWindow"
local RemoteOverlay = require "KBM_ViewpointTVRemote"
local WatchReward = require "KBMGB/Movie/WatchReward"

local TV_TYPE = "KBM.ScreenTV"
local LEGACY_TV_TYPE = "KBMViewpointProbe.ScreenTV"
local function isTVType(fullType)
    return fullType == TV_TYPE or fullType == LEGACY_TV_TYPE
end
local RECORDING_TYPE = "KBM.RecordedVHS"
local STATE_KEY = "KBMViewpointTape"
local activeDevice, activeEntry, activeAudio, audioSegment = nil, nil, nil, -1
local activePaused = false
local activeWatchReward = nil
local audioStartPending = false
local lastDriftLogFrame = -100000
local lastStatus = ""

local function log(message) print("[KBMViewpointTV] " .. tostring(message)) end
local function probe()
    if type(KBMViewpointScreenProbe) == "table" then return KBMViewpointScreenProbe end
    if type(com) == "table" and type(com.knoxboxprobe) == "table" then
        return com.knoxboxprobe.KBMViewpointScreenProbe
    end
end
local function registry()
    local ok, result = pcall(require, "KBMGB/Movie/MovieRegistry")
    return ok and result or nil
end
local function audioBridge()
    if type(KBMMovieAudio) == "table" then return KBMMovieAudio end
    if type(com) == "table" and type(com.knoxboxgb) == "table" then
        return com.knoxboxgb.KBMMovieAudio
    end
end

local function itemOf(obj)
    if not obj then return nil end
    if obj.getFullType then
        local ok, fullType = pcall(obj.getFullType, obj)
        if ok and isTVType(fullType) then return obj end
    end
    if obj.getItem then
        local ok, item = pcall(obj.getItem, obj)
        if ok and item and item.getFullType and isTVType(item:getFullType()) then return item end
    end
    local data = obj.getModData and obj:getModData() or nil
    local id = data and data.RadioItemID
    local square = obj.getSquare and obj:getSquare() or nil
    local objects = square and square.getWorldObjects and square:getWorldObjects() or nil
    if id and objects then
        for i = 0, objects:size() - 1 do
            local world = objects:get(i)
            local item = world and world.getItem and world:getItem() or nil
            if item and item.getID and item:getID() == id and isTVType(item:getFullType()) then
                return item
            end
        end
    end
    return nil
end
local function deviceOf(data, device)
    if itemOf(device) then return device end
    local parent = data and data.getParent and data:getParent() or nil
    if itemOf(parent) then return parent end
    return nil
end
local function tapeState(device, create)
    if not device or not device.getModData then return nil end
    local data = device:getModData()
    if create and not data[STATE_KEY] then data[STATE_KEY] = {} end
    return data[STATE_KEY]
end
local function setTape(device, fullType, recordingId, label)
    local state = tapeState(device, true)
    state.fullType = fullType or ""
    state.recordingId = recordingId or ""
    state.label = label or ""
    if device.transmitModData then pcall(device.transmitModData, device) end
end
local function entryFor(device)
    local state = tapeState(device, false)
    local reg = registry()
    local entry = state and reg and reg.get(state.fullType) or nil
    if not entry then return nil end
    if state.fullType ~= RECORDING_TYPE then return entry end
    if not state.recordingId or state.recordingId == "" then return nil end
    return {
        itemType = RECORDING_TYPE,
        label = state.label,
        recordingId = state.recordingId,
    }
end
local function stop()
    if activeAudio then pcall(activeAudio.stop) end
    local p = probe()
    if p then p.stop() end
    activeDevice, activeEntry, activeAudio, audioSegment = nil, nil, nil, -1
    activePaused = false
    activeWatchReward = nil
    audioStartPending = false
    lastDriftLogFrame = -100000
end
local function start(device)
    local entry = entryFor(device)
    local p = probe()
    if not p or not entry then log("no playable tape"); return end
    stop()
    local ok, loaded
    if entry.recordingId and entry.recordingId ~= "" then
        ok, loaded = pcall(p.playRecording, tostring(entry.recordingId))
    elseif entry.modId and entry.video then
        ok, loaded = pcall(p.playFromMod, tostring(entry.modId), tostring(entry.video))
    end
    if not ok or loaded ~= true then
        log("video load failed: " .. tostring(p.getStatus()))
        return
    end
    activeDevice, activeEntry, activeAudio, audioSegment = device, entry, audioBridge(), -1
    activePaused = false
    activeWatchReward = WatchReward.new()
    audioStartPending = true
    lastDriftLogFrame = -100000
    log("playing " .. tostring(entry.label or entry.itemType))
end

local function togglePause(device)
    if device ~= activeDevice or not activeEntry then return end
    local p = probe()
    if not p then return end
    if activePaused then
        pcall(p.resume)
        if activeAudio then pcall(activeAudio.resume) end
        activePaused = false
        log("remote resumed playback")
    else
        pcall(p.pause)
        if activeAudio then pcall(activeAudio.pause) end
        activePaused = true
        log("remote paused playback")
    end
end

local function seek(device, seconds)
    if device ~= activeDevice or not activeEntry then return false end
    local p = probe()
    if not p or not p.seekSeconds then return false end
    local ok, moved = pcall(p.seekSeconds, seconds)
    if not ok or not moved then
        log("remote seek failed: " .. tostring(p and p.getStatus and p.getStatus() or moved))
        return false
    end
    if activeAudio then pcall(activeAudio.stop) end
    audioSegment = -1
    audioStartPending = true
    log("remote seek " .. tostring(seconds) .. "s")
    return true
end

local remoteControls = {
    isActive = function(device) return device == activeDevice and activeEntry ~= nil end,
    togglePause = togglePause,
    isPaused = function(device) return device == activeDevice and activePaused end,
    seek = seek,
}
local function snapshot(character)
    local seen = {}
    local items = character and character.getInventory and character:getInventory():getItems() or nil
    if items then
        for i = 0, items:size() - 1 do seen[tostring(items:get(i))] = true end
    end
    return seen
end
local function restoreEjected(character, before, recordingId, label)
    if not recordingId or recordingId == "" then return end
    local items = character and character.getInventory and character:getInventory():getItems() or nil
    if not items then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == RECORDING_TYPE and not before[tostring(item)] then
            item:getModData().KBMRecordingId = recordingId
            item:getModData().KBMRecordingLabel = label
            if label and label ~= "" then item:setName("VHS - " .. label) end
            return
        end
    end
    log("ejected recording item not found")
end

local originalMediaInvoke = ISDeviceMediaAction.invoke
function ISDeviceMediaAction:invoke()
    local device = deviceOf(self.deviceData, self.device)
    local old = device and tapeState(device, false) or nil
    local oldType = old and old.fullType or nil
    local oldId = old and old.recordingId or nil
    local oldLabel = old and old.label or nil
    local before = self.isRemove and oldId and snapshot(self.character) or nil
    originalMediaInvoke(self)
    if not device then return end
    if self.isRemove then
        if oldType and oldType ~= "" then
            if before then restoreEjected(self.character, before, oldId, oldLabel) end
            setTape(device, "")
            if activeDevice == device then stop() end
            log("tape ejected")
        end
        return
    end
    local item = self.secondaryItem
    local fullType = item and item.getFullType and item:getFullType() or nil
    local reg = registry()
    if not reg or not reg.isTape(fullType) then return end
    local data = item:getModData()
    local recordingId = fullType == RECORDING_TYPE and data and data.KBMRecordingId or nil
    local label = fullType == RECORDING_TYPE and data and data.KBMRecordingLabel or item:getName()
    if label and label:sub(1, 6) == "VHS - " then label = label:sub(7) end
    setTape(device, fullType, recordingId, label)
    log("tape inserted: " .. fullType)
end

local originalTogglePlay = ISRadioAction.performTogglePlayMedia
function ISRadioAction:performTogglePlayMedia()
    local device = deviceOf(self.deviceData, self.device)
    local wasPlaying = self.deviceData and self.deviceData.isPlayingMedia
        and self.deviceData:isPlayingMedia()
    originalTogglePlay(self)
    if not device then return end
    local nowPlaying = self.deviceData and self.deviceData.isPlayingMedia
        and self.deviceData:isPlayingMedia()
    if nowPlaying and not wasPlaying then start(device)
    elseif wasPlaying and not nowPlaying then stop(); log("playback stopped") end
end

local originalTogglePower = ISRadioAction.performToggleOnOff
function ISRadioAction:performToggleOnOff()
    local device = deviceOf(self.deviceData, self.device)
    originalTogglePower(self)
    if device and activeDevice == device and self.deviceData
        and not self.deviceData:getIsTurnedOn() then stop() end
end

local function soundUpdate()
    if not activeEntry or not activeAudio then return end
    if activePaused then return end
    local p = probe()
    if not p or p.isFinished() then
        pcall(activeAudio.stop)
        audioSegment = -1
        return
    end
    local seconds = math.max(0, (tonumber(p.getCurrentFrame()) - 1) / math.max(1, tonumber(p.getFps())))
    local chunkSeconds = tonumber(activeEntry.audioChunkSeconds) or 30
    local single = activeEntry.recordingId or activeEntry.audioLayout == "single"
    local segment = single and 0 or math.floor(seconds / chunkSeconds)
    local offsetMs = math.floor((seconds - (single and 0 or segment * chunkSeconds)) * 1000)
    if segment ~= audioSegment then
        pcall(activeAudio.stop)
        local ok, started = false, false
        if activeEntry.recordingId then
            ok, started = pcall(activeAudio.playRecording, tostring(activeEntry.recordingId), offsetMs)
        elseif activeEntry.soundName then
            ok, started = pcall(activeAudio.playSoundId,
                string.format("KBM_Movie_%s_%03d", tostring(activeEntry.soundName), segment), offsetMs)
        end
        if ok and started then audioSegment = segment end
    end
    if audioSegment == segment then
        local ok, positionMs = pcall(activeAudio.getPositionMs)
        if ok and tonumber(positionMs) and tonumber(positionMs) >= 0 then
            local frame = tonumber(p.getCurrentFrame()) or 0
            local displayed = p.getDisplayedFrame and tonumber(p.getDisplayedFrame()) or frame
            local fps = math.max(1, tonumber(p.getFps()) or 1)
            local displayedSeconds = math.max(0, (displayed - 1) / fps)
            local displayedOffsetMs = math.floor((displayedSeconds - (single and 0 or segment * chunkSeconds)) * 1000)
            local driftMs = tonumber(positionMs) - displayedOffsetMs
            if math.abs(driftMs) > 350 and frame - lastDriftLogFrame > fps * 10 then
                log("A/V drift " .. math.floor(driftMs) .. "ms at displayed frame "
                    .. displayed .. " (decoded " .. frame .. ")")
                lastDriftLogFrame = frame
            end
        end
    end
    local volume = activeDevice and activeDevice.getDeviceData
        and activeDevice:getDeviceData():getDeviceVolume() or 1
    pcall(activeAudio.setVolume, volume)
end

local function updateAudioClock(p)
    if not p.setAudioClockMs then return end
    if not activeEntry or not activeAudio or audioSegment < 0 or activePaused then
        pcall(p.setAudioClockMs, -1)
        return
    end
    local ok, positionMs = pcall(activeAudio.getPositionMs)
    if not ok or not tonumber(positionMs) or tonumber(positionMs) < 0 then
        pcall(p.setAudioClockMs, -1)
        return
    end
    local single = activeEntry.recordingId or activeEntry.audioLayout == "single"
    local chunkSeconds = tonumber(activeEntry.audioChunkSeconds) or 30
    local absoluteMs = tonumber(positionMs) + (single and 0 or audioSegment * chunkSeconds * 1000)
    pcall(p.setAudioClockMs, math.floor(absoluteMs))
end

local audioTick = 0
Events.OnRenderTick.Add(function()
    local p = probe()
    if not p then return end
    updateAudioClock(p)
    p.tick()
    if activeEntry and activeWatchReward then
        local player = getPlayer and getPlayer() or nil
        local tvSquare = activeDevice and activeDevice.getSquare and activeDevice:getSquare() or nil
        local playerSquare = player and player.getSquare and player:getSquare() or nil
        local nearby = tvSquare and playerSquare and tvSquare:getZ() == playerSquare:getZ()
            and math.abs(tvSquare:getX() - playerSquare:getX()) <= 6
            and math.abs(tvSquare:getY() - playerSquare:getY()) <= 6
        WatchReward.tick(activeWatchReward, nearby and player or nil,
            not activePaused and p.isPlaying() and not p.isFinished(),
            p.getCurrentFrame(), p.getFps())
    end
    local status = tostring(p.getStatus())
    if status ~= lastStatus then
        lastStatus = status
        log(status)
    end
    audioTick = audioTick + 1
    if activeEntry and audioStartPending and tonumber(p.getCurrentFrame()) > 0 then
        audioStartPending = false
        soundUpdate()
    elseif activeEntry and audioTick % 15 == 0 then
        soundUpdate()
    end
end)

-- Viewpoint's 3D world-item model can be the clicked surface even though the
-- associated IsoRadio is invisible. Offer the same native panel explicitly.
local function radioForWorldItem(square, item)
    local objects = square and square.getObjects and square:getObjects() or nil
    if not objects then return nil end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if instanceof(object, "IsoRadio") then
            local data = object:getModData()
            if data and data.RadioItemID == item:getID() then return object end
        end
    end
    return nil
end

local function onWorldMenu(playerNum, context, worldObjects, test)
    if test then return end
    local seen = {}
    for _, object in ipairs(worldObjects or {}) do
        local square = object and object.getSquare and object:getSquare() or nil
        if square and not seen[square] then
            seen[square] = true
            local objects = square:getWorldObjects()
            for i = 0, objects:size() - 1 do
                local world = objects:get(i)
                local item = world and world.getItem and world:getItem() or nil
                if item and isTVType(item:getFullType()) then
                    local radio = radioForWorldItem(square, item)
                    if radio then
                        local player = getSpecificPlayer(playerNum)
                        context:addOption("Device Options (KnoxBox TV)", player, function(p)
                            ISRadioWindow.activate(p, radio)
                        end)
                        if radio:getDeviceData():canPlayerRemoteInteract(player) then
                            context:addOption("KnoxBox TV Remote", player, function(p)
                                RemoteOverlay.open(p, radio, remoteControls)
                            end)
                        end
                    else
                        context:addOption("KnoxBox TV: place a newly spawned TV", nil, function()
                            log("old plain-item TV has no media device; spawn and place a new TV")
                        end)
                    end
                    return
                end
            end
        end
    end
end
Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)

local function nearestRemoteTV(player)
    local current = player and player.getSquare and player:getSquare() or nil
    local cell = current and current:getCell() or nil
    if not cell then return nil end
    local best, bestDistance = nil, math.huge
    for x = current:getX() - 10, current:getX() + 10 do
        for y = current:getY() - 10, current:getY() + 10 do
            local square = cell:getGridSquare(x, y, current:getZ())
            local items = square and square:getWorldObjects() or nil
            if items then
                for i = 0, items:size() - 1 do
                    local world = items:get(i)
                    local item = world and world.getItem and world:getItem() or nil
                    if item and isTVType(item:getFullType()) then
                        local radio = radioForWorldItem(square, item)
                        local data = radio and radio:getDeviceData() or nil
                        if data and data:canPlayerRemoteInteract(player) then
                            local distance = (x - current:getX()) ^ 2 + (y - current:getY()) ^ 2
                            if distance < bestDistance then best, bestDistance = radio, distance end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- The ground-inventory entry remains selectable even if Viewpoint consumes
-- the model click before PZ dispatches the world context-menu event.
local function onInventoryMenu(playerNum, context, items)
    for _, entry in ipairs(items or {}) do
        local item = entry.items and entry.items[1] or entry
        if item and item.getFullType and item:getFullType() == "Base.Remote" then
            local player = getSpecificPlayer(playerNum)
            context:addOption("Use KnoxBox TV Remote", player, function(p)
                local radio = nearestRemoteTV(p)
                if radio then RemoteOverlay.open(p, radio, remoteControls)
                elseif p and p.Say then p:Say("Equip the remote and face a nearby KnoxBox TV.") end
            end)
            return
        end
        if item and item.getFullType and isTVType(item:getFullType()) then
            local world = item.getWorldItem and item:getWorldItem() or nil
            local square = world and world.getSquare and world:getSquare() or nil
            local target = square and radioForWorldItem(square, item) or item
            if target and (target ~= item or instanceof(item, "Radio")) then
                local player = getSpecificPlayer(playerNum)
                context:addOption("Device Options (KnoxBox TV)", player, function(p)
                    ISRadioWindow.activate(p, target)
                end)
            end
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onInventoryMenu)
