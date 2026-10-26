local Scan = {}

Scan.projectorSprite = "appliances_com_01_87" -- north-facing cinema projector
local projectorSprites = {
    appliances_com_01_84=true, appliances_com_01_85=true,
    appliances_com_01_86=true, appliances_com_01_87=true,
}
Scan.screenType = "KBMProjector.Screen"
Scan.driveInScreenType = "KBMProjector.DriveInScreen"

function Scan.isScreenType(fullType)
    return fullType == Scan.screenType
        or fullType == Scan.driveInScreenType
end

function Scan.isProjector(object)
    local sprite = object and object.getSprite and object:getSprite()
    return sprite and projectorSprites[sprite:getName()] == true
end

function Scan.findNorthWall(projector, cell)
    local origin = projector and projector.getSquare and projector:getSquare()
    if not origin or not cell then return nil end
    for distance = 2, 6 do
        local square = cell:getGridSquare(origin:getX(), origin:getY() - distance, origin:getZ())
        if not square then return nil end
        local wall = square:getWall(true)
        if wall then
            local props = wall:getProperties()
            if props and (props:has("WallN") or props:has("WallNW")) then
                return square, distance
            end
            return nil
        end
    end
    return nil
end

function Scan.findScreen(square, expectedType)
    local objects = square and square.getWorldObjects and square:getWorldObjects()
    if not objects then return nil end
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item then
            local fullType = item:getFullType()
            if not expectedType and Scan.isScreenType(fullType) then return objects:get(i) end
            if expectedType and fullType == expectedType then return objects:get(i) end
        end
    end
    return nil
end

function Scan.hasScreen(square, expectedType)
    return Scan.findScreen(square, expectedType) ~= nil
end

return Scan
