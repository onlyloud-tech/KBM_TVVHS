local S = require "KBMProjector/ScreenState"
local Locations = require "KBMProjector/ScreenLocations"
local states, editing = {}, {}
local tick = 0
KBMScreenNetwork = {}

function KBMScreenNetwork.begin(world)
    local state = S.read(world)
    if not state then return false end
    editing[state.id] = true
    return true
end

function KBMScreenNetwork.finish(world, playerNum)
    local state = S.read(world)
    if not state then return false end
    editing[state.id] = nil
    state.revision = states[state.id] and states[state.id].revision or 0
    sendClientCommand(getSpecificPlayer(playerNum), S.module, "Set", state)
    return true
end

Events.OnServerCommand.Add(function(module, command, state)
    if module ~= S.module or command ~= "State" or not S.valid(state) then return end
    local previous = states[state.id]
    if type(state.revision) ~= "number" or (previous and state.revision < previous.revision) then return end
    states[state.id] = state
    if not editing[state.id] then S.apply(S.world(S.target(state.id)), state) end
end)

Events.OnTick.Add(function()
    if not isClient() then return end
    tick = tick + 1
    if tick % 120 ~= 0 then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    for _, target in ipairs(Locations) do
        -- Request again after chunk loading, late join, or a spawn packet that
        -- arrived before the final rotation/scale was set on the server.
        if S.world(target) and not editing[target.id] then
            sendClientCommand(player, S.module, "Get", {id=target.id})
        end
    end
end)
