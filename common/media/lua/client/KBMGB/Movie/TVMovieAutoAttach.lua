local Registry = require("KBMGB/Movie/MovieRegistry")

local attached = {}

local function findMediaObject(mediaId)
    local radio = getZomboidRadio and getZomboidRadio() or nil
    local rm = radio and radio.getRecordedMedia and radio:getRecordedMedia() or nil
    if not rm or not rm.getAllMediaForCategory then return nil end
    local ok, list = pcall(rm.getAllMediaForCategory, rm, "VHS")
    if not ok or not list then return nil end
    for i = 0, list:size() - 1 do
        local entry = list:get(i)
        if entry and entry.getId and tostring(entry:getId()) == tostring(mediaId) then return entry end
    end
    return nil
end

local function attach(item)
    if not item or not item.getFullType then return end
    local reg = Registry.get(item:getFullType())
    if not reg then return end
    local key = tostring(item)
    if attached[key] then return end
    pcall(item.setMediaType, item, 1)
    local media = findMediaObject(reg.recMediaId)
    if media and item.setRecordedMediaData then pcall(item.setRecordedMediaData, item, media) end
    if item:getMediaType() == 1 and item:isRecordedMedia() then attached[key] = true end
end

Events.OnTick.Add(function()
    local player = getPlayer()
    local inv = player and player.getInventory and player:getInventory() or nil
    local items = inv and inv:getItems() or nil
    if not items then return end
    for i = 0, items:size() - 1 do pcall(attach, items:get(i)) end
end)
