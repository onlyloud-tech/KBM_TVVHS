local MovieRegistry = {}
local PackRegistry = require "KBMGB/Movie/MoviePackRegistry"

-- Device releases contain no technical-test tape. Local movies and optional
-- content packs register themselves through MoviePackRegistry.
local entries = {
    ["KBM.RecordedVHS"] = {
        itemType = "KBM.RecordedVHS",
        recMediaId = "KBM_HomeRecording",
        label = "Home Recording",
        recordingId = "",
    },
}

function MovieRegistry.get(fullType)
    if not fullType then return nil end
    return entries[tostring(fullType)] or PackRegistry.get(fullType)
end

function MovieRegistry.isTape(fullType)
    return MovieRegistry.get(fullType) ~= nil
end

function MovieRegistry.all()
    local combined = {}
    for itemType, entry in pairs(entries) do combined[itemType] = entry end
    for itemType, entry in pairs(PackRegistry.allEntries()) do combined[itemType] = entry end
    return combined
end

return MovieRegistry
