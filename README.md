# KnoxBox Media: Movies and TV

Watch VHS tapes and home recordings on televisions in Project Zomboid Build 42. The mod also adds three camcorders, a KnoxBox 3D Television, and playback through existing cinema projectors at the configured theater and drive-in. Movie packs are distributed separately.

## Requirements

- KnoxBox Media Framework (`KBM_Core`)
- ZombieBuddy 2.3.4 or later
- Viewpoint only for the optional 3D view

## Projector and Viewpoint screen light

Right-click an existing cinema projector near a configured screen and choose **Projector Device Options**. Insert a battery and a KnoxBox VHS, turn it on, and press Play. The original furniture stays in place and connects to the nearest configured theater or drive-in screen, including from an upstairs booth. Battery charge and inserted tapes persist across saves; playback stops when power runs out. Native radio static, TV sound effects, and floating broadcast captions are suppressed on these devices.

Movie audio fades with distance. Projectors play at full volume within eighteen tiles of the linked screen and fade to silence at twenty-four tiles. Televisions play at full volume within two tiles of the TV and fade to silence at twelve tiles. Projectors emit movie audio from the screen, rather than the control booth.

Screens are currently configured for the two locations in `common/media/lua/shared/KBMProjector/ScreenLocations.lua`; other cinemas are not automatically fitted with screens. Private projector-box prototypes and calibration controls are not included.

Premium Technologies and ValuTech televisions support physical screen playback in Viewpoint with the optional **6277 3D models for Viewpoint** model pack. Each television has four fitted facing profiles, and its video surface follows furniture placement height. Other TVs retain the KnoxBox movie overlay. Leaving Viewpoint keeps the overlay hidden; right-click the TV and choose **Continue Playing** to watch in isometric view.

## Multiplayer playback

TVVHS includes experimental multiplayer playback for movie packs on vanilla TVs, the KnoxBox 3D TV, and configured projector screens. No separate multiplayer addon is required. Enable TVVHS, its dependencies, and the same movie packs on the server and clients. The server sends movie identity, playback time, and control state; each client decodes its installed movie files.

The tape inserter controls playback until ejection; admins can override. Ownership and playback checkpoints are saved with the device. Projector audiences receive state near the linked screen, including when the distant control booth is outside their loaded area. A client currently plays one selected movie at a time. Older tapes inserted before synchronized state existed may need one ejection and reinsertion.

Host-session playback has been tested. Two-player synchronization has automated receiver coverage but has not been verified with a second live client. Synchronization is approximate, with snapshots every two seconds. Camcorder recording and playback of local home-recording files remain single-player only.

The optional `viewpoint-shaderpack/KnoxBoxScreens` folder contains the original KnoxBox shader pack that keeps supported movie screens visible in a dark room. Copy that folder to `Zomboid/viewpoint-shaderpacks/KnoxBoxScreens`, then select **KnoxBox Screens** in Viewpoint Graphics > Modern. Viewpoint loads custom packs from that user folder, so the shader is a separate installation step. Playback works without it, but screens respond to room lighting.

## Playing movies

Find tapes in the world or add a movie pack. [Knoxbox Media Converter](https://github.com/onlyloud-tech/Knoxbox-Media-Converter) automatically converts your videos and installs them into a personal library or a separate movie-pack mod. Its [Windows releases](https://github.com/onlyloud-tech/Knoxbox-Media-Converter/releases) include a portable executable, so you do not need Node.js to use it. Movie packs depend on `KBM_TVVHS`; see [MOVIE_PACK_FORMAT.md](MOVIE_PACK_FORMAT.md) if you want to inspect or build a pack yourself.

On first launch, Windows Defender SmartScreen may warn that the converter is unrecognized because the executable is unsigned. This is expected for this release. Choose **More info** and then **Run anyway** to launch it.

For the KnoxBox 3D Television, equip a base-game TV remote and use its inventory action to open the KnoxBox remote for power, playback, pause, and volume controls.

To make a home recording, find a blank VHS tape in VHS storage or a camera shop, then right-click a camcorder to insert it. Equip the camcorder and press **Alt+E** to start recording; press **Alt+E** again to stop. The shortcut is ignored while typing. Each completed recording uses one blank tape and creates a playable home-recording VHS. You can eject an unused blank from the camcorder.

The mod includes no commercial movies. Only distribute movies and artwork for which you have redistribution rights.

## Building the Java bridge

The Java sources for the TV and projector are in `java-src`. Run `python tools/build-java.py --game-dir <ProjectZomboid directory>` with a JDK matching the game's Java version or newer (JDK 25 for the tested game build). Use `--javac` to select its compiler. The small `java-stubs` directory provides compile-only signatures and is never included in the runtime jar. The game and ZombieBuddy supply their classes at runtime; the existing bundled jar supplies JCodec and its notices.

The source repository includes build tools, compile-only stubs, native recording-helper sources, and the optional shader pack. A Workshop mod needs only `42`, `common`, and `LICENSES`; do not copy development tools into the runtime mod. Original content and third-party license terms are included in `LICENSES`; Java files with their own license notices retain those terms.

The Windows camcorder audio helper is embedded in the existing jar at `com/knoxboxprobe/KBMAudioCapture.exe`. Its sources are in `native-src/audio-capture`, derived from Microsoft's ApplicationLoopback sample with microphone capture added. To rebuild it, use MSVC, a Windows SDK supporting process loopback capture, and Microsoft.Windows.ImplementationLibrary NuGet package version `1.0.210204.1`. Configure CMake with `-DWIL_INCLUDE_DIR=<package>/include`, build the Release target, and replace that same jar resource with the resulting `KBMAudioCapture.exe`. The Java build preserves this resource and the bundled JCodec classes. Microsoft and WIL notices are included in `LICENSES/Audio`.
