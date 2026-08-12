# Deltarune Editor

A small macOS app for editing DELTARUNE save files — inventory, money, party stats and
equipment — designed to be safe enough to hand to a nine-year-old.

> **Unofficial.** Not affiliated with or endorsed by Toby Fox. Editing save files is
> always at your own risk. This app backs up before every change and can restore any
> previous state, but keep your own copy of your saves too.

<!-- Add a screenshot here: ![Deltarune Editor](docs/screenshot.png) -->

---

## What it does

- Edit the **inventory**, **key items** and **storage** using real item names rather than
  numbers, filtered to the chapter you're playing.
- Change **Dark Dollars**, **Light World money** and party **HP, stats and equipment**.
- Pick who's **in your party**.
- Browse and restore a full **history** of every change, with one click back to how things
  were before you first ran it.
- An **Advanced** tab for story flags, raw line editing, and a field inspector showing
  which line of the file each value came from.

It opens the save you were last playing, and shows where you are — *"Cold Place · Tenna
Prefight Speech Started"* — so it's obvious the right file is loaded.

---

## Safety

Editing a save file badly can destroy a playthrough, so most of the design is about not
doing that.

**It never rewrites a save file.** Most save editors parse a file into a model and
serialize the whole thing back, which means a bug anywhere in the mapping can corrupt parts
of the file the player never touched. This app keeps the original lines verbatim and
replaces only the individual lines that were edited. Everything it doesn't model —
including the 2,500–9,999 flag lines — is preserved by construction.

**It proves it can reproduce a file before it will change it.** On load, the untouched
lines are reassembled and compared against the original bytes. If they don't match
exactly, the app says so and refuses to write. Editing is impossible unless it has already
demonstrated it can reproduce the file byte for byte.

**Every write is backed up first.** The whole save folder is snapshotted before any change,
with a SHA-256 per file, into `~/Library/Application Support/DeltaruneEditor/` — outside
the game folder, so a Steam "verify integrity" can't wipe the history. Restoring takes its
own snapshot first, so restoring is itself undoable. The very first snapshot is kept
forever.

**It won't write while the game is open.** DELTARUNE holds save state in memory and writes
it out on its own schedule, so edits made while it's running would silently vanish.

**Writes are atomic.** Temp file in the same directory, then an atomic replace. A save is
never left half-written.

**Values are clamped.** The simple screens hold values inside sensible ranges, which also
keeps every number below the point where the game switches to exponential notation. The
Advanced tab lifts the limits deliberately.

---

## Requirements

| | |
|---|---|
| macOS | 15 or later |
| Xcode | 16 or later (developed on Xcode 27 / Swift 6.4) |
| Node.js | 18+ — **only** to regenerate the game data; not needed to build or run |

No other dependencies. The app is a single self-contained bundle of about 3 MB.

## Build and run

```sh
git clone https://github.com/<you>/DeltaRuneEditor.git
cd DeltaRuneEditor

swift build                     # build the library and app
./Tools/build-app.sh            # assemble build/DeltaruneEditor.app (ad-hoc signed)
open build/DeltaruneEditor.app
```

`build-app.sh` produces a universal binary (arm64 + x86_64). Ad-hoc signing is enough to
run it on the machine that built it; see below for distributing to another Mac.

## Running the tests

**The test suite needs real save files, and none are included** — save files are personal
data, carrying the player's chosen names, playtime and a Steam account id.

To run the full suite, copy your own save folder in:

```sh
cp -R ~/Library/"Application Support"/com.tobyfox.deltarune/* \
      Tests/DeltaruneCoreTests/Fixtures/
swift test
```

Copy, don't move — those are your actual saves. Everything in that directory is gitignored,
so nothing you put there can be committed by accident.

Without fixtures, `swift test` still builds and runs the tests that don't need save data —
number formatting, filename parsing, format detection, atomic writes, the bundled game
data — and reports the rest as skipped.

The tests assert properties that hold for *any* valid save, such as reproducing a file byte
for byte, editing one field rewriting exactly one line, and the format being detected from
the line count. They don't assert facts about one particular playthrough, so any save
folder will do. Including `dr.ini` is worthwhile: several tests cross-check the save
against it, which is the strongest available evidence that the field mapping is aligned.

## Signing for distribution

