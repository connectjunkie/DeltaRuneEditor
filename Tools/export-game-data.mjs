#!/usr/bin/env node
//
// Generates Sources/DeltaruneCore/Resources/gamedata.json — the item, weapon, armour,
// spell and character name tables the UI shows instead of raw numeric ids.
//
// The names come from tenna-editor (https://github.com/tennaproject/tenna-editor, zlib),
// which maintains them properly. Hand-transcribing several hundred entries would be
// slow and wrong; this reads them from the source of truth instead.
//
// Run it only when the game updates:
//     node Tools/export-game-data.mjs
//
// Needs network access the first time (to clone tenna) and npx (to fetch esbuild).
// Neither is needed to build or run the app — the generated JSON is committed.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUTPUT = path.join(ROOT, 'Sources/DeltaruneCore/Resources/gamedata.json');
const CHECKOUT = path.join(ROOT, '.cache/tenna-editor');
const REPO = 'https://github.com/tennaproject/tenna-editor.git';

const CHAPTERS = [1, 2, 3, 4, 5];

/** Category name in our output -> [id constant, metadata constant] in tenna. */
const CATEGORIES = {
  consumables: ['CONSUMABLES', 'CONSUMABLES_META'],
  keyItems: ['KEYITEMS', 'KEYITEMS_META'],
  weapons: ['WEAPONS', 'WEAPONS_META'],
  armors: ['ARMORS', 'ARMORS_META'],
  spells: ['SPELLS', 'SPELLS_META'],
  characters: ['CHARACTERS', 'CHARACTERS_META'],
  lightWorldItems: ['LIGHTWORLDITEMS', 'LIGHTWORLDITEMS_META'],
};

function run(command, args, options = {}) {
  return execFileSync(command, args, { stdio: 'pipe', encoding: 'utf8', ...options });
}

function ensureCheckout() {
  if (existsSync(CHECKOUT)) {
    console.log('Using cached checkout at .cache/tenna-editor');
    return;
  }
  console.log('Cloning tenna-editor…');
  mkdirSync(path.dirname(CHECKOUT), { recursive: true });
  run('git', ['clone', '--depth', '1', REPO, CHECKOUT]);
}

function bundleDataModule() {
  const outDir = mkdtempSync(path.join(tmpdir(), 'deltarune-data-'));
  const outFile = path.join(outDir, 'data.mjs');

  console.log('Bundling tenna data tables…');
  run('npx', [
    '--yes', 'esbuild',
    'src/data/index.ts',
    '--bundle',
    '--format=esm',
    '--platform=node',
    '--log-level=error',
    '--alias:@types=./src/types',
    '--alias:@data=./src/data',
    '--alias:@utils=./src/utils',
    `--outfile=${outFile}`,
  ], { cwd: CHECKOUT });

  return { outFile, outDir };
}

/**
 * Resolve an entry's properties for a chapter. Entries can override their own display
 * name per chapter — Dark Candy becomes "Darker Candy" from Chapter 4 on.
 */
function resolveForChapter(properties, chapter) {
  if (typeof properties?.getOverrides !== 'function') return properties ?? {};
  let overrides = {};
  try {
    overrides = properties.getOverrides({ chapter, saveSlot: 0 }) ?? {};
  } catch {
    // Some entries inspect flags we don't have here; the base name is fine.
    overrides = {};
  }
  return { ...properties, ...overrides };
}

function buildCategory(ids, meta) {
  const entries = [];

  for (const [key, id] of Object.entries(ids)) {
    if (typeof id !== 'number') continue;

    const base = resolveForChapter(meta[id], 1);
    const entry = {
      id,
      key,
      name: base?.displayName ?? key,
    };
    // Item descriptions are deliberately not exported. They're verbatim creative text
    // from the game, and nothing in the UI displays them — only the names are needed.

    // Record only the chapters whose name actually differs.
    const perChapter = {};
    for (const chapter of CHAPTERS) {
      const resolved = resolveForChapter(meta[id], chapter);
      const name = resolved?.displayName ?? entry.name;
      if (name !== entry.name) perChapter[chapter] = name;
    }
    if (Object.keys(perChapter).length > 0) entry.namesByChapter = perChapter;

    entries.push(entry);
  }

  return entries.sort((a, b) => a.id - b.id);
}

/**
 * Turn an internal key into something readable, for the many rooms whose displayName is
 * blank. DW_SNOW_ZONE -> "Snow Zone". The DW_/LW_ prefixes are Dark/Light World markers
 * and just add noise for a player.
 */
function prettifyKey(key) {
  return key
    .replace(/^(DW|LW)_/, '')
    .toLowerCase()
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

/** Room id -> name, so the app can say where he is rather than printing a number. */
function buildRooms(data) {
  const { ROOMS, ROOMS_META } = data;
  const rooms = [];

  for (const [key, id] of Object.entries(ROOMS)) {
    if (typeof id !== 'number') continue;
    const displayName = ROOMS_META?.[id]?.displayName;
    rooms.push({
      id,
      key,
      name: displayName && displayName.trim() ? displayName : prettifyKey(key),
    });
  }

  return rooms.sort((a, b) => a.id - b.id);
}

/** Chapter -> named story milestones, for turning a plot number into progress. */
function buildPlotPoints(data) {
  const byChapter = {};

  for (const chapter of CHAPTERS) {
    const meta = data.PLOT_META_BY_CHAPTER?.[chapter];
    if (!meta) continue;

    byChapter[chapter] = Object.entries(meta)
      .map(([value, properties]) => ({
        value: Number(value),
        name: properties?.displayName ?? `Plot ${value}`,
        ...(properties?.unused ? { unused: true } : {}),
      }))
      .filter((entry) => Number.isFinite(entry.value))
      .sort((a, b) => a.value - b.value);
  }

  return byChapter;
}

async function main() {
  ensureCheckout();
  const commit = run('git', ['rev-parse', '--short', 'HEAD'], { cwd: CHECKOUT }).trim();

  const { outFile, outDir } = bundleDataModule();
  const data = await import(pathToFileURL(outFile).href);

  const output = {
    _comment:
      'Generated by Tools/export-game-data.mjs. Do not edit by hand. ' +
      'Names derived from tenna-editor (zlib licence), a modified use of its data tables.',
    source: `tenna-editor@${commit}`,
    chapters: CHAPTERS,
  };

  for (const [name, [idsKey, metaKey]] of Object.entries(CATEGORIES)) {
    const ids = data[idsKey];
    const meta = data[metaKey];
    if (!ids || !meta) {
      throw new Error(`tenna no longer exports ${idsKey}/${metaKey} — update CATEGORIES`);
    }
    output[name] = buildCategory(ids, meta);
    console.log(`  ${name.padEnd(16)} ${output[name].length} entries`);
  }

  output.rooms = buildRooms(data);
  console.log(`  ${'rooms'.padEnd(16)} ${output.rooms.length} entries`);

  output.plotPoints = buildPlotPoints(data);
  const plotTotal = Object.values(output.plotPoints).reduce((n, list) => n + list.length, 0);
  console.log(`  ${'plotPoints'.padEnd(16)} ${plotTotal} entries across ${Object.keys(output.plotPoints).length} chapters`);

  mkdirSync(path.dirname(OUTPUT), { recursive: true });
  writeFileSync(OUTPUT, JSON.stringify(output, null, 2) + '\n');
  rmSync(outDir, { recursive: true, force: true });

  console.log(`\nWrote ${path.relative(ROOT, OUTPUT)} from tenna-editor@${commit}`);
}

main().catch((error) => {
  console.error(error.stderr?.toString() || error.message || error);
  process.exit(1);
});
