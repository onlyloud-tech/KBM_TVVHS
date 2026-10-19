local MoviePackRegistry = rawget(_G, "KBMGBMoviePackRegistry")
if MoviePackRegistry then return MoviePackRegistry end

MoviePackRegistry = { packs = {}, byItemType = {} }

local function validText(value)
    return type(value) == "string" and value ~= ""
end

function MoviePackRegistry.register(pack)
    if type(pack) ~= "table" or not validText(pack.packId) or not validText(pack.modId) then
        error("KBM movie pack requires packId and modId")
    end
    if MoviePackRegistry.packs[pack.packId] then
        error("duplicate KBM movie pack id: " .. pack.packId)
    end
    local stored = { packId = pack.packId, modId = pack.modId, name = pack.name or pack.packId, entries = {} }
    for _, entry in ipairs(pack.entries or {}) do
        if type(entry) == "table" and validText(entry.itemType) and validText(entry.video) then
            if MoviePackRegistry.byItemType[entry.itemType] then
                error("duplicate KBM movie item type: " .. entry.itemType)
            end
            entry.packId = stored.packId
            entry.modId = stored.modId
            stored.entries[#stored.entries + 1] = entry
            MoviePackRegistry.byItemType[entry.itemType] = entry
        end
    end
    MoviePackRegistry.packs[stored.packId] = stored
    print("[KBMGB][MoviePack] registered " .. stored.packId .. " from " .. stored.modId
        .. " with " .. tostring(#stored.entries) .. " movie(s)")
    return stored
end

function MoviePackRegistry.get(fullType)
    return fullType and MoviePackRegistry.byItemType[tostring(fullType)] or nil
end

function MoviePackRegistry.allEntries()
    return MoviePackRegistry.byItemType
end

_G.KBMGBMoviePackRegistry = MoviePackRegistry
_G.KBMGB_RegisterMoviePack = function(pack) return MoviePackRegistry.register(pack) end
return MoviePackRegistry
