#!/usr/bin/env node
/**
 * Turn the newest Graphify code graph into Obsidian notes the agents can navigate.
 *
 * Graphify indexes code (symbols, calls, imports); Obsidian only renders Markdown links.
 * This script is the bridge: one note per code area + one "Code map" index + hot files,
 * all written into docs/second-brain/graph/ so they show up in Obsidian's graph view and
 * can be read as plain files by Hermes/Freebuff.
 *
 *   node scripts/second-brain-code-graph.mjs            # newest graphify-out/<date>/graph.json
 *   node scripts/second-brain-code-graph.mjs <graph.json>
 *
 * Re-running on the same graph produces byte-identical notes (stable sort, no timestamps),
 * so a refresh only dirties git when the code graph actually changed.
 *
 * One file, one area: a community pass can split a file (AppState+Payments.swift was 113
 * symbols in one area and 99 in another), so ownership is settled before anything is written —
 * each file belongs to the single area that holds most of its symbols, and a refresh that finds
 * a file in two areas exits non-zero instead of writing a map that points two ways.
 *
 * Area stability: graphify's community partition is re-run on every `graphify update`, so
 * "the 24 biggest communities" reshuffles even when the code barely changed — in 2026-11-27
 * a fresh graph dropped the iOS HomeView and EventDetailView areas off the map entirely.
 * The set is therefore sticky: the 12 biggest areas are always taken, and the known set is kept
 * from the previous run by any of the up to three files it owned, stored in
 * `docs/second-brain/graph/areas.json`. Remembering several files matters because a re-partition
 * can move the file an area was named after while the area (its other files) still exists. An
 * area none of whose files is in any community is simply not pinned. Delete that file to re-rank
 * from scratch — and copy its `label` entries back, since they are the hand-fixed names.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const REPO = process.cwd();
const OUT_DIR = path.join(REPO, 'docs/second-brain/graph');
/**
 * 26, not 24: one-file-one-area can reveal a real area that the old split hid (the web
 * tour/calendar/sharing area), and the sticky budget needs room for it instead of pushing
 * the smallest known area off the map.
 */
