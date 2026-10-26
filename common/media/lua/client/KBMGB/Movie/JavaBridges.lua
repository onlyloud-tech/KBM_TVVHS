-- ZombieBuddy can expose Java classes only under their full package path.
-- Resolve both forms, as the existing movie/projector bridges already do.
local M = {}
function M.get(name)
    local direct = _G[name]
    if direct then return direct end
    if type(com) == "table" and type(com.knoxboxprobe) == "table" then
        return com.knoxboxprobe[name]
    end
end
return M
