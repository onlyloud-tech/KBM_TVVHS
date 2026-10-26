-- Keep map furniture intact; its persistent, invisible radio holds tapes/power.
local Scan = require "KBMProjector/WallScan"
local Locations = require "KBMProjector/ScreenLocations"
local Cinema = {}
local RANGE = 120

function Cinema.fixture(square)
    local objects = square and square:getObjects()
    if not objects then return nil end
    for i=0, objects:size()-1 do
        local object = objects:get(i)
        if Scan.isProjector(object) then return object end
    end
end

function Cinema.screen(square)
    if not square then return nil end
    local nearest, best = nil, RANGE * RANGE
    for _, target in ipairs(Locations) do
        -- Projection booths may be above the screen's ground-floor anchor.
        local dx, dy = target.x-square:getX(), target.y-square:getY()
        local distance = dx*dx + dy*dy
        if distance <= best and math.abs(target.z-square:getZ()) <= 2 then
            nearest, best = target, distance
        end
    end
    return nearest
end

function Cinema.radio(square)
    local objects = square and square:getObjects()
    if not objects then return nil end
    for i=0, objects:size()-1 do
        local object = objects:get(i)
        if instanceof(object, "IsoRadio") and object:getModData().KBMStaticProjector then
            return object
        end
    end
end

function Cinema.quiet(radio)
    -- The hosted/dedicated server has no local audio renderer and may not load
    -- ZombieBuddy's client Java bridge. It must still create the native radio
    -- that owns batteries/media. Each receiving client quiets it locally.
    if isServer() then return true end
    local bridge = KBMCinemaProjectorBridge
    if not bridge and type(com)=="table" and type(com.knoxboxprobe)=="table" then
        bridge = com.knoxboxprobe.KBMCinemaProjectorBridge
    end
    return bridge and bridge.quiet(radio) == true
end

function Cinema.ensure(square)
    if isClient() or not Cinema.fixture(square) then return nil end
    local target = Cinema.screen(square)
    if not target then return nil end
    local radio = Cinema.radio(square)
    if radio then
        Cinema.quiet(radio)
        return radio -- Never refill its battery or replace its inserted tape.
    end
    -- Native battery/media actions resolve the first wave device on the tile.
    -- Refuse an ambiguous tile instead of redirecting another radio's actions.
    if square:getDeviceData() then return nil end
    radio = IsoRadio.new(getCell(), square, nil)
    local data = radio:getDeviceData()
    data:setDeviceName("Cinema Projector")
    data:setIsTelevision(true)
    data:setMediaType(1)
    data:setIsPortable(false)
    data:setIsTwoWay(false)
    data:setTransmitRange(0)
    data:setMicRange(0)
    data:setNoTransmit(true)
    data:setChannelRaw(0)
    data:setBaseVolumeRange(12)
    data:setDeviceVolumeRaw(0.5)
    data:setIsBatteryPowered(true)
    data:setHasBattery(false)
    data:setPower(0)
    data:setUseDelta(0.009)
    data:setTurnedOnRaw(false)
    local md = radio:getModData()
    md.KBMStaticProjector = true
    md.KBMProjectorDevice = true
    md.KBMProjectorScreenId = target.id
    if not Cinema.quiet(radio) then
        print("[KBMProjector] cinema bridge unavailable; leaving fixture unchanged")
        return nil
    end
    square:AddSpecialObject(radio, square:getObjects():size())
    radio:transmitCompleteItemToClients()
    radio:transmitModData()
    triggerEvent("OnObjectAdded", radio)
    print("[KBMProjector] cinema controls at " .. square:getX() .. "," .. square:getY()
        .. "," .. square:getZ() .. " linked to " .. target.id .. "; battery required")
    return radio
end

return Cinema
