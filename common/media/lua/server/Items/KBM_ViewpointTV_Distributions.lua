require "Items/ProceduralDistributions"

local function addTV()
    for _, target in ipairs({
        { name = "CrateTV", weight = 20 },
        { name = "ElectronicStoreAppliances", weight = 10 },
    }) do
        local distribution = ProceduralDistributions.list[target.name]
        local items = distribution and distribution.items
        if items then
            local found = false
            for i = 1, #items, 2 do
                if items[i] == "KBM.ScreenTV" then
                    found = true
                    break
                end
            end
            if not found then
                items[#items + 1] = "KBM.ScreenTV"
                items[#items + 1] = target.weight
            end
        end
    end

    -- Bedroom packing boxes and crates use mixed storage pools, but do not
    -- select CrateTV by default. Add that pool so stored TVs can appear there.
    local bedroom = SuburbsDistributions and SuburbsDistributions.bedroom
    for _, containerName in ipairs({ "cardboardbox", "crate" }) do
        local container = bedroom and bedroom[containerName]
        local procList = container and container.procList
        if procList then
            local found = false
            for _, entry in ipairs(procList) do
                if entry.name == "CrateTV" then
                    found = true
                    break
                end
            end
            if not found then
                procList[#procList + 1] = { name = "CrateTV", min = 0, max = 1, weightChance = 10 }
            end
        end
    end
end

Events.OnPreDistributionMerge.Add(addTV)

-- A store-wide guarantee cannot be expressed with per-container loot weights.
-- Room loading also covers stores whose containers were filled in an older save.
local function placeStoreTV(origin, fallbackContainer)
    if isClient() then return end
    local room = origin and origin:getRoom()
    local roomDef = room and room:getRoomDef()
    if not roomDef then return end
    local roomName = roomDef:getName()
    if roomName ~= "electronicstore" and roomName ~= "electronicsstore" then return end

    local key = tostring(roomDef:getX()) .. ":" .. tostring(roomDef:getY()) .. ":" .. tostring(origin:getZ())
    local spawned = ModData.getOrCreate("KBM_ScreenTV_StoreSpawns")
    if spawned[key] then return end

    local cell = getCell()
    for radius = 0, 6 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = cell:getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                    if square and square:getRoom() == room and square:isFree(false) then
                        if square:AddWorldInventoryItem("KBM.ScreenTV", 0.5, 0.5, 0) then
                            spawned[key] = true
                            return
                        end
                    end
                end
            end
        end
    end

    -- Some layouts have no open loaded tile near the first filled container.
    -- Keep the guarantee by using that container instead.
    if fallbackContainer and fallbackContainer:AddItem("KBM.ScreenTV") then
        spawned[key] = true
    end
end

Events.LoadGridsquare.Add(function(square)
    placeStoreTV(square)
end)

Events.OnFillContainer.Add(function(roomName, containerType, container)
    if roomName ~= "electronicstore" and roomName ~= "electronicsstore" then return end
    local parent = container and container:getParent()
    placeStoreTV(parent and parent:getSquare(), container)
end)

local function addCamcorder2()
    local displayCase = ProceduralDistributions.list.CameraStoreDisplayCase
    local items = displayCase and displayCase.items
    if not items then return end
    for i = 1, #items, 2 do
        if items[i] == "KBM.Camcorder2" then return end
    end
    items[#items + 1] = "KBM.Camcorder2"
    items[#items + 1] = 4
end

Events.OnPreDistributionMerge.Add(addCamcorder2)

local function addCamcorder3()
    local displayCase = ProceduralDistributions.list.CameraStoreDisplayCase
    local items = displayCase and displayCase.items
    if not items then return end
    for i = 1, #items, 2 do
        if items[i] == "KBM.Camcorder3" then return end
    end
    items[#items + 1] = "KBM.Camcorder3"
    items[#items + 1] = 4
end

Events.OnPreDistributionMerge.Add(addCamcorder3)

local function addVHSCollectionBox()
    for _, listName in ipairs({ "CrateVHSTapes", "MovieRentalShelves" }) do
        local distribution = ProceduralDistributions.list[listName]
        local items = distribution and distribution.items
        if items then
            local found = false
            for i = 1, #items, 2 do
                if items[i] == "KBM.VHSCollectionBox" then
                    found = true
                    break
                end
            end
            if not found then
                items[#items + 1] = "KBM.VHSCollectionBox"
                items[#items + 1] = 5
            end
        end
    end
end

Events.OnPreDistributionMerge.Add(addVHSCollectionBox)
