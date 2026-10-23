-- Record the visible game view onto a blank VHS loaded in a camcorder.
require "KBMGB/Movie/RecordableTape"
require "ISUI/ISUIHandler"
require "ISUI/ISTextBox"
require "TimedActions/ISBaseTimedAction"
local TAPE_TYPE = "KBM.RecordedVHS"
local BLANK_TAPE_TYPE = "KBM.BlankVHS"
local CAMERA_TYPES = {
    ["KBM.Camcorder"] = true,
    ["KBM.Camcorder2"] = true,
    ["KBM.Camcorder3"] = true,
}
local WRITING_TOOLS = {
    ["Base.Pen"] = true, ["Base.Pencil"] = true,
    ["Base.BluePen"] = true, ["Base.GreenPen"] = true,
    ["Base.RedPen"] = true, ["Base.PenFancy"] = true,
    ["Base.PenMultiColor"] = true, ["Base.PenSpiffo"] = true,
    ["Base.PencilSpiffo"] = true, ["Base.MarkerBlack"] = true,
    ["Base.MarkerBlue"] = true, ["Base.MarkerGreen"] = true,
    ["Base.MarkerRed"] = true,
}
local pendingId = nil
local pendingPlayer = nil
local pendingCamera = nil
local poseAction = nil
local hudHiddenByCamera = false

local function hideHudForRecording()
    if not ISUIHandler or not ISUIHandler.allUIVisible then return end
    local ok, err = pcall(ISUIHandler.setVisibleAllUI, false)
    if not ok then
        print("[KBMGB][Camera] Could not hide HUD: " .. tostring(err))
        return
    end
    ISUIHandler.allUIVisible = false
    hudHiddenByCamera = true
end

local function restoreHudAfterRecording()
    if not hudHiddenByCamera then return end
    hudHiddenByCamera = false
    -- The player may have used PZ's Toggle UI key while recording.
    if ISUIHandler and not ISUIHandler.allUIVisible then
        local ok, err = pcall(ISUIHandler.setVisibleAllUI, true)
        if ok then ISUIHandler.allUIVisible = true
        else print("[KBMGB][Camera] Could not restore HUD: " .. tostring(err)) end
    end
end

local function bridge()
    if type(com) == "table" and type(com.knoxboxprobe) == "table" then
        return com.knoxboxprobe.KBMCameraRecorder
    end
    return nil
end

local function notify(player, message)
    print("[KBMGB][Camera] " .. tostring(message))
    if player and player.Say then pcall(player.Say, player, tostring(message)) end
end

local function findItem(items, fullType)
    for _, entry in ipairs(items or {}) do
        local item = entry.items and entry.items[1] or entry
        if item and item.getFullType and item:getFullType() == fullType then
            return item
        end
    end
    return nil
end

local function hasWritingTool(player)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory then return false end
    for fullType in pairs(WRITING_TOOLS) do
        if inventory:containsTypeRecurse(fullType) then return true end
    end
    return false
end

local function hasBlankLoaded(camera)
    return camera and camera:getModData().KBMBlankVHSLoaded == true
end

local function insertBlankTape(args)
    local player, camera = args.player, args.camera
    if not player or not camera or hasBlankLoaded(camera) then return end
    local inventory = player:getInventory()
    local blank = inventory and inventory:getFirstTypeRecurse(BLANK_TAPE_TYPE) or nil
    if not blank then
        notify(player, "A blank VHS tape is needed.")
        return
    end
    local container = blank:getContainer()
    if not container then return end
    container:Remove(blank)
    camera:getModData().KBMBlankVHSLoaded = true
    notify(player, "Blank VHS tape inserted.")
end

local function ejectBlankTape(args)
    local player, camera = args.player, args.camera
    if not player or not hasBlankLoaded(camera) then return end
    local inventory = player:getInventory()
    if inventory and inventory:AddItem(BLANK_TAPE_TYPE) then
        camera:getModData().KBMBlankVHSLoaded = nil
        notify(player, "Blank VHS tape ejected.")
    end
end

local function saveTapeLabel(args, button)
    if not button or button.internal ~= "OK" then return end
    local player, tape = args.player, args.tape
    if not player or not tape or tape:getFullType() ~= TAPE_TYPE or not hasWritingTool(player) then
        notify(player, "A pen, pencil, or marker is needed to label the tape.")
        return
    end
    local label = tostring(button.parent.entry:getText() or "")
    label = label:gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if not label or label == "" then return end
    label = label:sub(1, 40)
    tape:getModData().KBMRecordingLabel = label
    tape:setName("VHS - " .. label)
    notify(player, "Labeled tape: " .. label)
