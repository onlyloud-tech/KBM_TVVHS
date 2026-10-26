local Scan = require "KBMProjector/WallScan"
local Locations = require "KBMProjector/ScreenLocations"
local logPlacement = require "KBMProjector/PlacementLog"

local MARKER = "KBMProjectorFixedScreenPlaced"
local PLACEMENT_VERSION = "KBMProjectorFixedScreenPlacementV2"
local LAYOUT_VERSION = "KBMProjectorScreenLayoutVersion"
local tick = 0
local completed = {}

local function ensureFixedScreen(target)
    if completed[target.id] then return end
    local cell = getCell()
    local square = cell and cell:getGridSquare(target.x, target.y, target.z)
    if not square then return end
    local data = square:getModData()
    local existing = Scan.findScreen(square, target.itemType)
    if existing and target.layoutVersion and data[LAYOUT_VERSION] ~= target.layoutVersion then
        -- One-time repair of the drive-in layout and tuner-clamped offsets.
        -- Keep the same item; do not create another overlapping screen.
        existing:setOffX(target.offX)
        existing:setOffY(target.offY)
        existing:setOffZ(target.offZ)
        existing:getItem():setWorldZRotation(target.rotation)
        if target.scale then existing:getItem():setWorldScale(target.scale) end
        existing:setExtendedPlacement(true)
        if not isServer() then existing:syncExtendedPlacement() end
        data[MARKER] = true
        data[PLACEMENT_VERSION] = true
        data[LAYOUT_VERSION] = target.layoutVersion
        square:transmitModdata()
        logPlacement(existing, "layout updated " .. target.id)
        print("[KBMProjector] " .. target.id .. " scale=" .. tostring(target.scale))
        completed[target.id] = true
        return
    end
    if data[PLACEMENT_VERSION] then
        if existing then
            logPlacement(existing, "saved " .. target.id)
            completed[target.id] = true
            return
        end
    end

    -- The first merged build could place a screen, then fail before setting its
    -- rotation and extended placement. Replace only that build's fixed screen.
    if data[MARKER] then
        local objects = square:getWorldObjects()
        for i = objects:size() - 1, 0, -1 do
            local world = objects:get(i)
            local item = world:getItem()
            if item and item:getFullType() == target.itemType then
                square:transmitRemoveItemFromSquare(world)
            end
        end
    end
    if Scan.hasScreen(square, target.itemType) then
        data[MARKER] = true
        data[PLACEMENT_VERSION] = true
        square:transmitModdata()
        completed[target.id] = true
        print("[KBMProjector][Server] existing fixed screen found: " .. target.id)
        logPlacement(Scan.findScreen(square, target.itemType), "existing " .. target.id)
        return
    end
    local item = square:AddWorldInventoryItem(target.itemType, target.offX, target.offY, target.offZ)
    if not item then return end
    item:setWorldZRotation(target.rotation)
    if target.scale then item:setWorldScale(target.scale) end
    local world = item:getWorldItem()
    if not world then return end
    world:setExtendedPlacement(true)
    if not isServer() then world:syncExtendedPlacement() end
    data[MARKER] = true
    data[PLACEMENT_VERSION] = true
    if target.layoutVersion then data[LAYOUT_VERSION] = target.layoutVersion end
    square:transmitModdata()
    completed[target.id] = true
    print("[KBMProjector][Server] spawned " .. target.id .. " screen at " .. target.x .. "," .. target.y .. "," .. target.z)
    logPlacement(world, "spawned " .. target.id)
end

Events.OnTick.Add(function()
    if isClient() then return end
    tick = tick + 1
    if tick % 120 ~= 0 then return end
    for _, target in ipairs(Locations) do ensureFixedScreen(target) end
end)
