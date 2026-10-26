local Locations = require "KBMProjector/ScreenLocations"
local Scan = require "KBMProjector/WallScan"
local S = { module = "KBMScreenPlacement" }
local fields = {"offX", "offY", "offZ", "rotX", "rotY", "rotZ", "scale"}

function S.target(id)
    for _, target in ipairs(Locations) do
        if target.id == id then return target end
    end
end

function S.world(target)
    local cell = getCell()
    local square = cell and cell:getGridSquare(target.x, target.y, target.z)
    return square and Scan.findScreen(square, target.itemType)
end

function S.read(world)
    if not world or not world:getItem() then return end
    local item = world:getItem()
    for _, target in ipairs(Locations) do
        if world:getX() == target.x and world:getY() == target.y and world:getZ() == target.z
            and item:getFullType() == target.itemType then
            return {id=target.id, itemId=item:getID(), offX=world:getOffX(),
                offY=world:getOffY(), offZ=world:getOffZ(), rotX=item:getWorldXRotation(),
                rotY=item:getWorldYRotation(), rotZ=item:getWorldZRotation(),
                -- InventoryItem exposes setWorldScale(), but no Lua getter.
                -- Persist protocol scale alongside the item for later sessions.
                scale=item:getModData().KBMScreenScale or target.scale or 1}
        end
    end
end

function S.valid(state)
    if type(state) ~= "table" or not S.target(state.id) then return false end
    if type(state.itemId) ~= "number" then return false end
    for i, field in ipairs(fields) do
        local value = state[field]
        if type(value) ~= "number" or value ~= value then return false end
        local low, high = -1, 2
        if i >= 4 and i <= 6 then low, high = 0, 360 end
        if field == "scale" then low, high = 0.1, 2 end
        if value < low or value > high then return false end
    end
    return true
end

function S.apply(world, state)
    if not S.valid(state) or not world or world:getItem():getID() ~= state.itemId then return false end
    world:setOffX(state.offX)
    world:setOffY(state.offY)
    world:setOffZ(state.offZ)
    local item = world:getItem()
    item:setWorldXRotation(state.rotX)
    item:setWorldYRotation(state.rotY)
    item:setWorldZRotation(state.rotZ)
    item:setWorldScale(state.scale)
    item:getModData().KBMScreenScale = state.scale
    world:setExtendedPlacement(true)
    return true
end

return S
