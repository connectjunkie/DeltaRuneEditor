# Test fixtures — bring your own saves

This directory is intentionally empty in the repository. **Everything in it except this
file is gitignored.**

The test suite validates the save format against *real* DELTARUNE save files rather than
files it generates itself. That's deliberate: a save produced by this project's own
serializer would only prove the parser agrees with itself. Real files are what revealed
that the 13th inventory slot is an end-of-list marker written as `999`, and that plot
values can be fractional (`238.61`).

Real save files are personal data — they carry the player's chosen names, playtime, and
a Steam account id in `steam_autocloud.vdf` — so none are committed here.

## To run the full suite

Copy your own save folder in:

```sh
cp -R ~/Library/"Application Support"/com.tobyfox.deltarune/* \
      Tests/DeltaruneCoreTests/Fixtures/
swift test
```

Then remove them again when you're done, or just leave them — they're ignored by git
either way.

**Copy, don't move.** These are your actual saves.

## What the tests expect

Any valid save folder works. The suite discovers whatever `filech*` files are present and
asserts properties that hold for *any* save — that a file can be reproduced byte for byte,
that editing one field rewrites exactly one line, that the format is detected from the line
count — rather than facts about one particular playthrough.

`dr.ini` is optional but worth including: several tests cross-check the save against it,
which is the strongest available evidence that the field mapping is aligned.

## Without fixtures

`swift test` still builds and runs. The tests that don't need save files — number
formatting, filename parsing, format detection, atomic writes, the bundled game data —
pass as normal. The rest report as skipped.
