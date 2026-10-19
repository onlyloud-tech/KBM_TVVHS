local function mediaData()
    local radio = getZomboidRadio and getZomboidRadio() or nil
    local recorded = radio and radio.getRecordedMedia and radio:getRecordedMedia() or nil
    return recorded and recorded.getMediaData and recorded:getMediaData("KBM_HomeRecording") or nil
end

function KBMGB_OnCreateRecordedVHS(item)
    if not item then return end
    local data = mediaData()
    if item.setMediaType then pcall(item.setMediaType, item, 1) end
    if data and item.setRecordedMediaData then
        pcall(item.setRecordedMediaData, item, data)
    end
end

return { attach = KBMGB_OnCreateRecordedVHS }
