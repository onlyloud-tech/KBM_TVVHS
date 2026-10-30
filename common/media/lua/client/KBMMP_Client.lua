if not isClient() then return end
local P = require "KBMMP/Protocol"
local Registry = require "KBMGB/Movie/MoviePackRegistry"
local ViewMode = require "KBMGB/Movie/ViewMode"
local PremiumScreen = require "KBMGB/Movie/PremiumScreen"
local C = {states={}, selected=nil}
_G.KBMMPClient = C
local active, window, raw, activeToken, lastSync, lastLog = nil,nil,nil,nil,-100,-100
local lastSnapshot = -1
local finishedToken, finishedRevision=nil,nil
local function log(s) print("[KBMMP][Client] " .. s) end
local function stateFor(device)
    local address = P.address(device)
    for _,s in ipairs(C.states) do
        local a = s.address
        if address and a.x==address.x and a.y==address.y and a.z==address.z and a.index==address.index then return s end
    end
end
-- Remote controls read authoritative per-device state, including ISO playback.
function C.getPlaybackState(device) return stateFor(device) end
function C.watch(device)
    local s=stateFor(device)
    if s then C.selected=s.token end
    local overlay=_G.KBMMPVanillaPlayback
    if s and active=="2d" and activeToken==s.token and overlay and overlay.continueMovie then
        overlay.continueMovie(device)
    end
    sendClientCommand(P.module,"Sync",{})
end
function C.request(device, command, value)
    local s = stateFor(device)
    if not s then sendClientCommand(P.module,"Sync",{}); log("waiting for playback state; reinsert an older untracked tape if needed"); return end
    local a={address=s.address,token=s.token,revision=s.revision}
    if command=="Seek" then a.delta=value elseif command=="Volume" then a.volume=value end
    sendClientCommand(P.module,command,a)
end
function C.isPlaying() return active ~= nil end
local function stop()
    if active == "3d" then _G.KBMViewpointTVPlayback.stopRemote()
    elseif active == "projector" then _G.KBMProjectorPlayback.stopRemote()
    elseif active == "2d" then
        -- Leaving range or selecting another TV is a local renderer teardown,
        -- not an instruction to stop the server's movie for other viewers.
        if window and window.app and raw then window.app.stop=raw.stop end
        _G.KBMMPVanillaPlayback.close()
    end
    active,window,raw,activeToken=nil,nil,nil,nil
end
local virtualDevice, virtualToken, virtualState
local function projectorDevice(s)
    virtualState = s
    if virtualToken == s.token then return virtualDevice end
    local square = {
        getX=function() return virtualState.address.x end,
        getY=function() return virtualState.address.y end,
        getZ=function() return virtualState.address.z end,
        getWorldObjects=function() return {size=function() return 0 end} end,
    }
    local dd = {
        getIsTurnedOn=function() return virtualState.powered ~= false end,
        getDeviceVolume=function() return virtualState.volume or 0 end,
    }
    local md = {KBMProjectorDevice=true,KBMStaticProjector=true,KBMProjectorScreenId=s.screenId}
    virtualDevice = {
        getSquare=function() return square end,
        getObjectIndex=function() return virtualState.address.index end,
        getDeviceData=function() return dd end,
        getModData=function() return md end,
    }
    virtualToken = s.token
    return virtualDevice
end
local function bindWindow(w, device)
    local app=w and w.app
    if not app then return false end
    raw={play=app.play,pause=app.pause,stop=app.stop}
    app.play=function() C.request(device,"Play") end
    app.pause=function() C.request(device,"Pause") end
    app.stop=function() C.request(device,"Stop") end
    app.togglePause=app.pause
    app.togglePower=function() C.request(device,"Power") end
    app.seekChunk=function(_,n) C.request(device,"Seek",n*10) end
    -- Volume is local attenuation here; native device volume remains shared.
    app.onKey=function(_,_,key)
        if key==Keyboard.KEY_SPACE then C.request(device,"Pause"); return true end
        if key==Keyboard.KEY_LEFT then C.request(device,"Seek",-10); return true end
        if key==Keyboard.KEY_RIGHT then C.request(device,"Seek",10); return true end
        return false
    end
    return true
