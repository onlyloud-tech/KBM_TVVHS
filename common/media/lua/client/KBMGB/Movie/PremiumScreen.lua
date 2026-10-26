local Bridges = require "KBMGB/Movie/JavaBridges"
local M = {}
local active = false
function M.canRender(device)
    local bridge = Bridges.get("KBMPremiumTVBridge")
    if not bridge or not Bridges.get("KBMProjectorFrameTap") then return false end
    local ok, supported = pcall(bridge.supports, device)
    return ok and supported == true
end
function M.start(device)
    local bridge, tap = Bridges.get("KBMPremiumTVBridge"), Bridges.get("KBMProjectorFrameTap")
    if not bridge or not tap then return false end
    if bridge.start(device) ~= true then
        print("[KBMPremiumTV] " .. tostring(bridge.getStatus()))
        return false
    end
    local model = bridge.getScreenModel and bridge.getScreenModel(device) or "KBM.PremiumScreen"
    tap.setScreenModel(model)
    tap.start()
    active = true
    return true
end
function M.stop()
    if not active then return end
    active = false
    local bridge, tap = Bridges.get("KBMPremiumTVBridge"), Bridges.get("KBMProjectorFrameTap")
    if bridge then bridge.stop() end
    if tap then tap.stop() end
end
function M.update()
    local tap = Bridges.get("KBMProjectorFrameTap")
    if active and tap then tap.update() end
end
function M.getDisplayedFrame()
    if not active then return nil end
    local tap = Bridges.get("KBMProjectorFrameTap")
    -- Zero means this screen has not uploaded a picture yet. Do not substitute
    -- the legacy cabinet counter while the independent surface owns playback.
    return tap and tap.getDisplayedFrame and tonumber(tap.getDisplayedFrame()) or 0
end
return M
