#!/usr/bin/env node
/**
 * Keep the two mission Kanban boards in the Obsidian vault up to date.
 *
 * Boards are plain Obsidian Canvas files: three group nodes (TODO / DOING / DONE)
 * and one text card per mission run. The card keeps a stable id (`task-<key>`), so
 * the same command can move it between columns without touching anyone else's cards.
 *
 *   node scripts/kanban.mjs init   docs/second-brain/kanban/audit.canvas
 *   node scripts/kanban.mjs upsert docs/second-brain/kanban/audit.canvas audit-2026-11-22 doing "AUDIT 2026-11-22 — đang chạy"
 *   node scripts/kanban.mjs upsert docs/second-brain/kanban/audit.canvas audit-2026-11-22 done  "AUDIT 2026-11-22 — P0=1 P1=2 · apply sent"
 *   node scripts/kanban.mjs list   docs/second-brain/kanban/audit.canvas
 *
 * Only stdlib, no build step: the mission can run it from the repo root.
 */
import fs from 'node:fs';
import path from 'node:path';

const COLUMNS = [
  { key: 'todo', label: 'TODO', x: 0, y: 0, color: '1' },
  { key: 'doing', label: 'DOING', x: 360, y: 0, color: '3' },
  { key: 'done', label: 'DONE', x: 720, y: 0, color: '4' },
];
const WIDTH = 340;
const CARD_WIDTH = 300;
const CARD_HEIGHT = 88;
const PAD = 20;
const TOP = 56;
const MIN_HEIGHT = 720;
const CARD_MAX = 140;

const usage = () => {
  console.log(`Usage:
  node scripts/kanban.mjs init   <board.canvas>
  node scripts/kanban.mjs upsert <board.canvas> <key> todo|doing|done "one-line text"
  node scripts/kanban.mjs list   <board.canvas>

Keys: audit-<date> or apply-<date>. Text is kept to ${CARD_MAX} characters and one line.`);
};

const oneLine = (value) => {
  const text = String(value ?? '').replace(/\s+/g, ' ').trim();
  return text.length <= CARD_MAX ? text : `${text.slice(0, CARD_MAX - 1)}…`;
};

const safeKey = (value) =>
  String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'task';

const emptyBoard = () => ({
  nodes: COLUMNS.map((column) => ({
    id: `col-${column.key}`,
    type: 'group',
    label: column.label,
    x: column.x,
    y: 0,
    width: WIDTH,
    height: MIN_HEIGHT,
    color: column.color,
  })),
  edges: [],
});

const readBoard = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));

const writeBoard = (file, board) => {
  fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(board, null, 2)}\n`);
};

const columnOf = (card) =>
  COLUMNS.find((column) => card.x >= column.x && card.x < column.x + WIDTH) || null;

const columnOfKey = (key) => COLUMNS.find((column) => column.key === key);

const cardsIn = (board, key) =>
  board.nodes.filter((node) => node.type === 'text' && columnOf(node)?.key === key);

// A hand-edited or older card can have a missing coordinate; never let that turn
// the whole board's positions into NaN.
const bottomOf = (card) =>
  (Number.isFinite(card.y) ? card.y : 0) + (Number.isFinite(card.height) ? card.height : CARD_HEIGHT);

const nextY = (board, key, skipId) => {
  const column = columnOfKey(key);
  const bottoms = cardsIn(board, key)
    .filter((card) => card.id !== skipId)
    .map(bottomOf);
  return Math.max(column.y + TOP, ...bottoms) + 16;
};

const fitColumns = (board) => {
  for (const column of COLUMNS) {
    const cards = cardsIn(board, column.key);
    const bottom = Math.max(0, ...cards.map(bottomOf));
    const group = board.nodes.find((node) => node.id === `col-${column.key}`);
    if (group) group.height = Math.max(MIN_HEIGHT, bottom + 48);
  }
};

const init = (file) => {
  if (fs.existsSync(file)) {
    console.log(`kanban: exists ${file}`);
    return;
  }
  writeBoard(file, emptyBoard());
  console.log(`kanban: created ${file}`);
};

const upsert = (file, key, status, text) => {
  const column = columnOfKey(status);
  if (!column) throw new Error(`unknown status "${status}" (use todo, doing or done)`);
  if (!text || !String(text).trim()) throw new Error('text is required');

  const board = fs.existsSync(file) ? readBoard(file) : emptyBoard();
  if (!Array.isArray(board.nodes)) throw new Error(`${file} is not a Canvas board`);
  if (!Array.isArray(board.edges)) board.edges = [];

  const id = `task-${safeKey(key)}`;
  let card = board.nodes.find((node) => node.id === id);
  if (!card) {
    card = { id, type: 'text', text: '', x: 0, y: 0, width: CARD_WIDTH, height: CARD_HEIGHT };
    board.nodes.push(card);
  }
  card.type = 'text';
  card.text = oneLine(text);
  card.width = CARD_WIDTH;
  card.height = CARD_HEIGHT;
  card.x = column.x + PAD;
  card.y = nextY(board, status, card.id);

  fitColumns(board);
  writeBoard(file, board);
  console.log(`kanban: ${status.padEnd(5)} ${id} — ${card.text}`);
};

const list = (file) => {
  const board = readBoard(file);
  for (const column of COLUMNS) {
    console.log(`\n${column.label}`);
    const cards = cardsIn(board, column.key).sort((a, b) => a.y - b.y);
    if (!cards.length) console.log('  (empty)');
    for (const card of cards) console.log(`  ${card.id} — ${card.text}`);
  }
};

const main = () => {
  const [command, file, ...rest] = process.argv.slice(2);
  if (!command || command === '--help' || command === '-h' || !file) {
    usage();
    process.exit(command === '--help' || command === '-h' ? 0 : 2);
  }
  try {
    if (command === 'init') return init(file);
    if (command === 'list') return list(file);
    if (command === 'upsert') {
      const [key, status, ...words] = rest;
      if (!key || !status || !words.length) {
        usage();
        process.exit(2);
      }
      return upsert(file, key, status, words.join(' '));
    }
    usage();
    process.exit(2);
  } catch (error) {
    console.error(`kanban: ${error.message}`);
    process.exit(1);
  }
};

main();