end

local function labelTape(args)
    local tape = args.tape
    local data = tape:getModData()
    local current = data.KBMRecordingLabel or "Home Recording"
    local dialog = ISTextBox:new(0, 0, 340, 180, "Label VHS tape", current,
        args, saveTapeLabel, args.playerNum)
    dialog:initialise()
    dialog.maxChars = 40
    dialog.noEmpty = true
    dialog:addToUIManager()
    dialog.entry:focus()
end

local CameraRecordingAction = ISBaseTimedAction:derive("KBMCameraRecordingAction")

function CameraRecordingAction:isValid()
    return self.camera and CAMERA_TYPES[self.camera:getFullType()] == true
        and hasBlankLoaded(self.camera)
end

function CameraRecordingAction:start()
    local player = self.character

    if not hasBlankLoaded(self.camera) then
        notify(player, "Insert a blank VHS tape before recording.")
        self:forceStop()
        return
    end
    local recorder = bridge()
    if not recorder then
        notify(player, "Camera bridge unavailable.")
        self:forceStop()
        return
    end
    if player:getPrimaryHandItem() ~= self.camera then player:setPrimaryHandItem(self.camera) end
    local cameraType = self.camera:getFullType()
    if cameraType == "KBM.Camcorder3" then
        self:setActionAnim("kbmrecordcamcorder3")
    elseif cameraType == "KBM.Camcorder2" then
        self:setActionAnim("kbmrecordcamcorder2")
    else
        self:setActionAnim("kbmrecordcamcorder")
    end
    self:setOverrideHandModels(self.camera, nil)
    local ok, started = pcall(recorder.start)
    if not ok or not started then
        local errorText = ok and recorder.getError() or started
        notify(player, "Could not start recording: " .. tostring(errorText))
        self:forceStop()
        return
    end
    pendingId = tostring(recorder.getRecordingId())
    pendingPlayer = player
    pendingCamera = self.camera
    local micEnabled = getCore and getCore():getOptionVoiceEnable() == true
    notify(player, micEnabled and "Recording started; microphone capture enabled by VOIP setting."
        or "Recording started; microphone capture disabled by VOIP setting.")
    print("[KBMGB][Camera] Recording started. Press Alt+E to stop; 10-minute limit.")
    hideHudForRecording()
end

function CameraRecordingAction:update()
    local recorder = bridge()
    if not recorder or not recorder.isRecording or not recorder.isRecording() then
        self:forceStop()
    end
end

function CameraRecordingAction:stop()
    local recorder = bridge()
    if recorder and recorder.isRecording and recorder.isRecording() then pcall(recorder.stop) end
    if poseAction == self then poseAction = nil end
    restoreHudAfterRecording()
    ISBaseTimedAction.stop(self)
end

function CameraRecordingAction:perform()
    local recorder = bridge()
    if recorder and recorder.isRecording and recorder.isRecording() then pcall(recorder.stop) end
    if poseAction == self then poseAction = nil end
    restoreHudAfterRecording()
    ISBaseTimedAction.perform(self)
end

function CameraRecordingAction:forceCancel()
    if poseAction == self then poseAction = nil end
    restoreHudAfterRecording()
end

function CameraRecordingAction:new(player, camera)
    local action = ISBaseTimedAction.new(self, player)
    action.camera = camera
    action.maxTime = 100000
    action.stopOnWalk = false
    action.stopOnRun = false
    return action
end

local function startRecording(args)
    local player = args and args.player
    if not args or not hasBlankLoaded(args.camera) then
        notify(player, "Insert a blank VHS tape before recording.")
        return
    end
    local recorder = bridge()
    if not recorder then notify(player, "Camera bridge unavailable; check the Movies & TV addon."); return end
    if isClient and isClient() then
        notify(player, "Camcorder recording currently supports single-player saves.")
        return
    end
    if poseAction or pendingId then return end
    poseAction = CameraRecordingAction:new(player, args.camera)
    ISTimedActionQueue.add(poseAction)
end

local function stopRecording(args)
    local recorder = bridge()
    if not recorder then return end
    local ok, errorText = pcall(recorder.stop)
    if not ok then notify(args and args.player, "Stop failed: " .. tostring(errorText)); return end
    if poseAction then poseAction:forceStop() end
    restoreHudAfterRecording()
    notify(args and args.player, "Finalizing recording...")
