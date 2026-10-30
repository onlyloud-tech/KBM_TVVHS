# TVVHS regression checks

The Lua tests execute the current repository files with mocked PZ objects under Lua 5.1.
Install `lupa` in your test Python environment, then run from the repository root:

```
python -m unittest discover -s tests -v
```

`KBM_LUA_TEST_PATH` can point to an existing dependency folder instead. Tests cover bounded idle
inventory work, tape repair/retry, indexed catalog lookups, late registration, multiplayer controls,
single decoder tick ownership, projector audio-clock ownership, and Lua syntax.
These are not in-game multiplayer or renderer tests.

`java/TVUploadChecks.java` uses compile-only PZ stubs and a fake Texture to check buffer reuse,
resize behavior, cabinet/RGB preservation, and active/idle alpha markers without OpenGL. It must
be run in an isolated test JVM with stub classes ahead of game classes; never package test classes
or stubs in the runtime jar. The runner checks both absent and present Viewpoint, then compiles all
runtime Lua through the installed game's Kahlua compiler:

```
python tests/run_java_checks.py --game-dir "C:\path\to\ProjectZomboid" --javac "C:\path\to\javac.exe"
```

It defaults to the repository's built jar; `--jar` selects a staged candidate. If the game API requires
a newer class-file version than javac can read, `--game-api-jar` accepts a compile-only API copy.
That copy must never be executed or packaged. Tests run with the game's real Java runtime and game
jar. A real game check remains necessary for GL uploads, Viewpoint surfaces, audio sync and networking.
