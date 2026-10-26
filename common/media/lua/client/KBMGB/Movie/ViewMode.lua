local Bridges = require "KBMGB/Movie/JavaBridges"
local M = {}
function M.isViewpointActive()
    local bridge = Bridges.get("KBMViewModeBridge")
    if not bridge then return false end
    local ok, active = pcall(bridge.isViewpointActive)
    return ok and active == true
end
return M