end

local function stopRecordingKey(key)
    if key ~= Keyboard.KEY_E or not poseAction then return end
    if not (Keyboard.isKeyDown(Keyboard.KEY_LMENU)
        or Keyboard.isKeyDown(Keyboard.KEY_RMENU)) then return end
    local recorder = bridge()
    if recorder and recorder.isRecording and recorder.isRecording() then
        stopRecording({ player = pendingPlayer })
    end
end

local function contextMenu(playerNum, context, items)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player then return end
    local tape = findItem(items, TAPE_TYPE)
    if tape then
        local args = { player = player, playerNum = playerNum, tape = tape }
        local option = context:addOption("Label VHS tape", args, labelTape)
        if not hasWritingTool(player) then
            option.notAvailable = true
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = "Requires a pen, pencil, or marker in inventory."
            option.toolTip = tooltip
        end
    end
    local camera = findItem(items, "KBM.Camcorder3")
        or findItem(items, "KBM.Camcorder2") or findItem(items, "KBM.Camcorder")
    if not camera then return end
    local recorder = bridge()
    if recorder and recorder.isRecording and recorder.isRecording() then
        context:addOption("Stop camera recording", { player = player }, stopRecording)
    elseif not pendingId and not (recorder and recorder.isFinalizing and recorder.isFinalizing()) then
        local args = { player = player, camera = camera }
        if hasBlankLoaded(camera) then
            context:addOption("Eject blank VHS tape", args, ejectBlankTape)
        else
            local insert = context:addOption("Insert blank VHS tape", args, insertBlankTape)
            if not player:getInventory():containsTypeRecurse(BLANK_TAPE_TYPE) then
                insert.notAvailable = true
                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip.description = "Requires a blank VHS tape in inventory."
                insert.toolTip = tooltip
            end
        end
        local record = context:addOption("Record video with camcorder", args, startRecording)
        if not hasBlankLoaded(camera) then
            record.notAvailable = true
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = "Insert a blank VHS tape first."
            record.toolTip = tooltip
        end
    end
end

local function captureTick()
    local recorder = bridge()
    if recorder and recorder.isRecording and recorder.isRecording() then
        local ok, err = pcall(recorder.captureTick)
        if not ok then notify(pendingPlayer, "Capture failed: " .. tostring(err)) end
    end
end

local function finishTick()
    if not pendingId then return end
    local recorder = bridge()
    if not recorder then return end
    if not recorder.isRecording() then restoreHudAfterRecording() end
    local ok, ready = pcall(recorder.consumeReady, pendingId)
    if ok and ready then
        local player = pendingPlayer or getPlayer()
        local inv = player and player.getInventory and player:getInventory() or nil
        local tape = inv and inv.AddItem and inv:AddItem(TAPE_TYPE) or nil
        if tape then
            tape:getModData().KBMRecordingId = pendingId
            tape:getModData().KBMRecordingLabel = "Home Recording"
            if KBMGB_OnCreateRecordedVHS then KBMGB_OnCreateRecordedVHS(tape) end
            if tape.setName then pcall(tape.setName, tape, "VHS - Home Recording") end
            if pendingCamera then pendingCamera:getModData().KBMBlankVHSLoaded = nil end
            local audioMessage = recorder.hasCapturedAudio and recorder.hasCapturedAudio()
                and " with audio" or " without captured audio"
            notify(player, "Recording saved" .. audioMessage .. " to a VHS tape. Frames: "
                .. tostring(recorder.getEncodedFrames()) .. ", dropped: "
                .. tostring(recorder.getDroppedFrames()))
        else
            notify(player, "Recording saved, but VHS creation failed: " .. pendingId)
        end
        pendingId, pendingPlayer, pendingCamera = nil, nil, nil
    elseif not recorder.isRecording() and not recorder.isFinalizing() then
        local errorText = recorder.getError and recorder.getError() or "unknown error"
        notify(pendingPlayer, "Recording failed: " .. tostring(errorText))
        pendingId, pendingPlayer, pendingCamera = nil, nil, nil
    end
end

Events.OnFillInventoryObjectContextMenu.Add(contextMenu)
Events.OnKeyPressed.Add(stopRecordingKey)
Events.OnRenderTick.Add(captureTick)
Events.OnTick.Add(finishTick)
print("[KBMGB][Camera] Camcorder recording actions loaded")
