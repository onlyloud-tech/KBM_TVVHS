local Registry = require "KBMGB/System/ExtensionRegistry"

Registry.registerDevice({
    id = "tvvhs",
    modId = "KBM_TVVHS",
    name = "KnoxBox Television and VHS",
    capabilities = { "vhs", "byom", "movie-packs" },
})

Registry.registerMediaProvider({
    id = "movies",
    modId = "KBM_TVVHS",
    name = "KnoxBox Movie Pack API",
    registryModule = "KBMGB/Movie/MoviePackRegistry",
})
