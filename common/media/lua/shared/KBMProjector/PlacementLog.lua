local Scan = require "KBMProjector/WallScan"

return function(world, reason)
    local item = world and world.getItem and world:getItem() or nil
    if not item or not Scan.isScreenType(item:getFullType()) then return end
    print(string.format(
        "[KBMProjector][Placement] %s type=%s tile=(%d,%d,%d) offset=(%.3f,%.3f,%.3f) rotation=(%.3f,%.3f,%.3f)",
        reason, item:getFullType(), world:getX(), world:getY(), world:getZ(),
        world:getOffX(), world:getOffY(), world:getOffZ(),
        item:getWorldXRotation(), item:getWorldYRotation(), item:getWorldZRotation()))
end
