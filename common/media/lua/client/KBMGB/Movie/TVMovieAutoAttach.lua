local Registry = require("KBMGB/Movie/MovieRegistry")

-- Creation/loot hooks attach new tapes. This bounded repair pass covers old saves,
-- transferred items and media definitions unavailable during creation.
local REPAIR_INTERVAL_MS, ITEMS_PER_TICK = 2000, 32
local nextRepair, cursor, inventory = 0, 0, nil
local mediaManager, mediaById, indexedThisPass = nil, {}, false

local function findMediaObject(mediaId)
    if not mediaId then return nil end
    local radio = getZomboidRadio and getZomboidRadio() or nil
    local rm = radio and radio.getRecordedMedia and radio:getRecordedMedia() or nil
    if not rm then return nil end
    if rm ~= mediaManager then
        mediaManager, mediaById, indexedThisPass = rm, {}, false
    end
    local key = tostring(mediaId)
    if mediaById[key] then return mediaById[key] end
    if rm.getMediaData then
        local ok, entry = pcall(rm.getMediaData, rm, key)
        if ok and entry then mediaById[key] = entry; return entry end
    end
    -- Index fallback at most once per pass; retry missing IDs on later passes.
    if not indexedThisPass and rm.getAllMediaForCategory then
        indexedThisPass = true
        local ok, list = pcall(rm.getAllMediaForCategory, rm, "VHS")
        if ok and list then
            for i = 0, list:size() - 1 do
                local entry = list:get(i)
                if entry and entry.getId then mediaById[tostring(entry:getId())] = entry end
            end
        end
    end
    return mediaById[key]
end

local function attach(item)
    if not item or not item.getFullType then return end
    local reg = Registry.get(item:getFullType())
    if not reg then return end
    -- Native item state replaces the unbounded table of stringified items.
    if item:getMediaType() == 1 and item:isRecordedMedia() and item.getMediaData then
        local current = item:getMediaData()
        if current and current:getId() == reg.recMediaId then return end
    end
    pcall(item.setMediaType, item, 1)
    local media = findMediaObject(reg.recMediaId)
    if media and item.setRecordedMediaData then pcall(item.setRecordedMediaData, item, media) end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if cursor == 0 and now < nextRepair then return end
    local player = getPlayer()
    local inv = player and player.getInventory and player:getInventory() or nil
    local items = inv and inv:getItems() or nil
    if not items then inventory, cursor, nextRepair = nil, 0, now + REPAIR_INTERVAL_MS; return end
    if inv ~= inventory then inventory, cursor = inv, 0 end
    if cursor == 0 then indexedThisPass = false end
    local finish = math.min(items:size(), cursor + ITEMS_PER_TICK)
    for i = cursor, finish - 1 do pcall(attach, items:get(i)) end
    cursor = finish
    if cursor >= items:size() then cursor, nextRepair = 0, now + REPAIR_INTERVAL_MS end
end)
