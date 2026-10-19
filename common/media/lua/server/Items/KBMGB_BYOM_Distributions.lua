require "Items/ProceduralDistributions"

local userEntries = {}

local function loadCatalog(path, destination)
    local ok, catalog = pcall(require, path)
    if not ok or type(catalog) ~= "table" then return end
    for _, entry in ipairs(catalog.entries or {}) do
        destination[#destination + 1] = entry
    end
end

loadCatalog("KBMGB/Movie/UserMovieCatalog", userEntries)

local targets = { "MovieRentalShelves", "CrateVHSTapes" }
local USER_TOTAL_WEIGHT = 25

local function addOnce(items, fullType, weight)
    for i = 1, #items, 2 do
        if items[i] == fullType then items[i + 1] = weight; return end
    end
    items[#items + 1] = fullType
    items[#items + 1] = weight
end

local function addCatalog(items, catalog, totalWeight)
    if #catalog == 0 then return end
    local weight = totalWeight / #catalog
    for _, entry in ipairs(catalog) do
        addOnce(items, entry.itemType, weight)
    end
end

local function addBYOMLoot()
    if #userEntries == 0 then return end
    local updatedTargets = 0
    for _, listName in ipairs(targets) do
        local distribution = ProceduralDistributions.list[listName]
        if distribution and distribution.items then
            addCatalog(distribution.items, userEntries, USER_TOTAL_WEIGHT)
            updatedTargets = updatedTargets + 1
        end
    end
    print("[KBMGB][Movie] registered " .. tostring(#userEntries)
        .. " imported VHS tape(s) in " .. tostring(updatedTargets) .. " loot table(s)")
end

Events.OnPreDistributionMerge.Add(addBYOMLoot)
