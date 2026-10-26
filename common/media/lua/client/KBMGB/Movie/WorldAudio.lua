-- Distance envelope for movie audio emitted by a placed screen/device.
local WorldAudio = {}

local FULL_VOLUME_TILES = 2
local SILENT_TILES = 12
local FLOOR_DISTANCE_TILES = 3

function WorldAudio.gain(device, player, fullVolumeTiles, silentTiles)
    fullVolumeTiles = fullVolumeTiles or FULL_VOLUME_TILES
    silentTiles = silentTiles or SILENT_TILES
    local source = device and device.getSquare and device:getSquare() or nil
    local listener = player and player.getSquare and player:getSquare() or nil
    if not source or not listener then return 0 end

    local listenerX = player.getX and player:getX() or listener:getX() + 0.5
    local listenerY = player.getY and player:getY() or listener:getY() + 0.5
    local dx = source:getX() + 0.5 - listenerX
    local dy = source:getY() + 0.5 - listenerY
    local dz = (source:getZ() - listener:getZ()) * FLOOR_DISTANCE_TILES
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance <= fullVolumeTiles then return 1 end
    if distance >= silentTiles then return 0 end

    local t = (distance - fullVolumeTiles) / (silentTiles - fullVolumeTiles)
    return 1 - t * t * (3 - 2 * t)
end

return WorldAudio
