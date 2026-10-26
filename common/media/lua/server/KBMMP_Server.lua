if not isServer() then return end
require "TimedActions/ISDeviceMediaAction"
local P = require "KBMMP/Protocol"
local Registry = require "KBMGB/Movie/MoviePackRegistry"
local records, limits, count, serial = {}, {}, 0, 0
local detached = {}
local snapshotSerial = 0
local STATE_KEY = "KBMMPPlayback"
local session = tostring(P.now())
local function log(s) print("[KBMMP][Server] " .. s) end
local function persist(device, s)
    local md = device:getModData()
    local now = P.now()
    local target=P.screenFor(device)
    s.kind,s.screenId=P.kind(device),target and target.id or nil
    s.address=P.address(device) or s.address
    s.volume=device:getDeviceData():getDeviceVolume()
    s.powered=device:getDeviceData():getIsTurnedOn()
    md[STATE_KEY] = {version=1,token=s.token,owner=s.owner,itemType=s.itemType,
        playing=s.playing,paused=s.paused,position=P.position(s,now),revision=s.revision,session=session,at=now}
    s.savedAt = now
end
local function restore(device)
    if records[device] then return records[device] end
    if not device or not device.getModData then return nil end
    local saved = device:getModData()[STATE_KEY]
    local entry = saved and P.entry(device)
    if not entry or saved.version~=1 or entry.itemType~=saved.itemType
            or type(saved.owner)~="string" or type(saved.token)~="string"
            or not P.number(saved.position,0,1e12) or not P.number(saved.revision,1,1e12)
            or (count>=256 and not detached[saved.token]) then return nil end
    if detached[saved.token] then
        local s=detached[saved.token]
        detached[saved.token],records[device]=nil,s
        persist(device,s)
        return s
    end
    local s = {token=saved.token,owner=saved.owner,itemType=saved.itemType,
        playing=saved.playing==true,paused=saved.paused==true,position=saved.position,
        at=P.now(),revision=saved.revision,savedAt=P.now()}
    if saved.session==session and s.playing and not s.paused and P.number(saved.at,0,1e15) then
        s.position=s.position+math.max(0,P.now()-saved.at)
    end
    records[device],count=s,count+1
    log("restored token=" .. s.token .. " owner=" .. s.owner)
    return s
end
Events.LoadGridsquare.Add(function(square)
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if object and object.getDeviceData and object:getDeviceData() then restore(object) end
    end
end)
local function reject(player, why)
    sendServerCommand(player, P.module, "Rejected", {reason=why})
    log("rejected player=" .. P.owner(player) .. " reason=" .. why)
end
local function packet(device, s, now)
    local a = device and P.address(device) or s.address
    if not a then return nil end
    local target = device and P.screenFor(device) or P.screen(s.screenId)
    return {address=a, token=s.token, owner=s.owner, itemType=s.itemType,
        kind=device and P.kind(device) or s.kind,screenId=target and target.id or nil,
        powered=device and device:getDeviceData():getIsTurnedOn() or s.powered,
        playing=s.playing, paused=s.paused, position=P.position(s, now), at=now,
        revision=s.revision, volume=device and device:getDeviceData():getDeviceVolume() or s.volume}