To send the app to another Mac without Gatekeeper warnings you need your own Apple
Developer Program membership.

1. Create a **Developer ID Application** certificate — Xcode → Settings → Accounts → your
   team → Manage Certificates → **+**. Requires the Account Holder role; App Store
   certificates can't sign for distribution outside the store. Confirm it with:

   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

2. Store notarization credentials once, using your own Apple ID, team id and an
   [app-specific password](https://appleid.apple.com):

   ```sh
   xcrun notarytool store-credentials "DR_NOTARY"
   ```

3. Build, sign, notarize, staple and package:

   ```sh
   BUNDLE_ID=com.yourname.deltaruneeditor ./Tools/release.sh
   ```

`release.sh` checks both prerequisites before doing anything, runs the tests, and produces
a notarized, stapled `.dmg` that opens on another Mac with no warning, even offline. The
first `codesign` after creating a certificate shows a keychain prompt — choose **Always
Allow** so later builds don't stall.

## Regenerating the game data

```sh
node Tools/export-game-data.mjs
```

Clones [tenna-editor](https://github.com/tennaproject/tenna-editor) and extracts its item,
weapon, armour, spell, character, room and story-milestone tables into
`Sources/DeltaruneCore/Resources/gamedata.json`, resolving per-chapter renames (Dark Candy
becomes "Darker Candy" from Chapter 4). Only needed when the game updates; the generated
JSON is committed.

The app icon can be regenerated with `swift Tools/make-icon.swift Tools`.

---

## The save format

Worked out from real save files rather than documentation, and verified by reproducing
them byte for byte.

| Format | Chapters | Lines  | Stat blocks | Inventory |
|--------|----------|--------|-------------|-----------|
| V1     | 1        | 10,318 | 4           | 13 × interleaved consumable/key/weapon/armor |
| V2     | 2–5      | 3,055  | 5           | 13 consumable+key pairs, 48 weapon+armor pairs, 72 storage |

The format is identified purely by line count. The layout is a flat, positional list —
a cursor walks it from the top:

```
playerName, vesselName, 5 blanks, party[3], money, xp, lv, inv, invc, inDarkWorld,
then per stat block: hp, maxHp, atk, def, magic, guts, weapon, armor1, armor2,
                     weaponStyle, 4 × weaponStats, 12 × spells,
then boltSpeed, grazeAmount, grazeSize, inventory, tension, maxTension,
     the Light World block, the flag array, and finally plot, room, time.
```

Details that catch people out:

- Line endings are **CRLF**.
- Every line has a **trailing space** *except* the first seven.
- There is **no trailing newline** on the last line.
- Values at or above 1e6 use GameMaker's exponential form: `1304870` is written
  `1.30487e+06`.
- Plot values can be **fractional** — Chapter 4 has 238.1, 238.61, 238.65.
- The 13-wide inventory arrays hold **12 usable slots**; the 13th is an end-of-list marker
  written as `999`. Writing an item there corrupts the inventory, so the app refuses to.
- Stat blocks are indexed by **character id**, not party position: 0 is an unused empty
  slot, and Kris is 1. Chapter 1 has four blocks because Noelle isn't in it yet.

`dr.ini` sits beside the saves and drives the file-select screen — `[G0]` for Chapter 1,
`[G_2_0]` for Chapter 2 onward, holding the name, level, room and playtime. It's patched
key by key, so `[VHS]`, `[URA]` and every untouched entry survive.

## Project layout

```
Sources/DeltaruneCore/       all the logic, no UI
  Model/                     SaveDocument, SaveParser, DrIni, GMNumber, EditPolicy
  Services/                  BackupStore, SaveEditor, AtomicFile, GameData, SaveFolder
  Resources/gamedata.json    generated name tables
Sources/DeltaruneEditor/     the SwiftUI app
Tests/DeltaruneCoreTests/    the test suite
Tools/                       build, release, icon and data-export scripts
```

---

## Credits

Save-format knowledge and the item name tables come from
[tenna-editor](https://github.com/tennaproject/tenna-editor) by the Tenna Project, used in
modified form under the zlib licence. The "Tenna Editor" name and logo are excluded from
that licence and are not used here. If you want a full-featured, actively maintained
DELTARUNE save editor that runs in a browser, use theirs.

DELTARUNE is by Toby Fox.

## Licence

[MIT](LICENSE).