end
local function render(s,device)
    if s.token==finishedToken and s.revision==finishedRevision then return end
    local entry=Registry.get(s.itemType)
    if not entry then stop(); log("missing movie pack for " .. s.itemType); return end
    if s.kind == "projector" then device = projectorDevice(s) end
    local args={}
    for k,v in pairs(entry) do args[k]=v end
    args.tv=device
    local target=s.position + (s.playing and not s.paused and math.max(0,P.now()-s.received) or 0)
    local data=device:getModData()
    local is3d=(s.kind=="3d" or data.RadioItemID ~= nil or PremiumScreen.canRender(device)) and ViewMode.isViewpointActive()
    local mode=s.kind=="projector" and "projector" or (is3d and "3d" or "2d")
    local started=activeToken~=s.token or active~=mode
    if started then
        local leavingViewpoint=active=="3d" and mode=="2d" and activeToken==s.token
        stop()
        if s.kind=="projector" then
            local api=_G.KBMProjectorPlayback
            if not api or api.mpVersion~=1 then log("projector playback API unavailable"); return end
            api.startRemote(device,args)
            active="projector"
        elseif is3d then
            local api=_G.KBMViewpointTVPlayback
            if not api or api.mpVersion~=1 then log("3D playback API unavailable"); return end
            api.startRemote(device,args)
            active="3d"
        else
            local api=_G.KBMMPVanillaPlayback
            if not api then log("TV playback API unavailable"); return end
            window=api.open(device,args,leavingViewpoint)
            if not bindWindow(window,device) then stop(); log("movie UI initialization failed"); return end
            active="2d"
        end
        activeToken=s.token
        log("opened token=" .. s.token .. " movie=" .. s.itemType .. " target=" .. target)
    end
    local position,decoded,displayed,finished=0,0,-1,false
    if active=="3d" or active=="projector" then
        local api=active=="projector" and _G.KBMProjectorPlayback or _G.KBMViewpointTVPlayback
        if api.diagnostics then decoded,displayed,finished=api.diagnostics() end
        position=api.position()
        if not finished and (started or math.abs(target-position)>1.5) then api.seekRemote(target) end
        api.pauseRemote(s.paused)
    elseif window and window.app then
        local app=window.app
        app.volume=s.volume or 1
        if app.kbm and not app.err then
            decoded,finished=app.kbm.getCurrentFrame(),app.kbm.isFinished()
            position=math.max(0,(app.kbm.getCurrentFrame()-1)/math.max(1,app.kbm.getFps()))
            if not finished and (started or math.abs(target-position)>1.5) then
                app.kbm.seekFrame(math.max(1,math.min(app.kbm.getTotalFrames(),math.floor(target*app.kbm.getFps())+1)))
                app:_stopAudio()
            end
            if s.paused then raw.pause(app) else raw.play(app) end
        end
    end
    if finished and not started then
        finishedToken,finishedRevision=s.token,s.revision
        if P.allowed(s,getPlayer()) then C.request(device,"Stop") end
        stop()
        log("movie finished token=" .. s.token)
        return
    end
    if P.now()-lastLog>=5 then
        lastLog=P.now()
        log("progress token=" .. s.token .. " rev=" .. s.revision
            .. " localSeconds=" .. string.format("%.2f",position)
            .. " targetSeconds=" .. string.format("%.2f",target) .. " paused=" .. tostring(s.paused))
        log("frames decoded=" .. tostring(decoded) .. " displayed=" .. tostring(displayed))
    end
