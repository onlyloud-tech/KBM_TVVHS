local Cinema = require "KBMProjector/CinemaProjector"
local Window = require "KBMGB/Movie/DeviceWindow"
local tracked = setmetatable({}, {__mode="k"})
local pending

local function track(object)
    if object and instanceof(object,"IsoRadio") and object:getModData().KBMStaticProjector then
        if Cinema.quiet(object) then tracked[object]=true end
    end
end

Events.OnObjectAdded.Add(track)
Events.LoadGridsquare.Add(function(square)
    local objects=square:getObjects()
    for i=0,objects:size()-1 do track(objects:get(i)) end
end)

local function open(index, square)
    local player=getSpecificPlayer(index)
    if not player or not Cinema.fixture(square) then return end
    if math.abs(player:getX()-square:getX())>=10 or math.abs(player:getY()-square:getY())>=10
            or math.floor(player:getZ())~=square:getZ() then return end
    local radio=Cinema.radio(square)
    if not radio and not isClient() then radio=Cinema.ensure(square) end
    if radio then
        track(radio)
        Window.activate(player,radio)
    elseif isClient() then
        pending={index=index,x=square:getX(),y=square:getY(),z=square:getZ(),ticks=300}
        sendClientCommand(player,"KBM_TVVHS","CinemaProjector",{x=pending.x,y=pending.y,z=pending.z})
    else
        print("[KBMProjector] no cinema controls: screen link or an unambiguous radio tile required")
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(index,context,objects,test)
    if test or context:getOptionFromName("Projector Device Options") then return end
    for _,object in ipairs(objects or {}) do
        local square=object and object.getSquare and object:getSquare()
        if Cinema.fixture(square) and Cinema.screen(square) then
            context:addOption("Projector Device Options",index,open,square)
            return
        end
    end
end)

Events.OnTick.Add(function()
    for radio in pairs(tracked) do
        local square=radio:getSquare()
        if not square or not Cinema.fixture(square) then
            if square and not isClient() then square:transmitRemoveItemFromSquare(radio) end
            tracked[radio]=nil
        else
            -- Only this fixture's native captions/SFX are suppressed. Movie
            -- audio has its own emitter and keeps the user-selected volume.
            Cinema.quiet(radio)
        end
    end
    if pending then
        pending.ticks=pending.ticks-1
        local square=getCell():getGridSquare(pending.x,pending.y,pending.z)
        if Cinema.radio(square) then
            local index=pending.index
            pending=nil
            open(index,square)
        elseif pending.ticks<=0 then
            pending=nil
            print("[KBMProjector] cinema controls did not arrive from server")
        end
    end
end)