end
local function sync(player)
    local out, now = {}, P.now()
    for device, s in pairs(records) do
        if P.audience(player,device) or P.near(player,device,P.controlRadius) then
            local p = packet(device, s, now)
            if p then out[#out+1] = p end
        end
    end
    for _,s in pairs(detached) do
        if P.audience(player,nil,s) then
            local p=packet(nil,s,now)
            if p then out[#out+1]=p end
        end
    end
    snapshotSerial = snapshotSerial + 1
    sendServerCommand(player, P.module, "Snapshot", {version=P.version, states=out, at=now, sequence=snapshotSerial})
end
local function publish(device, s)
    persist(device,s)
    local now = P.now()
    local players = getOnlinePlayers()
    for i=0,players:size()-1 do
        local player = players:get(i)
        if P.audience(player,device) or P.near(player,device,P.controlRadius) then sync(player) end
    end
    log("state token=" .. s.token .. " revision=" .. s.revision .. " owner=" .. s.owner
        .. " powered=" .. tostring(s.powered)
        .. " playing=" .. tostring(s.playing) .. " paused=" .. tostring(s.paused)
        .. " position=" .. string.format("%.2f", P.position(s, now)))
end
local originalInvoke = ISDeviceMediaAction.invoke
function ISDeviceMediaAction:invoke()
    local dd = self.deviceData
    local device = dd and dd:getParent()
    local entry = self.secondaryItem and Registry.get(self.secondaryItem:getFullType())
    local s = restore(device)
    if not s and not entry then return originalInvoke(self) end
    if not device or not P.address(device) or not P.near(self.character, device, 3) then
        reject(self.character, "Use a nearby placed TV or projector."); return
    end
    if self.isRemove and s and not P.allowed(s, self.character) then
        reject(self.character, "Only the tape inserter or an admin can eject this tape."); return
    end
    if not self.isRemove and count >= 256 then reject(self.character, "Server playback-device limit reached."); return end
    if not self:isValid() then return end
    local fullType = self.secondaryItem and self.secondaryItem:getFullType()
    originalInvoke(self)
    if self.isRemove and not dd:hasMedia() and s then
        s.playing, s.position, s.at = false, 0, P.now()
        s.revision = s.revision + 1
        publish(device, s)
        device:getModData()[STATE_KEY] = nil
        records[device], count = nil, count - 1
    elseif not self.isRemove and dd:hasMedia() and P.entry(device) == entry then
        serial = serial + 1
        records[device] = {token=tostring(P.now()) .. ":" .. serial, owner=P.owner(self.character),
            itemType=fullType, playing=false, paused=false, position=0, at=P.now(), revision=1}
        count = count + (s and 0 or 1)
        publish(device, records[device])
    end
end
local function command(module, cmd, player, a)
    if module ~= P.module or not player then return end
    local now, name = P.now(), P.owner(player)
    local limit = limits[name]
    if not limit or now - limit.at >= 1 then limit={at=now,n=0}; limits[name]=limit end
    limit.n = limit.n + 1
    if limit.n > 8 then return end
    if cmd == "Sync" then sync(player); return end
    if type(a) ~= "table" then return end
    local device = P.resolve(a.address)
    local s = device and restore(device)
    if not s then reject(player, "Reinsert this older movie-pack tape once to initialize synchronized playback."); return end
    if a.token ~= s.token or a.revision ~= s.revision then sync(player); return end
    if not P.near(player, device, P.controlRadius) then reject(player, "Playback device out of range."); return end
    if not P.allowed(s, player) then reject(player, "Only the tape inserter or an admin controls this device."); return end
    local dd = device:getDeviceData()
    local e = P.entry(device)
    if not e or e.itemType ~= s.itemType then reject(player, "Tape changed; reinsert it."); return end
    local pos = P.position(s, now)
    if cmd == "Play" or cmd == "Toggle" then
        if not dd:getIsTurnedOn() then reject(player, "Turn the TV on first."); return end
        if cmd == "Toggle" and s.playing then s.playing, pos = false, 0
        else s.playing, s.paused = true, false end
    elseif cmd == "Pause" then
        if not s.playing then return end
        s.paused = not s.paused
    elseif cmd == "Stop" then s.playing, s.paused, pos = false, false, 0
    elseif cmd == "Seek" then
        if not P.number(a.delta, -30, 30) or not s.playing then return end
        pos = math.max(0, math.min(86400, pos + a.delta))
    elseif cmd == "Power" then
        if not dd:getIsTurnedOn() and not dd:canBePoweredHere() then return end
        dd:setIsTurnedOn(not dd:getIsTurnedOn())
        if not dd:getIsTurnedOn() then s.playing, s.paused, pos = false, false, 0 end
    elseif cmd == "Volume" then
        if not P.number(a.volume, 0, 1) then return end
        dd:setDeviceVolume(a.volume)
    else return end
    s.position, s.at, s.revision = pos, now, s.revision + 1
    publish(device, s)
end
Events.OnClientCommand.Add(command)
local lastSweep = 0
Events.OnTick.Add(function()
    local now = P.now()
    if now-lastSweep < 1 then return end
    lastSweep=now
    for device,s in pairs(records) do
        local dd = device:getDeviceData()
        local entry=P.entry(device)
        if not P.address(device) then
            -- Keep projector time/state available to the screen audience even
            -- after the server unloads the distant, unoccupied control booth.
            if s.kind=="projector" and s.playing then
                persist(device,s)
                detached[s.token]=s
            else count=count-1 end
            records[device]=nil
        elseif not entry or entry.itemType~=s.itemType then
            if P.address(device) then device:getModData()[STATE_KEY]=nil end
            records[device],count=nil,count-1
        elseif s.playing and not dd:getIsTurnedOn() then
            s.playing,s.position,s.at,s.revision=false,0,now,s.revision+1
            publish(device,s)
        elseif s.playing and now-(s.savedAt or 0)>=5 then
            persist(device,s)
        end
    end
    for name,limit in pairs(limits) do if now-limit.at > 60 then limits[name]=nil end end
end)
log("TVVHS multiplayer loaded; tape insertion ownership; persistent TV/projector state")
