"""Rebuild the KnoxBox screen classes inside the Movies & TV jar.

Requires a JDK matching the game's Java version or newer, and ZombieBuddy.jar.
Run: python tools/build-java.py --game-dir <ProjectZomboid directory>
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
JAR = ROOT / "common/media/java/KBMMovieScreenBridge.jar"
SOURCES = (
    "KBMMovieScreenBridge", "KBMProjectorFrameTap", "KBMCinemaProjectorBridge",
    "KBMPremiumTVBridge", "KBMViewModeBridge",
    "KBMCameraRecorder", "KBMRecordingAudioCapture", "KBMTVCaptionBridge",
)
NOTICES = {
    "META-INF/licenses/KnoxBox-Bridges.md": ROOT / "LICENSES/Java/KnoxBox-Bridges.md",
    "META-INF/licenses/KnoxBox-License.md": ROOT / "LICENSES/KnoxBox-License.md",
    "META-INF/licenses/GPL-3.0.txt": ROOT / "LICENSES/Java/GPL-3.0.txt",
    "META-INF/licenses/JCodec-BSD-2-Clause.txt": ROOT / "LICENSES/Java/JCodec-BSD-2-Clause.txt",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, required=True)
    parser.add_argument("--javac", default=shutil.which("javac") or "javac")
    parser.add_argument("--output", type=Path, default=JAR)
    parser.add_argument("--game-api-jar", type=Path, help="Optional compile-only game API jar")
    args = parser.parse_args()
    game = args.game_dir.resolve()
    if not JAR.is_file() or not (game / "projectzomboid.jar").is_file() or not (game / "ZombieBuddy.jar").is_file():
        parser.error("Movies & TV jar or game Java dependencies were not found")
    sources = sorted((ROOT / "java-src").rglob("*.java"))
    stubs = sorted((ROOT / "java-stubs").rglob("*.java"))
    if {source.stem for source in sources} != set(SOURCES) or not stubs:
        parser.error("Unexpected screen source or compatibility stub set")

    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        compiled = temp / "classes"
        compiled.mkdir()
        api = args.game_api_jar.resolve() if args.game_api_jar else game / "projectzomboid.jar"
        deps = os.pathsep.join(str(path) for path in (game / "ZombieBuddy.jar", api, JAR))
        result = subprocess.run(
            [str(args.javac), "-encoding", "UTF-8", "--release", "17",
             "-cp", deps, "-d", str(compiled), *(str(path) for path in sources),
             *(str(path) for path in stubs)],
            capture_output=True, text=True,
        )
        if result.returncode or result.stdout or result.stderr:
            raise RuntimeError("Java compiler reported a problem:\n" + result.stdout + result.stderr)
        outputs = {file.relative_to(compiled).as_posix():file
                   for file in (compiled / "com/knoxboxprobe").glob("*.class")}
        if any(f"com/knoxboxprobe/{name}.class" not in outputs for name in SOURCES):
            raise RuntimeError("Compiler did not produce every screen bridge")
        rebuilt = temp / "KBMMovieScreenBridge.jar"
        with ZipFile(JAR) as previous, ZipFile(rebuilt, "w") as updated:
            for info in previous.infolist():
                if (info.filename not in outputs and info.filename not in NOTICES and info.filename not in (
                        "com/knoxboxprobe/KBMViewpointScreenProbe.class",
                        "com/knoxboxprobe/KBMCinemaProjectorBridge$QuietDeviceData.class")):
                    updated.writestr(info, previous.read(info.filename))
            for name, file in sorted(outputs.items()):
                updated.write(file, name)
            for name, file in NOTICES.items():
                updated.write(file, name)
        with ZipFile(rebuilt) as checked:
            if checked.testzip() is not None or any(checked.namelist().count(name) != 1 for name in outputs):
                raise RuntimeError("Rebuilt jar failed integrity check")
            if any(name.startswith(('zombie/', 'org/lwjgl/')) for name in checked.namelist()):
                raise RuntimeError("Compile-only game stubs must not be distributed")
            if any(checked.read(name) != file.read_bytes() for name,file in NOTICES.items()):
                raise RuntimeError("Embedded license notice mismatch")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(rebuilt, args.output)
    print("Rebuilt", args.output)


if __name__ == "__main__":
    main()
