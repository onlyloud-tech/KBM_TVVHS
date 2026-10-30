-- Remote discovery runs only when the player opens the menu, never on a tick.
local M = {}

function M.isCustomItem(item)
    local kind = item and item.getFullType and item:getFullType()
    return kind == "KBM.ScreenTV" or kind == "KBMViewpointProbe.ScreenTV"
end

function M.isNativeTV(device)
    local sprite = device and device.getSprite and device:getSprite()
    local name = sprite and sprite:getName()
    if not name or not name:match("^appliances_television_01_[0-7]$") then return false end
    local dd = device.getDeviceData and device:getDeviceData()
    return dd and dd:getIsTelevision() == true or false
end

function M.linkedRadio(square, item)
    local objects = square and square.getObjects and square:getObjects()
    if not objects or not item then return nil end
    for i = 0, objects:size() - 1 do
        local device = objects:get(i)
        if instanceof(device, "IsoRadio") then
            local md = device:getModData()
            if md and md.RadioItemID == item:getID() then return device end
        end
    end
end

function M.nativeOnSquare(square)
    local objects = square and square.getObjects and square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            local device = objects:get(i)
            if M.isNativeTV(device) then return device end
        end
    end
end

function M.canUse(device, player)
    local data = device and device.getDeviceData and device:getDeviceData()
    return player and data and data:canPlayerRemoteInteract(player) or false
end

function M.nearest(player)
    local current = player and player.getSquare and player:getSquare()
    local cell = current and current:getCell()
    if not cell then return nil end
    local best, bestDistance = nil, math.huge
    local function consider(device, x, y)
        if not M.canUse(device, player) then return end
        local distance = (x - current:getX()) ^ 2 + (y - current:getY()) ^ 2
        if distance < bestDistance then best, bestDistance = device, distance end
    end
    for x = current:getX() - 10, current:getX() + 10 do
        for y = current:getY() - 10, current:getY() + 10 do
            local square = cell:getGridSquare(x, y, current:getZ())
            local objects = square and square.getObjects and square:getObjects()
            if objects then
                for i = 0, objects:size() - 1 do
                    local device = objects:get(i)
                    if M.isNativeTV(device) then consider(device, x, y) end
                end
            end
            local items = square and square.getWorldObjects and square:getWorldObjects()
            if items then
                for i = 0, items:size() - 1 do
                    local world = items:get(i)
                    local item = world and world.getItem and world:getItem()
                    if M.isCustomItem(item) then consider(M.linkedRadio(square, item), x, y) end
                end
            end
        end
    end
    return best
end

return M
