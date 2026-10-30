"""Isolated buffer/camera-mode tests; no graphics context, game launch or mod install."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir', type=Path, required=True)
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--jar', type=Path, default=ROOT/'common/media/java/KBMMovieScreenBridge.jar')
    parser.add_argument('--game-api-jar', type=Path)
    args = parser.parse_args()
    game = args.game_dir.resolve()
    jar = args.jar.resolve()
    api = args.game_api_jar.resolve() if args.game_api_jar else game/'projectzomboid.jar'
    classes, fixture = ROOT/'build/optimization-tests/classes', ROOT/'build/optimization-tests/fixture'
    classes.mkdir(parents=True, exist_ok=True)
    fixture.mkdir(parents=True, exist_ok=True)
    deps = [jar, api, game/'ZombieBuddy.jar']
    cp = os.pathsep.join(map(str, deps))
    subprocess.run([args.javac, '--release', '17', '-encoding', 'UTF-8', '-cp', cp, '-d', str(classes),
                    *map(str, (ROOT/'java-stubs').rglob('*.java')), str(ROOT/'tests/java/TVUploadChecks.java'),
                    str(ROOT/'tests/java/LuaSyntaxChecks.java')], check=True)
    subprocess.run([args.javac, '--release', '17', '-d', str(fixture), str(ROOT/'tests/java/viewpoint/core/View.java')], check=True)
    cp = os.pathsep.join(map(str, [classes, jar, game/'projectzomboid.jar', game/'ZombieBuddy.jar']))
    java = str(game/'jre64/bin/java.exe')
    subprocess.run([java, '-cp', cp, 'TVUploadChecks'], check=True)
    subprocess.run([java, '-cp', cp+os.pathsep+str(fixture), 'TVUploadChecks', 'present'], check=True)
    subprocess.run([java, '-cp', cp, 'LuaSyntaxChecks', str(ROOT/'common/media/lua'),
                    str(ROOT/'42/media/lua')], check=True)


if __name__ == '__main__':
    main()
