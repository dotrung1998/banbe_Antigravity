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
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const REPO = process.cwd();
const OUT_DIR = path.join(REPO, 'docs/second-brain/graph');
const MAX_AREAS = 24;
const MAX_FILES_PER_AREA = 8;
const MAX_SYMBOLS_PER_AREA = 14;
const MAX_HOT_FILES = 30;

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

function main() {
  const graphPath = process.argv[2] || newestGraph();
  const graph = JSON.parse(fs.readFileSync(graphPath, 'utf8'));
  const allNodes = graph.nodes ?? [];
  const allLinks = graph.links ?? [];

  const nodes = allNodes.filter((n) => n.source_file && !SKIP_FILE.test(n.source_file));
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const keptIds = new Set(byId.keys());
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

  const areas = [...communities.values()]
    .map((c) => {
      const name = [...c.names.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0];
      const title = name || `Area ${c.id}`;
      const files = new Map();
      for (const n of c.nodes) files.set(n.source_file, (files.get(n.source_file) ?? 0) + 1);
      const fileEntries = [...files.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
      const testShare =
        fileEntries.filter(([f]) => TEST_FILE.test(f) || /Tests\//.test(f) || /\.(test|spec)\.[a-z]+$/i.test(f)).length /
        fileEntries.length;
      const byDegree = (a, b) => (degree.get(b.id) ?? 0) - (degree.get(a.id) ?? 0) || a.label.localeCompare(b.label);
      const callables = c.nodes.filter((n) => n._callable);
      const symbols = [...(callables.length ? callables : c.nodes)].sort(byDegree).slice(0, MAX_SYMBOLS_PER_AREA);
      // A module node (label = filename) is a poor "start here" hint; prefer a real callable with a line.
      const top = symbols.find((n) => n._callable && n.source_location) ?? symbols.find((n) => n.source_location) ?? symbols[0];
      return {
        id: c.id,
        title,
        slug: '',
        nodes: c.nodes,
        files: fileEntries,
        testShare,
        symbols,
        top,
      };
    })
    .filter((a) => a.nodes.length >= 8 && !NOISE_TITLE.test(a.title) && a.testShare < 0.6)
    .sort((a, b) => b.nodes.length - a.nodes.length || a.title.localeCompare(b.title))
    .slice(0, MAX_AREAS);

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
    let title = a.title;
    let t = 2;
    while (seenTitle.has(title)) title = `${a.title} (${t++})`;
    seenTitle.add(title);
    a.title = title;
  }

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
  const date = path.basename(path.dirname(graphPath));
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
  for (const a of areas.slice(0, 5)) console.log(`  ${a.slug}.md  ${a.nodes.length} symbols`);
}

main();
