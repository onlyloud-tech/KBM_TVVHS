local P = { module = "KBM_MP", version = 1, radius = 12, controlRadius = 10 }
local Registry = require "KBMGB/Movie/MoviePackRegistry"
local Locations = require "KBMProjector/ScreenLocations"
local Cinema = require "KBMProjector/CinemaProjector"

function P.screen(id)
    for _, target in ipairs(Locations) do if target.id == id then return target end end
end
function P.kind(device)
    local md = device and device.getModData and device:getModData() or {}
    if md.KBMProjectorDevice then return "projector" end
    return md.RadioItemID and "3d" or "2d"
end
function P.screenFor(device)
    if P.kind(device) ~= "projector" then return nil end
    local md = device:getModData()
    return P.screen(md.KBMProjectorScreenId) or Cinema.screen(device:getSquare())
end
function P.audience(player, device, packet)
    local target = packet and packet.kind == "projector" and P.screen(packet.screenId)
        or (device and P.screenFor(device))
    if not target then return P.near(player, device, P.radius) end
    if not player then return false end
    local dx, dy = player:getX()-(target.x+.5), player:getY()-(target.y+.5)
    local dz = (player:getZ()-target.z)*3
    return dx*dx + dy*dy + dz*dz <= 24*24
end
function P.number(n, lo, hi)
    return type(n) == "number" and n == n and n >= lo and n <= hi
end
function P.now() return getTimestampMs() / 1000 end
function P.position(s, now)
    return math.max(0, s.position + (s.playing and not s.paused and math.max(0, now - s.at) or 0))
end
function P.near(player, device, radius)
    local sq = device and device.getSquare and device:getSquare()
    return player and sq and math.floor(player:getZ()) == sq:getZ()
        and (player:getX()-sq:getX())^2 + (player:getY()-sq:getY())^2 <= radius^2
end
function P.address(device)
    local sq = device and device.getSquare and device:getSquare()
    if not sq then return nil end
    if not device.getObjectIndex then return nil end
    local i = device:getObjectIndex()
    if i < 0 then return nil end
    return { x=sq:getX(), y=sq:getY(), z=sq:getZ(), index=i }
end
function P.resolve(a)
    if type(a) ~= "table" then return nil end
    for _, k in ipairs({"x", "y", "z", "index"}) do
        if not P.number(a[k], -1000000, 1000000) or a[k] ~= math.floor(a[k]) then return nil end
    end
    if a.index < 0 or a.index > 10000 then return nil end
    local cell = getCell()
    local sq = cell and cell:getGridSquare(a.x, a.y, a.z)
    local objects = sq and sq:getObjects()
    local obj = objects and a.index < objects:size() and objects:get(a.index) or nil
    local dd = obj and obj.getDeviceData and obj:getDeviceData()
    return dd and dd:getIsTelevision() and obj or nil
end
function P.entry(device)
    local dd = device and device.getDeviceData and device:getDeviceData()
    if not dd or not dd:getIsTelevision() or not dd:hasMedia() then return nil end
    local media = dd:getMediaData()
    if not media then return nil end
    return Registry.getByMediaId(media:getId())
end
function P.owner(player) return tostring(player:getUsername()) end
function P.allowed(s, player)
    return s.owner == P.owner(player) or string.lower(tostring(player:getAccessLevel())) == "admin"
end
return P
