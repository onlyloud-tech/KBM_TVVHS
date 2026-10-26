local Cinema = require "KBMProjector/CinemaProjector"

Events.LoadGridsquare.Add(function(square)
    if not isClient() and Cinema.fixture(square) then Cinema.ensure(square) end
end)

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "KBM_TVVHS" or command ~= "CinemaProjector" or not player
            or type(args) ~= "table" then return end
    local x,y,z = tonumber(args.x),tonumber(args.y),tonumber(args.z)
    if not x or not y or not z or x~=math.floor(x) or y~=math.floor(y) or z~=math.floor(z)
            or math.abs(player:getX()-x)>10 or math.abs(player:getY()-y)>10
            or math.floor(player:getZ())~=z then return end
    local square = getCell():getGridSquare(x,y,z)
    local radio = Cinema.ensure(square)
    if radio then
        sendServerCommand(player, "KBM_TVVHS", "CinemaProjectorReady", {x=x,y=y,z=z})
    end
end)
