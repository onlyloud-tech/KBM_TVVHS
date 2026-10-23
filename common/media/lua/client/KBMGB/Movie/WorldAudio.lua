-- Distance envelope for movie audio emitted by a placed television.
local WorldAudio = {}

local FULL_VOLUME_TILES = 2
local SILENT_TILES = 12
local FLOOR_DISTANCE_TILES = 3

function WorldAudio.gain(device, player)
    local source = device and device.getSquare and device:getSquare() or nil
    local listener = player and player.getSquare and player:getSquare() or nil
    if not source or not listener then return 0 end

    local listenerX = player.getX and player:getX() or listener:getX() + 0.5
    local listenerY = player.getY and player:getY() or listener:getY() + 0.5
    local dx = source:getX() + 0.5 - listenerX
    local dy = source:getY() + 0.5 - listenerY
    local dz = (source:getZ() - listener:getZ()) * FLOOR_DISTANCE_TILES
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance <= FULL_VOLUME_TILES then return 1 end
    if distance >= SILENT_TILES then return 0 end

    local t = (distance - FULL_VOLUME_TILES) / (SILENT_TILES - FULL_VOLUME_TILES)
    return 1 - t * t * (3 - 2 * t)
end

return WorldAudio