end
Events.OnServerCommand.Add(function(module,command,args)
    if module~=P.module then return end
    if command=="Rejected" then log("rejected: " .. tostring(args.reason)); return end
    if command~="Snapshot" or args.version~=P.version then return end
    if not P.number(args.sequence,0,1e15) or args.sequence<=lastSnapshot then return end
    lastSnapshot=args.sequence
    C.states=args.states or {}
    for _,s in ipairs(C.states) do s.received=P.now() end
    local chosen,device=nil,nil
    local best=math.huge
    for _,s in ipairs(C.states) do
        local obj=P.resolve(s.address)
        -- Server-side DeviceData setters do not transmit native device packets.
        -- Reflect authoritative state even when no movie renderer is active;
        -- raw setters avoid echoing another power/volume command to the server.
        local dd=obj and obj:getDeviceData()
        if dd then
            if type(s.powered)=="boolean" and dd:getIsTurnedOn()~=s.powered then
                dd:setTurnedOnRaw(s.powered)
            end
            if P.number(s.volume,0,1) and dd:getDeviceVolume()~=s.volume then
                dd:setDeviceVolumeRaw(s.volume)
            end
        end
        if s.playing and P.audience(getPlayer(),obj,s) then
            local target=s.kind=="projector" and P.screen(s.screenId)
            local sq=obj and obj:getSquare()
            local x,y=target and target.x or sq:getX(),target and target.y or sq:getY()
            local d=(getPlayer():getX()-x)^2+(getPlayer():getY()-y)^2
            if s.token==activeToken then d=-1 end
            if s.token==C.selected then d=-2 end
            if d<best then chosen,device,best=s,obj,d end
        end
    end
    if chosen then
        local ok,err=pcall(render,chosen,device)
        if not ok then stop(); log("playback error: " .. tostring(err)) end
    else stop() end
end)
Events.OnTick.Add(function()
    if not getPlayer() then return end
    if P.now()-lastSync>=2 then lastSync=P.now(); sendClientCommand(P.module,"Sync",{}) end
end)
Events.OnGameStart.Add(function()
    lastSnapshot=-1
    C.states, C.selected={},nil
    require "RadioCom/ISRadioAction"
    local oldPlay=ISRadioAction.performTogglePlayMedia
    function ISRadioAction:performTogglePlayMedia()
        if P.entry(self.device) then return C.request(self.device,"Toggle") end
        return oldPlay(self)
    end
    local oldPower=ISRadioAction.performToggleOnOff
    function ISRadioAction:performToggleOnOff()
        if P.entry(self.device) and stateFor(self.device) then return C.request(self.device,"Power") end
        return oldPower(self)
    end
    local oldVolume=ISRadioAction.performSetVolume
    function ISRadioAction:performSetVolume()
        if P.entry(self.device) then return C.request(self.device,"Volume",self.secondaryItem) end
        return oldVolume(self)
    end
    local oldMute=ISRadioAction.performMuteVolume
    function ISRadioAction:performMuteVolume()
        if P.entry(self.device) then return C.request(self.device,"Volume",0) end
        return oldMute(self)
    end
    local oldUnmute=ISRadioAction.performUnMuteVolume
    function ISRadioAction:performUnMuteVolume()
        if P.entry(self.device) then return C.request(self.device,"Volume",self.secondaryItem) end
        return oldUnmute(self)
    end
    if RWMMedia then
        local oldUpdate=RWMMedia.update
        function RWMMedia:update()
            oldUpdate(self)
            local s=stateFor(self.device)
            if s then self.toggleOnOffButton:setTitle(s.playing and self.textStop or self.textPlay) end
        end
    end
    -- Recorded-media duration is unrelated to the actual movie; no native
    -- StartPlayMedia call is needed for synchronized movie playback.
    log("TVVHS multiplayer loaded; TV/projector snapshots every 2 seconds")
end)
Events.OnFillWorldObjectContextMenu.Add(function(_,context,objects,test)
    if test then return end
    for _,device in ipairs(objects or {}) do
        local s=stateFor(device)
        -- Clicking the custom TV hits its visible world item, while playback
        -- belongs to the invisible radio linked by inventory-item ID.
        if not s and device.getSquare then
            local item=device.getItem and device:getItem()
            local square=device:getSquare()
            local signals=square and square:getObjects()
            if signals then
                for i=0,signals:size()-1 do
                    local radio=signals:get(i)
                    local md=radio.getModData and radio:getModData()
                    if not item or (md and md.RadioItemID==item:getID()) then
                        local linked=stateFor(radio)
                        if linked then device,s=radio,linked; break end
                    end
                end
            end
        end
        if s then
            if s.playing then
                local overlay=_G.KBMMPVanillaPlayback
                local resume=overlay and overlay.canContinue and overlay.canContinue(device)
                if not (resume and context.getOptionFromName and context:getOptionFromName("Continue Playing")) then
                    context:addOption(resume and "Continue Playing" or "MP Movie: Watch",device,C.watch)
                end
            end
            context:addOption("MP Movie: " .. s.owner .. " controls this tape",nil,function() end)
            if P.allowed(s,getPlayer()) then
                context:addOption(s.playing and "MP Movie: Stop" or "MP Movie: Play",device,C.request,s.playing and "Stop" or "Play")
                if s.playing then context:addOption("MP Movie: Pause / Resume",device,C.request,"Pause") end
            end
            return
        end
    end
end)
