local VTUtils = require("KBMGB/System/VTUtils")

local WatchReward = {}

local STEP_SECONDS = 30
local MAX_STEPS = 16

function WatchReward.new()
    return { lastMs = nil, lastFrame = nil, watchedSeconds = 0, awardedSteps = 0 }
end

-- Credit time only while the movie advances at a plausible viewing speed.
-- Rewinding, fast-forwarding, pauses, and a startup frame jump give no credit.
function WatchReward.tick(session, player, playing, frame, fps)
    if not session then return end
    local now = VTUtils.nowMs()
    frame, fps = tonumber(frame), tonumber(fps)
    local previousMs, previousFrame = session.lastMs, session.lastFrame
    session.lastMs, session.lastFrame = now, frame
    if not playing or not player or not frame or not fps or fps <= 0
        or not previousMs or not previousFrame then return end

    local elapsed = (now - previousMs) / 1000
    local advanced = (frame - previousFrame) / fps
    if elapsed <= 0 or elapsed > 5 or advanced <= 0 or advanced > elapsed * 1.5 + 0.25 then return end
    if session.awardedSteps >= MAX_STEPS then return end

    session.watchedSeconds = session.watchedSeconds + math.min(advanced, elapsed)
    local stats = player.getStats and player:getStats() or nil
    if not stats then return end
    while session.watchedSeconds >= STEP_SECONDS and session.awardedSteps < MAX_STEPS do
        session.watchedSeconds = session.watchedSeconds - STEP_SECONDS
        session.awardedSteps = session.awardedSteps + 1
        stats:remove(CharacterStat.BOREDOM, 1)
        stats:remove(CharacterStat.UNHAPPINESS, 0.5)
    end
end

return WatchReward
