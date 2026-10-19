local Registry = require "KBMGB/Movie/MoviePackRegistry"
local ok, catalog = pcall(require, "KBMGB/Movie/UserMovieCatalog")
if ok and type(catalog) == "table" then
    Registry.register({
        packId = "kbm-local-user-movies",
        modId = "KBM_TVVHS",
        name = "Local user movies",
        entries = catalog.entries or {},
    })
end

function KBMGB_OnCreateBYOM(item)
    if not item or not item.getFullType then return end
    local entry = Registry.get(item:getFullType())
    if not entry then return end
    local radio = getZomboidRadio and getZomboidRadio() or nil
    local media = radio and radio.getRecordedMedia and radio:getRecordedMedia() or nil
    local data = media and media.getMediaData and media:getMediaData(entry.recMediaId) or nil
    if data and item.setRecordedMediaData then
        pcall(item.setMediaType, item, 1)
        pcall(item.setRecordedMediaData, item, data)
    end
end

return Registry
