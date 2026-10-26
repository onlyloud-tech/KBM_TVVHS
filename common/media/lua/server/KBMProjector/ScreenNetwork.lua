local S = require "KBMProjector/ScreenState"
local revisions = {}

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= S.module or not player or type(args) ~= "table" then return end
    local target = S.target(args.id)
    if not target or math.abs(player:getZ() - target.z) > 2 then return end
    local dx, dy = player:getX() - target.x, player:getY() - target.y
    if dx * dx + dy * dy > 150 * 150 then return end
    local world = S.world(target)
    if not world then return end
    if command == "Set" then
        if dx * dx + dy * dy > 16 * 16 or args.revision ~= (revisions[target.id] or 0) then return end
        if not S.apply(world, args) then return end
        revisions[target.id] = (revisions[target.id] or 0) + 1
        -- The world item is saved by PZ. Do not call syncExtendedPlacement:
        -- that packet clamps signed/large offsets and omits world scale.
        print("[KBMProjector][Server] saved screen placement " .. target.id)
    elseif command ~= "Get" then return end
    local state = S.read(world)
    if not state then return end
    state.revision = revisions[target.id] or 0
    sendServerCommand(player, S.module, "State", state)
end)
