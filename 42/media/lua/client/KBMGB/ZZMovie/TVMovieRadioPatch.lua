require "TimedActions/ISDeviceMediaAction"
require "RadioCom/ISRadioAction"

local Registry = require("KBMGB/Movie/MovieRegistry")
local MovieApp = require("KBMGB/Movie/JavaMoviePlayerApp")
local MovieWindow = require("KBMGB/Movie/TVMovieWindow")
local VTUtils = require("KBMGB/System/VTUtils")

local STATE_KEY = "KBMGB_TV_Movie"
local RECORDABLE_TYPE = "KBM.RecordedVHS"
local activeWindow = nil

local function log(msg) print("[KBMGB][TVMovie] " .. tostring(msg)) end

local function deviceFromData(deviceData)
    if deviceData and deviceData.getParent then
        local ok, parent = pcall(deviceData.getParent, deviceData)
        if ok then return parent end
    end
    return nil
end

local function state(tv, create)
    if not tv or not tv.getModData then return nil end
    local data = tv:getModData()
    if create and not data[STATE_KEY] then data[STATE_KEY] = {} end
    return data[STATE_KEY]
end

local function setTape(tv, fullType, recordingId, label)
    local s = state(tv, true)
    if not s then return end
    s.fullType = fullType or ""
    s.recordingId = recordingId or ""
    s.label = label or ""
    if tv.transmitModData then pcall(tv.transmitModData, tv) end
end

local function getTape(tv)
    local s = state(tv, false)
    local fullType = s and s.fullType or nil
    return fullType ~= "" and fullType or nil
end

local function entryForTV(tv)
    local fullType = getTape(tv)
    local entry = Registry.get(fullType)
    if not entry then return nil end
    if fullType ~= RECORDABLE_TYPE then return entry end
    local s = state(tv, false)
    if not s or not s.recordingId or s.recordingId == "" then return nil end
    return {
        itemType = fullType,
        recMediaId = entry.recMediaId,
        label = s.label and s.label ~= "" and s.label or "Home Recording",
        recordingId = s.recordingId,
    }
end

local function closeWindow()
    local win = activeWindow
    activeWindow = nil
    if win and win.close then pcall(win.close, win) end
end

local function openWindow(tv)
    -- The KnoxBox 3D TV plays on its model via KBM_ViewpointProbe. Opening the
    -- 2D movie window as well covers the Viewpoint scene and duplicates playback.
    if VTUtils.isKnoxBox3DTV(tv) then return end
    local entry = entryForTV(tv)
    if not entry then return end
    closeWindow()
    local ok, win = pcall(MovieWindow.new, MovieWindow, nil, MovieApp, entry)
    if not ok or not win then log("window creation failed: " .. tostring(win)); return end
    pcall(win.initialise, win)
    pcall(win.addToUIManager, win)
    if win.bringToFront then pcall(win.bringToFront, win) end
    activeWindow = win
    log("opened " .. tostring(entry.itemType) .. " recording=" .. tostring(entry.recordingId or ""))
end

local function inventorySnapshot(character)
    local seen = {}
    local inv = character and character.getInventory and character:getInventory() or nil
    local items = inv and inv.getItems and inv:getItems() or nil
    if items then
        for i = 0, items:size() - 1 do seen[tostring(items:get(i))] = true end
    end
    return seen
end

local function restoreEjectedTape(character, seen, recordingId, label)
    if not recordingId or recordingId == "" then return end
    local inv = character and character.getInventory and character:getInventory() or nil
    local items = inv and inv.getItems and inv:getItems() or nil
    if not items then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item:getFullType() == RECORDABLE_TYPE and not seen[tostring(item)] then
            item:getModData().KBMRecordingId = recordingId
            item:getModData().KBMRecordingLabel = label
            if item.setName and label and label ~= "" then pcall(item.setName, item, "VHS - " .. label) end
            log("recording ID restored to ejected tape: " .. recordingId)
            return
        end
    end
    log("could not find newly ejected recording tape")
end

local originalMediaInvoke = ISDeviceMediaAction.invoke
function ISDeviceMediaAction:invoke()
    local item = self.secondaryItem
    local removing = self.isRemove
    local deviceData = self.deviceData
    local tv = deviceFromData(deviceData)
    local removedOurs = removing and tv and Registry.isTape(getTape(tv))
    local oldState = removing and tv and state(tv, false) or nil
    local ejectedId = oldState and oldState.recordingId or nil
    local ejectedLabel = oldState and oldState.label or nil
    local before = removing and ejectedId and inventorySnapshot(self.character) or nil

    originalMediaInvoke(self)

    if not tv or not VTUtils.isTelevisionObject(tv) then return end
    if removing then
        if removedOurs then
            if before then restoreEjectedTape(self.character, before, ejectedId, ejectedLabel) end
            setTape(tv, "")
            closeWindow()
            log("tape ejected")
        end
        return
    end
    local fullType = item and item.getFullType and item:getFullType() or nil
    if Registry.isTape(fullType) then
        local data = item and item.getModData and item:getModData() or nil
        local recordingId = fullType == RECORDABLE_TYPE and data and data.KBMRecordingId or nil
        local label = fullType == RECORDABLE_TYPE and data and data.KBMRecordingLabel
            or item and item.getName and item:getName() or nil
        if label and label:sub(1, 6) == "VHS - " then label = label:sub(7) end
        setTape(tv, fullType, recordingId, label)
        log("tape inserted: " .. fullType .. " recording=" .. tostring(recordingId or ""))
    end
end

local originalTogglePlay = ISRadioAction.performTogglePlayMedia
function ISRadioAction:performTogglePlayMedia()
    local deviceData = self.deviceData
    local tv = self.device or deviceFromData(deviceData)
    local wasPlaying = deviceData and deviceData.isPlayingMedia and deviceData:isPlayingMedia()

    originalTogglePlay(self)

    if not tv or not VTUtils.isTelevisionObject(tv) then return end
    local fullType = getTape(tv)
    if not Registry.isTape(fullType) then return end
    local nowPlaying = deviceData and deviceData.isPlayingMedia and deviceData:isPlayingMedia()
    if nowPlaying and not wasPlaying then openWindow(tv)
    elseif not nowPlaying and wasPlaying then closeWindow(); log("playback stopped") end
end

local function onContextMenu(_playerNum, context, worldObjects, test)
    if test then return end
    local tv = nil
    for _, object in ipairs(worldObjects) do
        if VTUtils.isTelevisionObject(object) then tv = object; break end
    end
    local fullType = tv and getTape(tv) or nil
    local entry = tv and entryForTV(tv) or nil
    if not entry then return end
    if VTUtils.isKnoxBox3DTV(tv) then return end
    context:addOption("Watch: " .. tostring(entry.label), tv, openWindow)
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