const MAX_AREAS = 26;
/** Slots always given to the biggest areas, so the map still follows the code. */
const ALWAYS_BY_SIZE = 12;
/** Files an area remembers, so a re-partition cannot make an old area vanish. */
const MAX_ANCHORS_PER_AREA = 3;
/** A sticky area must still be worth a slot — a 12-symbol utility cluster is not. */
const MIN_PINNED_NODES = 40;
/** Where the previous area set lives; keeps the map's front door from reshuffling. */
const ANCHOR_FILE = path.join(OUT_DIR, 'areas.json');
const MAX_FILES_PER_AREA = 8;
const MAX_SYMBOLS_PER_AREA = 14;
const MAX_HOT_FILES = 30;
/** An area smaller than this is a slice of a neighbourhood, not a place. */
const MIN_AREA_NODES = 8;
/** Markdown is documentation, not a place in the code. */
const DOC_FILE = /\.md$/i;
/** A title that is really a filename has to name a file the area owns. */
const FILE_TITLE = /\.(jsx?|tsx?|swift|sql|json|css)$/i;
/** Symbols that say nothing about where to start reading. */
const JUNK_SYMBOL = /^(codingkeys|keys|body|\.body\(\)|#?preview(provider)?|init)$/i;

const SKIP_FILE = /(^|\/)(node_modules|graphify-out|\.git|dist|build|\.kilo|\.next)\//;
/** Community names that are language boilerplate, not a place in the product. */
const NOISE_TITLE =
  /^(\.|view$|codingkeys$|public$|string$|int$|bool$|double$|array$|dictionary$|optional$|error$|equatable$|hashable$|identifiable$|codable$|decodable$|encodable$|sendable$|anyview$|emptyview$|never$|void$|t$)/i;
/** A cluster that is mostly test files is not a place in the product. */
const TEST_FILE = /(^|\/)(tests?|__tests__)\//i;

function die(msg) {
  console.error(`second-brain-code-graph: ${msg}`);
  process.exit(1);
}

function newestGraph() {
  const base = path.join(REPO, 'graphify-out');
  if (!fs.existsSync(base)) die('graphify-out/ not found — run graphify first');
  const root = path.join(base, 'graph.json');
  const found = [
    ...(fs.existsSync(root) ? [root] : []),
    ...fs
      .readdirSync(base, { withFileTypes: true })
      .filter((d) => d.isDirectory() && /^\d{4}-\d{2}-\d{2}$/.test(d.name))
      .map((d) => path.join(base, d.name, 'graph.json')),
  ]
    .filter((p) => fs.existsSync(p))
    .map((p) => ({ p, mtime: fs.statSync(p).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
  if (!found.length) die('no graphify-out/graph.json (or <date>/graph.json) found');
  return found[0].p;
}

/** Characters Obsidian refuses in a note title / wikilink. */
function cleanTitle(s) {
  return String(s || '')
    .replace(/[[\]|#^]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function slugify(s) {
  return s
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function pct(n, total) {
  return total ? `${((n / total) * 100).toFixed(1)}%` : '0%';
}

/** Test files are evidence, not a place to start reading. */
function isTestFile(file) {
  return TEST_FILE.test(file) || /Tests\//.test(file) || /\.(test|spec)\.[a-z]+$/i.test(file);
}

/** The one order every stage uses: biggest first, then by name. */
function bySize(a, b) {
  return b.nodes.length - a.nodes.length || a.title.localeCompare(b.title);
}

/** A cluster worth a note: not a slice of a file, not mostly tests, not boilerplate. */
function keepArea(a) {
  return a.nodes.length >= MIN_AREA_NODES && a.testShare < 0.6 && !NOISE_TITLE.test(a.title);
}

/** A symbol worth opening: not a coding key and not a test. */
function openable(n) {
  return !isTestFile(n.source_file) && !JUNK_SYMBOL.test(String(n.label ?? ''));
}

function byDegreeMap(degree) {
  return (a, b) => (degree.get(b.id) ?? 0) - (degree.get(a.id) ?? 0) || String(a.label).localeCompare(String(b.label));
}

function keySymbols(area, degree) {
  const byDegree = byDegreeMap(degree);
  const callables = area.nodes.filter((n) => n._callable && openable(n));
  const pool = callables.length ? callables : area.nodes.filter(openable);
  const ranked = [...pool].sort(byDegree).slice(0, MAX_SYMBOLS_PER_AREA);
  return ranked.length ? ranked : [...area.nodes].sort(byDegree).slice(0, MAX_SYMBOLS_PER_AREA);
}

/**
 * The entry point an agent should open. It prefers the area's biggest file, so "Start with"
 * agrees with the note's name: a test stub or a stray `CodingKeys` is never the answer.
 */
function startWith(area, degree) {
  const byDegree = byDegreeMap(degree);
  const usable = area.nodes.filter(openable);
  const dominant = area.files[0]?.[0];
  const inDominant = dominant ? usable.filter((n) => n.source_file === dominant) : [];
  return (
    inDominant.filter((n) => n._callable && n.source_location).sort(byDegree)[0] ??
    inDominant.filter((n) => n.source_location).sort(byDegree)[0] ??
    usable.filter((n) => n._callable && n.source_location).sort(byDegree)[0] ??
    usable.filter((n) => n.source_location).sort(byDegree)[0] ??
    area.nodes[0]
  );
}

/** Re-derive a note's shape from whichever nodes it now owns. */
function refresh(area, degree) {
  const files = new Map();
  for (const n of area.nodes) files.set(n.source_file, (files.get(n.source_file) ?? 0) + 1);
  area.files = [...files.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  area.testShare = area.files.length ? area.files.filter(([f]) => isTestFile(f)).length / area.files.length : 0;
  area.symbols = keySymbols(area, degree);
  area.top = startWith(area, degree);
  // A community named after a file it does not own ("events.js" whose file went to a bigger
  // neighbourhood) is a lie; then the biggest file it does own names it.
  if (FILE_TITLE.test(area.title) && area.files[0] && !area.files.some(([f]) => path.basename(f) === area.title)) {
    area.title = path.basename(area.files[0][0]);
  }
  return area;
}

/** One graphify community as a note-shaped area (ownership is settled afterwards). */
function buildArea(community, degree) {
  const files = new Map();
  for (const n of community.nodes) files.set(n.source_file, (files.get(n.source_file) ?? 0) + 1);
  const fileEntries = [...files.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const name = [...community.names.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0];
  // graphify names a community after one member, and that member can be a junk identifier:
  // the iOS Home area (215 symbols) came out as ".selection". A big community whose dominant
  // file holds a quarter of it is a real area — name it after that file instead of dropping
  // it as noise. Small junk clusters still go.
  const dominant = fileEntries[0];
  const dominantShare = dominant ? dominant[1] / community.nodes.length : 0;
  // It also emits "<member> group" labels for clusters named after a stray member
  // ("ReportMetricPresentation group" was really MapDiscovery, 85 symbols).
  const junkLabel = !name || NOISE_TITLE.test(name) || / group$/i.test(name);
  const title =
    !junkLabel
      ? name
      : dominant && community.nodes.length >= 40 && dominantShare >= 0.25
        ? path.basename(dominant[0])
        : name || `Area ${community.id}`;
  const area = { id: community.id, title, slug: '', nodes: community.nodes, files: fileEntries, testShare: 0 };
  area.size = community.nodes.length; // selection tie-break; never changes once built
  return refresh(area, degree);
}

/**
 * `areas.json` from the previous run: title, up to three files the area owned, and an optional
 * hand-curated `label` that survives refreshes. Several files per area is the point: a refresh
 * can hand the file an area was named after to another community while the area itself lives on
 * in its other files, and any remembered file finds it again. A file is claimed by one entry
 * only — one file belongs to one area, even in the pin file.
 */
function readAnchors() {
  try {
    const parsed = JSON.parse(fs.readFileSync(ANCHOR_FILE, 'utf8'));
    const claimed = new Set();
    const entries = [];
    for (const a of Array.isArray(parsed?.areas) ? parsed.areas : []) {
      if (!a) continue;
      const listed = Array.isArray(a.anchors) ? a.anchors : [a.anchor]; // v1 files had one `anchor`
      const anchors = [...new Set(listed.filter(Boolean).map(String))]
        .filter((file) => !claimed.has(file))
        .slice(0, MAX_ANCHORS_PER_AREA);
      if (!anchors.length) continue;
      for (const file of anchors) claimed.add(file);
      entries.push({
        title: String(a.title ?? ''),
        anchors,
        label: typeof a.label === 'string' && a.label.trim() ? a.label.trim() : '',
      });
    }
    return entries;
  } catch {
    return [];
  }
}

function main() {
  const graphPath = process.argv[2] || newestGraph();
  const graph = JSON.parse(fs.readFileSync(graphPath, 'utf8'));
  const allNodes = graph.nodes ?? [];
  const allLinks = graph.links ?? [];

  const nodes = allNodes.filter(
    (n) => n.source_file && !SKIP_FILE.test(n.source_file) && !DOC_FILE.test(n.source_file)
  );
  const keptIds = new Set(nodes.map((n) => n.id));
  const links = allLinks.filter((l) => keptIds.has(l.source) && keptIds.has(l.target));

  const degree = new Map();
  for (const l of links) {
    degree.set(l.source, (degree.get(l.source) ?? 0) + 1);
    degree.set(l.target, (degree.get(l.target) ?? 0) + 1);
  }

  // Community -> nodes, with the community's human name.
  const communities = new Map();
  for (const n of nodes) {
    const id = String(n.community ?? '0');
    if (!communities.has(id)) communities.set(id, { id, nodes: [], names: new Map() });
    const c = communities.get(id);
    c.nodes.push(n);
    const name = cleanTitle(n.community_name);
    if (name) c.names.set(name, (c.names.get(name) ?? 0) + 1);
  }

  const candidates = [...communities.values()].map((c) => buildArea(c, degree));

  // --- One file, one area --------------------------------------------------
  // graphify splits a file across communities (AppState+Payments.swift: 113 symbols in one,
  // 99 in another; AppState+Data.swift: spread over three), so a note can point at "the" area
  // for a file that actually lives in two. A file is opened once, so the map gives it to the
  // single area holding most of its symbols; everything else in that file is read from there.
  // A community that only existed as a slice of that file disappears, and a dropped area's
  // files are offered to the survivors, so nothing silently leaves the map.
  const fileCounts = new Map();
  for (const a of candidates) {
    for (const [file, count] of a.files) {
      if (!fileCounts.has(file)) fileCounts.set(file, new Map());
      fileCounts.get(file).set(a.id, count);
    }
  }
  // Per file: the areas holding any of it, strongest first. Ownership is read from this one
  // ranking, and size then id only settle an exact tie so two runs pick the same owner.
  const owners = new Map(
    [...fileCounts].map(([file, counts]) => [
      file,
      candidates
        .filter((a) => counts.get(a.id))
        .sort(
          (a, b) =>
            counts.get(b.id) - counts.get(a.id) || b.size - a.size || String(a.id).localeCompare(String(b.id))
        ),
    ])
  );
  const assignFiles = (pool) => {
    const inPool = new Set(pool.map((a) => a.id));
    const owner = new Map();
    for (const [file, ranked] of owners) {
      const area = ranked.find((a) => inPool.has(a.id));
      if (area) owner.set(file, area);
    }
    for (const a of pool) {
      a.nodes = nodes.filter((n) => owner.get(n.source_file) === a);
      refresh(a, degree);
    }
    return pool.filter(keepArea).sort(bySize);
  };

  let pool = candidates.filter(keepArea).sort(bySize);
  for (let pass = 0; pass < 3; pass += 1) {
    const survivors = assignFiles(pool);
    if (survivors.length === pool.length) break;
    pool = survivors;
  }

  // Sticky set: keep the area that owns any file this area owned last time, as long as that file
  // still exists and the area is worth a slot. Community ids are not stable across runs, so the
  // files — not the id or the label — are the key, and ownership makes each match exact.
  const anchors = readAnchors();
  const pinned = [];
  const pinnedIds = new Set();
  for (const anchor of anchors) {
    const owner = pool.find((a) => a.files.some(([file]) => anchor.anchors.includes(file)));
    // A one-file cluster is a slice of a file, not a place ("Screen" was 63 symbols of
    // AppState.swift) — never spend a sticky slot on one.
    if (owner && !pinnedIds.has(owner.id) && owner.nodes.length >= MIN_PINNED_NODES && owner.files.length >= 2) {
      pinned.push(owner);
      pinnedIds.add(owner.id);
    }
  }
  pinned.sort(bySize);

  const chosen = [];
  const chosenIds = new Set();
  const take = (area) => {
    if (chosen.length >= MAX_AREAS || chosenIds.has(area.id)) return;
    chosen.push(area);
    chosenIds.add(area.id);
  };
  pool.slice(0, ALWAYS_BY_SIZE).forEach(take);
  // Only pinned areas that the size rule did NOT already pick may use a sticky slot;
  // otherwise the biggest areas would eat the sticky budget and a screen area below the
  // cut (EventDetailView, 67 symbols) would stay off the map.
  const sticky = pinned.filter((area) => !chosenIds.has(area.id)).slice(0, MAX_AREAS - ALWAYS_BY_SIZE);
  sticky.forEach(take);
  pool.forEach(take);
  const areas = chosen.sort(bySize);

  // A wrong name stays fixed: `label` in areas.json is the hand-curated name of the area that
  // owns one of that entry's files, so a refresh cannot undo it. Ownership can move a file to
  // another area, so the previous title is the fallback — and a label that finds no owner is
  // carried forward rather than silently deleted, which is how one hand fix was already lost.
  const labelEntries = anchors.filter((a) => a.label);
  for (const entry of labelEntries) {
    const owner =
      areas.find((a) => a.files.some(([f]) => entry.anchors.includes(f))) ?? areas.find((a) => a.title === entry.title);
    if (owner) {
      owner.title = entry.label;
      owner.label = entry.label;
    }
  }

  // The rule, checked instead of hoped for: the same file under two areas is how this map
  // used to lie about where a `file:line` lives. Refuse to write it.
  const fileHome = new Map();
  for (const a of areas) {
    for (const [file] of a.files) {
      if (fileHome.has(file)) {
        die(`one file belongs to one area, but "${file}" sits in "${fileHome.get(file)}" and "${a.title}"`);
      }
      fileHome.set(file, a.title);
    }
  }

  // Unique slugs/titles (community names can repeat, e.g. "CodingKeys").
  const seenSlug = new Set();
  const seenTitle = new Set();
  for (const a of areas) {
    let base = slugify(a.title) || `area-${a.id}`;
    let slug = base;
    let i = 2;
    while (seenSlug.has(slug)) slug = `${base}-${i++}`;
    seenSlug.add(slug);
    a.slug = slug;
    // Two communities can end up named after the same file (a one-file slice next to the
    // real area). Say how wide each is instead of "(2)".
    let title = a.title;
    while (seenTitle.has(title)) {
      const withFiles = `${a.title} · ${a.files.length} files`;
      if (title === a.title && !seenTitle.has(withFiles)) {
        title = withFiles;
      } else {
        let n = 2;
        while (seenTitle.has(`${a.title} (${n})`)) n++;
        title = `${a.title} (${n})`;
      }
    }
    seenTitle.add(title);
    a.title = title;
  }

  // Remember the set so the next refresh keeps the same front door (see the header note).
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(
    ANCHOR_FILE,
    JSON.stringify(
      {
        version: 2,
        areas: [
          ...areas.map((a) => {
            const anchors = [...new Set([a.top?.source_file, ...a.files.map(([file]) => file)])]
              .filter((file) => file && !isTestFile(file))
              .slice(0, MAX_ANCHORS_PER_AREA);
            const entry = { title: a.title, anchors };
            if (a.label) entry.label = a.label;
            return entry;
          }),
          ...labelEntries.filter((entry) => !areas.some((a) => a.label === entry.label)),
        ],
      },
      null,
      2
    ) + '\n'
  );

  const areaOf = new Map();
  for (const a of areas) for (const n of a.nodes) areaOf.set(n.id, a);

  // Inter-area edge counts.
  const cross = new Map();
  for (const l of links) {
    const a = areaOf.get(l.source)?.slug;
    const b = areaOf.get(l.target)?.slug;
    if (!a || !b || a === b) continue;
    const key = a < b ? `${a}\u0000${b}` : `${b}\u0000${a}`;
    cross.set(key, (cross.get(key) ?? 0) + 1);
  }
  const neighbours = new Map(areas.map((a) => [a.slug, []]));
  for (const [key, count] of cross) {
    const [a, b] = key.split('\u0000');
    neighbours.get(a).push({ slug: b, count });
    neighbours.get(b).push({ slug: a, count });
  }
  for (const list of neighbours.values()) list.sort((x, y) => y.count - x.count || x.slug.localeCompare(y.slug));

  // Hot files: highest total degree.
  const fileStats = new Map();
  for (const n of nodes) {
    const f = fileStats.get(n.source_file) ?? { file: n.source_file, symbols: 0, degree: 0, area: areaOf.get(n.id) };
    f.symbols += 1;
    f.degree += degree.get(n.id) ?? 0;
    if (!f.area) f.area = areaOf.get(n.id);
    fileStats.set(n.source_file, f);
  }
  const hotFiles = [...fileStats.values()]
    .sort((a, b) => b.degree - a.degree || a.file.localeCompare(b.file))
    .slice(0, MAX_HOT_FILES);

  const builtAt = graph.built_at_commit ?? 'unknown';
  let head = 'unknown';
  let stale = false;
  try {
    head = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: REPO, encoding: 'utf8' }).trim();
    const headTime = Number(execFileSync('git', ['log', '-1', '--format=%ct'], { cwd: REPO, encoding: 'utf8' }).trim());
    // graphify keeps built_at_commit from the first extraction, so the file's write time is the real freshness signal.
    stale = fs.statSync(graphPath).mtimeMs / 1000 < headTime;
  } catch {
    /* not a git checkout; leave unknown */
  }
  const graphWritten = new Date(fs.statSync(graphPath).mtimeMs).toISOString().slice(0, 16).replace('T', ' ');
  const relGraph = path.relative(REPO, graphPath);

  fs.mkdirSync(OUT_DIR, { recursive: true });

  const link = (a) => `[[graph/${a.slug}|${a.title}]]`;
  const areaBySlug = new Map(areas.map((a) => [a.slug, a]));

  // --- Code map -----------------------------------------------------------
  const map = [];
  map.push('---');
  map.push('tags: [code-graph]');
  map.push('---');
  map.push('# Code map — open this before grepping the repo');
  map.push('');
  map.push(
    `> Generated from \`${relGraph}\` (graph written ${graphWritten} UTC · repo HEAD \`${head}\` · graphify base commit ` +
      `\`${String(builtAt).slice(0, 8)}\`): **${nodes.length.toLocaleString('en-US')} symbols**, ` +
      `${links.length.toLocaleString('en-US')} edges, ${areas.length} areas. Do not hand-edit — run ` +
      `\`node scripts/second-brain-code-graph.mjs\``
  );
  map.push('>');
  map.push(
    stale
      ? '> **Stale:** this graph was written before the current HEAD commit. Run `graphify update .` then this script.'
      : '> **Fresh:** the graph was written after the current HEAD commit, so it includes the committed code.'
  );
  map.push('');
  map.push('## Three hops, no repo scan');
  map.push('');
  map.push('1. Match the task to an **Area** below (or open the graph view and look for the cluster).');
  map.push('2. Open the area note. Read **Start with** and **Key symbols**.');
  map.push('3. Open that `file:line`. Only then search the repo — and if the graph had no answer, add it to `raw/inbox/`.');
  map.push('');
  map.push(
    'If a file disagrees with a note, the file wins: the graph is stale. Refresh with `graphify update .` then this script. ' +
      'Freshness check: graph commit vs `git rev-parse --short HEAD`.'
  );
  map.push('');
  map.push(
    '**One file, one area.** Every file is listed under exactly one area — the one holding most of its ' +
      'symbols — so a `file:line` has a single home. The script checks this and refuses to write a map ' +
      'where a file sits in two areas; `areas.json` pins up to three files per area, and its `label` ' +
      'field is a hand-fixed name a refresh will not undo.'
  );
  map.push('');
  map.push('## Areas');
  map.push('');
  map.push('| Area | Symbols | Files | Open |');
  map.push('| --- | ---: | ---: | --- |');
  for (const a of areas) map.push(`| ${a.title} | ${a.nodes.length} | ${a.files.length} | ${link(a)} |`);
  map.push('');
  map.push('## Hot files (highest coupling — read carefully before editing)');
  map.push('');
  map.push('| File | Symbols | Degree | Area |');
  map.push('| --- | ---: | ---: | --- |');
  for (const f of hotFiles) {
    map.push(`| \`${f.file}\` | ${f.symbols} | ${f.degree} | ${f.area ? link(f.area) : '—'} |`);
  }
  map.push('');
  map.push(
    '`—` means the file\'s community is smaller than the map\'s cut, so no area note owns it: open the file directly. ' +
      'It is not a second home for another area — a file is only ever listed under one.'
  );
  map.push('');
  map.push('## Related notes');
  map.push('');
  map.push('- [[Home]] · [[wiki/Project map]] · [[wiki/Conventions]] · [[Decisions]]');
  map.push('- Coverage: code structure only. Behaviour, status and history live in `.claude/notes/` and the wiki.');
  map.push('');
  fs.writeFileSync(path.join(OUT_DIR, 'Code map.md'), map.join('\n'));

  // --- One note per area ---------------------------------------------------
  for (const a of areas) {
    const lines = [];
    lines.push('---');
    lines.push('tags: [code-graph]');
    lines.push('---');
    lines.push(`# ${a.title}`);
    lines.push('');
    lines.push(
      `\`code-graph\` · area \`${a.id}\` · **${a.nodes.length} symbols** across **${a.files.length} files** · ` +
        `${pct(a.nodes.length, nodes.length)} of the graph.`
    );
    lines.push('');
    if (a.top?.source_file) {
      const loc = a.top.source_location ? `:${String(a.top.source_location).replace(/^L/, '')}` : '';
      lines.push(`**Start with:** \`${a.top.source_file}${loc}\` — \`${a.top.label}\``);
      lines.push('');
    }
    lines.push('**Key symbols:** ' + a.symbols.map((s) => `\`${s.label}\``).join(' · '));
    lines.push('');
    lines.push('## Files');
    lines.push('');
    lines.push('| File | Symbols |');
    lines.push('| --- | ---: |');
    for (const [file, count] of a.files.slice(0, MAX_FILES_PER_AREA)) lines.push(`| \`${file}\` | ${count} |`);
    if (a.files.length > MAX_FILES_PER_AREA) {
      lines.push(`| _+${a.files.length - MAX_FILES_PER_AREA} more files_ | |`);
    }
    lines.push('');
    const near = neighbours.get(a.slug) ?? [];
    if (near.length) {
      lines.push('## Connected areas');
      lines.push('');
      for (const n of near.slice(0, 6)) {
        const b = areaBySlug.get(n.slug);
        if (b) lines.push(`- ${link(b)} — ${n.count} edges`);
      }
      lines.push('');
    }
    lines.push('---');
    lines.push('[[graph/Code map|Code map]] · [[Home]]');
    lines.push('');
    fs.writeFileSync(path.join(OUT_DIR, `${a.slug}.md`), lines.join('\n'));
  }

  // Remove notes that no longer correspond to an area (avoid ghosts in the graph).
  const keep = new Set(['Code map.md', ...areas.map((a) => `${a.slug}.md`)]);
  for (const f of fs.readdirSync(OUT_DIR)) {
    if (f.endsWith('.md') && !keep.has(f)) fs.unlinkSync(path.join(OUT_DIR, f));
  }

  console.log(
    `wrote ${areas.length + 1} notes to ${path.relative(REPO, OUT_DIR)} ` +
      `(${nodes.length} symbols, ${links.length} edges, graph ${builtAt} -> HEAD ${head})`
  );
  console.log(`  area set: ${ALWAYS_BY_SIZE} by size + ${sticky.length} kept from ${anchors.length} anchor(s)`);
  console.log(`  one file, one area: ${fileHome.size} files across ${areas.length} areas`);
  for (const a of areas.slice(0, 5)) console.log(`  ${a.slug}.md  ${a.nodes.length} symbols`);
}

main();
