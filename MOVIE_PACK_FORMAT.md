# KnoxBox movie-pack format

A movie pack is a normal Project Zomboid Build 42 mod that declares `require=KBM_TVVHS`. It contains no Java jar and therefore creates no ZombieBuddy approval prompt.

You do not need to assemble this layout by hand. [Knoxbox Media Converter](https://github.com/onlyloud-tech/Knoxbox-Media-Converter) automatically converts videos and creates movie-pack mods, including their catalog, VHS items, sounds, and loot distribution. Download the [portable Windows release](https://github.com/onlyloud-tech/Knoxbox-Media-Converter/releases) for a ready-to-run app; its README explains setup and importing. The details below are for authors who want to inspect or create a pack manually.

## Layout

```text
KBM_ExampleMovies/
  42/
    mod.info
    media/
      video/example/<movie-id>.mp4
      sound/KBM/Example/<movie-id>/audio.ogg
      lua/shared/ExampleMovies/Catalog.lua
      lua/shared/ExampleMovies/Register.lua
      lua/shared/RecordedMedia/ExampleMoviesRecordedMedia.lua
      lua/server/Items/ExampleMoviesDistributions.lua
      scripts/ExampleMovies_Items.txt
      scripts/ExampleMovies_Sounds.txt
```

`mod.info` must use a unique mod ID and depend on Movies & TV:

```ini
name=Example KnoxBox Movie Pack
id=KBM_ExampleMovies
require=KBM_TVVHS
```

## Registration

Register the catalog during shared Lua loading:

```lua
local Registry = require "KBMGB/Movie/MoviePackRegistry"
local Catalog = require "ExampleMovies/Catalog"

Registry.register({
    packId = "author-example-movies",
    modId = "KBM_ExampleMovies",
    name = "Example Movies",
    entries = Catalog.entries,
})
```

Every `packId`, `modId`, and `itemType` must be unique. Each catalog entry uses this shape:

```lua
{
    id = "stable-id",
    itemType = "ExampleMovies.VHS_stable_id",
    recMediaId = "ExampleMovies_Recorded_stable_id",
    label = "Movie title",
    video = "example/stable-id.mp4",
    soundName = "Example_stable_id",
    audioLayout = "single",
    audioChunkSeconds = 30,
}
```

For `audioLayout = "single"`, `audioChunkSeconds` is a compatibility field in the generated catalog; the audio is stored in one `audio.ogg` file, not split into 30-second segments.

`video` is relative to the contributing mod's `media/video` directory. The movie runtime resolves it only when the declared mod is active and rejects paths that escape `media/video`.

VHS item definitions should use `OnCreate = KBMGB_OnCreateBYOM`, `Icon = vhs_tape`, and `WorldStaticModel = VhsTape`. For single-file audio, define one sound named `KBM_Movie_<soundName>_000` pointing to `<movie-id>/audio.ogg`. Older packs may omit `audioLayout` and continue to define `KBM_Movie_<soundName>_<three-digit chunk>` sounds pointing to 30-second `seg_000.ogg`, `seg_001.ogg`, and so on.

## Video requirements

- 320x180 H.264 Constrained Baseline
- Source-native frame rate
- YUV 4:2:0
- CRF 28 default
- B-frames disabled (`-bf 0 -x264-params bframes=0`)
- One mono 32 kHz Vorbis OGG audio file per movie (`audio.ogg`); 30-second OGG segments remain supported for older packs

The publisher is responsible for having the right to redistribute every included video, audio track, subtitle, and image.
