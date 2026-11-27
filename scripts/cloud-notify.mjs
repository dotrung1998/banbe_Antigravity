#!/usr/bin/env node
/**
 * Cloud-side status notifications for banbe, delivered to Discord channels.
 *
 * Runs inside GitHub Actions (.github/workflows/discord-notify.yml) so reports
 * keep arriving while the Mac that runs Hermes is asleep. Nothing here touches
 * the app, the database or the deployment: it reads git, the GitHub API and two
 * public endpoints, then posts an embed to a Discord webhook.
 *
 *   node scripts/cloud-notify.mjs standup     # 09:00 Mon-Fri ICT — commits, PRs, failed runs
 *   node scripts/cloud-notify.mjs health      # hourly — one alert per incident, a recovery message, repeats every 6h
 *   node scripts/cloud-notify.mjs weekly      # Fri 17:00 ICT — the week's commits + hotspots
 *   node scripts/cloud-notify.mjs deps        # Sun 18:00 ICT — outdated packages + npm audit
 *   node scripts/cloud-notify.mjs prompt      # 05:00 daily ICT — copy-paste Mission for a Freebuff session
 *   node scripts/cloud-notify.mjs prototype   # 06:00 daily ICT — that day's prototype Mission (day 1..8)
 *   node scripts/cloud-notify.mjs apply --file docs/audits/<date>/APPLY.discord.md  # one copyable mission message
 *   node scripts/cloud-notify.mjs test        # one message, to prove the webhook wiring
 *
 * Flags: --dry-run  print the payload and send nothing
 *        --always   health: post even when every check passes
 *        --file     apply: read the prompt from this file instead of APPLY_PROMPT/env
 *        --day N       prototype: post that day (1..8) instead of the computed one
 *        --cluster ID  prototype: post only that cluster's full mission (onboarding|discover|event|me|host)
 *                      (default: five messages, one per cluster, in ladder order)
 *
 * Webhooks (repo secrets, one URL per channel):
 *   DISCORD_WEBHOOK_STANDUP, DISCORD_WEBHOOK_ALERTS, DISCORD_WEBHOOK_WEEKLY
 *   DISCORD_WEBHOOK is a fallback for any of them, so one URL works everywhere.
 * An unset webhook is not an error: the message is printed to the job log and a
 * warning says which secret to add.
 *
 * Env: GITHUB_REPOSITORY + GITHUB_TOKEN (provided by Actions) for PRs and runs,
 *      APP_URL (default https://www.banbe.app) for the health check,
 *      SUPABASE_URL + SUPABASE_ANON_KEY for the optional API check
 *        (reads /rest/v1/events, not the service_role-only /rest/v1/ root),
 *      NOTIFY_STATE_DIR for the health state file (defaults to a temp dir),
 *      HEALTH_REPEAT_HOURS for how often an unchanged failure repeats (default 6).
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const JOB = process.argv[2];
const DRY_RUN = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
const ALWAYS = process.argv.includes('--always');

const APP_URL = process.env.APP_URL || 'https://www.banbe.app';
const TIME_ZONE = 'Asia/Ho_Chi_Minh';
const BRAND = { gold: 0xf6c453, moss: 0x8a9a7b, clay: 0xc0653f, red: 0xd64541 };

// Health needs to remember what it last said so hourly runs do not repeat an
// alert and so a recovery can be announced. GitHub Actions persists this file
// through the actions/cache steps in the workflow.
const STATE_DIR = process.env.NOTIFY_STATE_DIR || path.join(os.tmpdir(), 'banbe-notify-state');
const STATE_FILE = path.join(STATE_DIR, 'health.json');
const REPEAT_HOURS_RAW = Number.parseFloat(process.env.HEALTH_REPEAT_HOURS ?? '6');
const REPEAT_HOURS = Number.isFinite(REPEAT_HOURS_RAW) && REPEAT_HOURS_RAW >= 0 ? REPEAT_HOURS_RAW : 6;

const CHANNEL_OF = {
  standup: 'standup',
  health: 'alerts',
  weekly: 'weekly',
  deps: 'weekly',
  prompt: 'weekly',
  apply: 'weekly',
  prototype: 'weekly',
  test: 'alerts',
};

const clip = (value, max) => {
  const s = String(value ?? '');
  return s.length <= max ? s : `${s.slice(0, Math.max(0, max - 1))}…`;
};

const ictFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: TIME_ZONE,
  weekday: 'short',
  day: '2-digit',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});
const ictFrom = (value) => {
  const date = value ? new Date(value) : new Date();
  return Number.isNaN(date.getTime()) ? 'unknown' : ictFormat.format(date);
};
const ictNow = () => ictFrom();

const today = () =>
  new Intl.DateTimeFormat('en-CA', { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit' }).format(
    new Date()
  );

function git(args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', maxBuffer: 16 << 20 }).trim();
  } catch {
    return '';
  }
}

function capture(command, args, timeoutMs = 180_000) {
  try {
    return execFileSync(command, args, {
      encoding: 'utf8',
      maxBuffer: 16 << 20,
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
      env: { ...process.env, npm_config_update_notifier: 'false', NO_COLOR: '1' },
    });
  } catch (error) {
    // npm exits 1 for "outdated" and "audit" even though stdout holds the report.
    return String(error?.stdout ?? '');
  }
}

function commitsSince(since) {
  return git(['log', `--since=${since}`, '--pretty=format:%h\t%an\t%s'])
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
}

function commitLines(commits, limit) {
  if (!commits.length) return 'None.';
  const shown = commits.slice(0, limit).map((line) => {
    const [sha, author, ...subject] = line.split('\t');
    return `\`${sha}\` ${clip(subject.join(' ') || '(no subject)', 90)} — ${clip(author, 40)}`;
  });
  if (commits.length > limit) shown.push(`…and ${commits.length - limit} more`);
  return shown.join('\n');
}

async function githubApi(path) {
  const repo = process.env.GITHUB_REPOSITORY;
  const token = process.env.GITHUB_TOKEN;
  if (!repo || !token) return null;
  try {
    const response = await fetch(`https://api.github.com/repos/${repo}${path}`, {
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/vnd.github+json',
        'user-agent': 'banbe-cloud-notify',
      },
      signal: AbortSignal.timeout(15_000),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

function embed({ title, description, color, fields = [], footer }) {
  const safe = {
    title: clip(title, 256),
    description: clip(description, 4096),
    color,
    fields: fields.slice(0, 25).map((field) => ({
      name: clip(field.name, 256),
      value: clip(field.value || '—', 1024),
      inline: Boolean(field.inline),
    })),
    footer: { text: clip(footer || `banbe cloud · ${ictNow()} ICT`, 2048) },
    timestamp: new Date().toISOString(),
  };
  if (safe.description.length + safe.fields.reduce((sum, f) => sum + f.name.length + f.value.length, 0) > 5800) {
    safe.fields = safe.fields.slice(0, 8);
    safe.description = clip(safe.description, 1200);
  }
  return safe;
}

async function post(channel, embedPayload) {
  // Discord wants { embeds: [...] }; a bare embed object is rejected with 400.
  const payload = {
    username: 'banbe cloud',
    allowed_mentions: { parse: [] },
    embeds: [embedPayload],
  };
  if (DRY_RUN) {
    console.log(`dry run — would post to ${channel}:`);
    console.log(JSON.stringify(payload, null, 2));
    return { sent: false, dryRun: true };
  }
  const url = process.env[`DISCORD_WEBHOOK_${channel.toUpperCase()}`] || process.env.DISCORD_WEBHOOK;
  if (!url) {
    console.warn(`no webhook configured for "${channel}" — set DISCORD_WEBHOOK_${channel.toUpperCase()} in repo secrets`);
    console.log(JSON.stringify(payload, null, 2));
    return { sent: false };
  }
  const target = `${url}${url.includes('?') ? '&' : '?'}wait=true`;
  const response = await fetch(target, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Discord rejected the ${channel} message: HTTP ${response.status} ${clip(body, 300)}`);
  }
  console.log(`posted ${channel} (HTTP ${response.status})`);
  return { sent: true };
}

// Plain text (no embed) so the mission prompt is one drag-select away from the
// clipboard. Discord caps `content` at 2000 characters; dailyPrompt() stays under.
async function postText(channel, content) {
  const payload = { username: 'banbe cloud', allowed_mentions: { parse: [] }, content };
  if (DRY_RUN) {
    console.log(`dry run — would post to ${channel}:`);
    console.log(content);
    return { sent: false, dryRun: true };
  }
  const url = process.env[`DISCORD_WEBHOOK_${channel.toUpperCase()}`] || process.env.DISCORD_WEBHOOK;
  if (!url) {
    console.warn(`no webhook configured for "${channel}" — set DISCORD_WEBHOOK_${channel.toUpperCase()} in repo secrets`);
    console.log(content);
    return { sent: false };
  }
  const target = `${url}${url.includes('?') ? '&' : '?'}wait=true`;
  const response = await fetch(target, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Discord rejected the ${channel} message: HTTP ${response.status} ${clip(body, 300)}`);
  }
  console.log(`posted ${channel} (HTTP ${response.status})`);
  return { sent: true };
}

// The apply hand-off is always one copyable Discord message: a bold header, the
// paste instruction, and one fenced text block. Raw APPLY prompts are wrapped;
// already-formatted files are validated. Anything over 1,800 characters is refused
// rather than split into messages the owner cannot paste as one mission.
const APPLY_LIMIT = 1800;
const APPLY_CANONICAL = /^\*\*Mission APPLY — (\d{4}-\d{2}-\d{2}) \(.+?\) · HEAD `([^`]+)`\*\*\nDán khối dưới vào một phiên Freebuff mới \(Mission\):\n```text\n([\s\S]*?)\n```$/;

function weekdayNameVi(date) {
  const weekday = new Intl.DateTimeFormat('en-GB', { timeZone: TIME_ZONE, weekday: 'long' }).format(date);
  return {
    Monday: 'Thứ Hai', Tuesday: 'Thứ Ba', Wednesday: 'Thứ Tư',
    Thursday: 'Thứ Năm', Friday: 'Thứ Sáu', Saturday: 'Thứ Bảy', Sunday: 'Chủ Nhật',
  }[weekday] || weekday;
}

function applyDate(file) {
  const match = /(?:^|[/\\])(\d{4}-\d{2}-\d{2})(?:[/\\]|$)/.exec(file || '');
  return match ? match[1] : today();
}

function applyWeekday(date) {
  const parsed = new Date(`${date}T12:00:00+07:00`);
  return Number.isNaN(parsed.getTime()) ? weekdayNameVi(new Date()) : weekdayNameVi(parsed);
}

function formatApplyMessage(raw, file) {
  const text = String(raw).replace(/\r\n/g, '\n').trim();
  if (!text) throw new Error('empty prompt');
  const canonical = APPLY_CANONICAL.exec(text);
  const body = canonical ? canonical[3].trim() : text;
  if (!body) throw new Error('empty prompt body');
  if (/^```/m.test(body)) {
    throw new Error('prompt contains its own ``` fence; remove it so the script can wrap it in one code block');
  }
  if (!canonical && /^\*\*Mission APPLY\b/.test(text)) {
    throw new Error('file starts with a Mission APPLY header but is not in the canonical header + fenced text block format');
  }
  const date = canonical ? canonical[1] : applyDate(file);
  const head = canonical ? canonical[2] : git(['rev-parse', '--short', 'HEAD']) || 'unknown';
  const message = canonical
    ? text
    : `**Mission APPLY — ${date} (${applyWeekday(date)}) · HEAD \`${head}\`**\nDán khối dưới vào một phiên Freebuff mới (Mission):\n\`\`\`text\n${body}\n\`\`\``;
  if (message.length > APPLY_LIMIT) {
    throw new Error(`formatted message is ${message.length} characters (limit ${APPLY_LIMIT}); shorten the prompt so it stays one copyable code block`);
  }
  return message;
}

// The apply prompt is written by the audit, then posted here so the owner can paste
// it into a new session from Discord. No issue, no commit, no repo write.
async function postApply() {
  const at = process.argv.indexOf('--file');
  const file = at > -1 ? process.argv[at + 1] : null;
  let body = '';
  if (file) {
    try {
      body = fs.readFileSync(path.resolve(file), 'utf8');
    } catch (error) {
      console.error(`apply: cannot read --file ${file}: ${error.message}`);
      process.exit(2);
    }
  } else {
    body = process.env.APPLY_PROMPT || '';
  }
  body = body.trim();
  if (!body) {
    console.error('apply: nothing to send — pass --file <path> or set APPLY_PROMPT');
    process.exit(2);
  }
  let message;
  try {
    message = formatApplyMessage(body, file);
  } catch (error) {
    console.error(`apply: ${error.message}`);
    process.exit(2);
  }
  const result = await postText('weekly', message);
  const delivered = result.sent || result.dryRun ? 1 : 0;
  console.log(`apply: ${delivered}/1 message(s) delivered`);
  if (!delivered) {
    console.error('apply: webhook missing or Discord refused; the prompt was printed above — add DISCORD_WEBHOOK_WEEKLY to send it');
    process.exitCode = 1;
  }
}

/* ------------------------------------------------------------------ jobs */

async function standup() {
  const commits = commitsSince('24.hours');
  const [pulls, runs] = await Promise.all([
    githubApi('/pulls?state=open&per_page=10&sort=updated&direction=desc'),
    githubApi('/actions/runs?per_page=30'),
  ]);
  const failed = Array.isArray(runs?.workflow_runs)
    ? runs.workflow_runs.filter(
        (run) =>
          run.conclusion === 'failure' &&
          Date.now() - new Date(run.created_at).getTime() < 24 * 60 * 60 * 1000
      )
    : null;
  return embed({
    title: 'banbe · standup',
    description: `Cloud standup for **${today()}** · Git + GitHub only, no Mac needed.`,
    color: BRAND.gold,
    fields: [
      { name: `Commits · last 24h (${commits.length})`, value: commitLines(commits, 12) },
      {
        name: `Open pull requests${Array.isArray(pulls) ? ` (${pulls.length})` : ''}`,
        value: Array.isArray(pulls)
          ? pulls.length
            ? pulls.map((pr) => `#${pr.number} ${clip(pr.title, 90)}`).join('\n')
            : 'None.'
          : 'GitHub API unavailable for this run.',
      },
      {
        name: `Failed workflow runs · 24h${failed ? ` (${failed.length})` : ''}`,
        value: failed
          ? failed.length
            ? failed
                .slice(0, 6)
                .map((run) => `${clip(run.name, 50)} · ${clip(run.head_branch || '?', 40)} · #${run.run_number}`)
                .join('\n')
            : 'None.'
          : 'GitHub API unavailable for this run.',
      },
    ],
  });
}

async function weekly() {
  const commits = commitsSince('7.days');
  const pulls = await githubApi('/pulls?state=open&per_page=10&sort=updated&direction=desc');
  const changed = git(['log', '--since=7.days', '--name-only', '--pretty=format:'])
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
  const counts = new Map();
  for (const file of changed) counts.set(file, (counts.get(file) || 0) + 1);
  const hotspots = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 6);
  return embed({
    title: 'banbe · week in review',
    description: `Week ending **${today()}** · what Monday starts from.`,
    color: BRAND.moss,
    fields: [
      { name: `Commits · last 7 days (${commits.length})`, value: commitLines(commits, 10) },
      {
        name: 'Most-changed files',
        value: hotspots.length ? hotspots.map(([file, n]) => `${n}× \`${clip(file, 90)}\``).join('\n') : 'None.',
      },
      {
        name: `Open pull requests${Array.isArray(pulls) ? ` (${pulls.length})` : ''}`,
        value: Array.isArray(pulls)
          ? pulls.length
            ? pulls.map((pr) => `#${pr.number} ${clip(pr.title, 90)}`).join('\n')
            : 'None.'
          : 'GitHub API unavailable for this run.',
      },
    ],
  });
}

function deps() {
  const outdatedRaw = capture('npm', ['outdated', '--json', '--long']);
  const auditRaw = capture('npm', ['audit', '--json', '--omit=dev']);
  // null means "no report", which is different from "nothing outdated".
  let outdated = null;
  try {
    const parsed = JSON.parse(outdatedRaw || '');
    outdated = parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    outdated = null;
  }
  const names = outdated ? Object.keys(outdated).sort() : null;
  const outdatedLines = (names || []).slice(0, 10).map((name) => {
    const info = outdated[name] || {};
    return `\`${clip(name, 60)}\` ${clip(info.current || '?', 20)} → ${clip(info.latest || '?', 20)}`;
  });

  let summary = 'npm audit could not run.';
  let color = BRAND.moss;
  try {
    const audit = JSON.parse(auditRaw || '{}');
    const v = audit?.metadata?.vulnerabilities;
    if (v) {
      const total = Number(v.total || 0);
      summary = `critical **${v.critical ?? 0}** · high **${v.high ?? 0}** · moderate **${v.moderate ?? 0}** · low **${v.low ?? 0}** · total **${total}**`;
      if (Number(v.critical) || Number(v.high)) color = BRAND.red;
    }
  } catch {
    /* keep the fallback line */
  }

  return embed({
    title: 'banbe · dependency audit',
    description: `Week ending **${today()}** · production dependencies only for the audit.`,
    color,
    fields: [
      {
        name: names === null ? 'Outdated packages (no report)' : `Outdated packages (${names.length})`,
        value:
          names === null
            ? '`npm outdated` returned nothing — registry or network failure, not a clean result.'
            : names.length
              ? outdatedLines.join('\n')
              : 'None — everything on its latest wanted version.',
      },
      { name: 'npm audit · prod deps', value: summary },
    ],
  });
}

// Hermes cannot move to the cloud (its scheduler is an in-process ticker on the
// Mac) and Freebuff refuses automated runs, so the audit stays human-in-the-loop:
// this posts the mission, a person pastes it into a Freebuff session.
function dailyPrompt() {
  const date = today();
  const head = git(['rev-parse', '--short', 'HEAD']) || 'unknown';
  const weekday = new Intl.DateTimeFormat('en-GB', { timeZone: TIME_ZONE, weekday: 'long' }).format(new Date());
  const weekdayVi = {
    Monday: 'Thứ Hai', Tuesday: 'Thứ Ba', Wednesday: 'Thứ Tư',
    Thursday: 'Thứ Năm', Friday: 'Thứ Sáu', Saturday: 'Thứ Bảy', Sunday: 'Chủ Nhật',
  }[weekday] || weekday;
  const extra = weekday === 'Friday'
    ? 'Thứ Sáu: thêm week review 7 ngày (commit, 6 file hotspot, branch, "Monday starts with").'
    : weekday === 'Sunday'
      ? 'Chủ nhật: thêm deps sâu + code graph (nếu có graphify).'
      : 'Hôm nay không có việc riêng của thứ Sáu/Chủ nhật.';
  const text = [
    `**Mission hôm nay — ${date} (${weekdayVi})** · HEAD \`${head}\``,
    'Dán khối dưới vào một phiên Freebuff mới (Mission):',
    '```text',
    'Mission: banbe daily — đọc docs/prompts/daily-hermes.md rồi làm đủ các mục.',
    'Hôm nay: standup 24h · health app/Supabase/R2 · audit kỹ thuật P0–P3 · review UI/UX (6 chỗ + 7 chiều, có nguồn ngoài) · deps nhanh.',
    extra,
    `Ghi docs/audits/${date}/AUDIT.md và một dòng vào docs/second-brain/audits/index.md.`,
    'Chỉ báo cáo: KHÔNG sửa source, KHÔNG commit/push/deploy/migration. Mọi kết luận cần path:line, route hoặc ảnh; thiếu bằng chứng thì ghi blocked, không bịa.',
    'Cuối mission: tổng hợp prompt apply (mục K) và gửi vào kênh này.',
    'Bỏ qua backup git bundle và Apple Notes (chỉ chạy trên Mac).',
    '```',
  ].join('\n');
  return text.length <= 1900 ? text : `${text.slice(0, 1890)}…`;
}

// The prototype ladder is seven build days plus a review. A day is one lens over five
// screen clusters, and every cluster is its own Mission — its own Freebuff session and
// its own question on the Glance board. The matrix is data in
// docs/prototypes/missions/plan.json (edit the plan, not this script); day 8 is the
// single review mission in missions/day-08.md.
const PROTOTYPE_DIR = 'docs/prototypes';
const PROTOTYPE_PLAN = path.join(PROTOTYPE_DIR, 'missions', 'plan.json');
const PROTOTYPE_REVIEW = path.join(PROTOTYPE_DIR, 'missions', 'day-08.md');
const PROTOTYPE_LAST_DAY = 8;
const PROTOTYPE_LIMIT = 1900;
const PROTOTYPE_RULES =
  'không sửa src/, ios/, migration; không deploy; ảnh thật, không màn hình bịa; ≥1 link sang cụm khác.';

function prototypeDay() {
  const fromArgs = process.argv.indexOf('--day');
  const pinned = Number.parseInt(fromArgs > -1 ? process.argv[fromArgs + 1] : process.env.PROTOTYPE_DAY || '', 10);
  if (Number.isFinite(pinned) && pinned >= 1) return Math.min(pinned, PROTOTYPE_LAST_DAY);
  const startRaw = process.env.PROTOTYPE_START || '2026-11-27';
  const start = new Date(`${startRaw}T00:00:00+07:00`);
  if (Number.isNaN(start.getTime())) return 1;
  const elapsed = Math.floor((Date.now() - start.getTime()) / 86_400_000);
  return Math.min(PROTOTYPE_LAST_DAY, Math.max(1, elapsed + 1));
}

function pad2(value) {
  return String(value).padStart(2, '0');
}

function readTextFile(file) {
  let body = '';
  try {
    body = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n').trim();
  } catch (error) {
    throw new Error(`prototype: cannot read ${file}: ${error.message}`);
  }
  if (!body) throw new Error(`prototype: ${file} is empty`);
  return body;
}

function prototypePlan() {
  const raw = readTextFile(PROTOTYPE_PLAN);
  let plan;
  try {
    plan = JSON.parse(raw);
  } catch (error) {
    throw new Error(`prototype: ${PROTOTYPE_PLAN} is not valid JSON: ${error.message}`);
  }
  const clusters = Array.isArray(plan.clusters) ? plan.clusters.filter((cluster) => cluster && cluster.id) : [];
  const days = Array.isArray(plan.days) ? plan.days.filter((day) => day && day.day) : [];
  if (!clusters.length || !days.length) {
    throw new Error('prototype: plan.json needs a non-empty days[] and clusters[]');
  }
  return { clusters, days };
}

function clusterMissionText(day, lens, cluster, plan, index, total) {
  const previous = plan.days.find((entry) => entry.day === day - 1);
  const per = lens.clusters?.[cluster.id];
  if (!per || !Array.isArray(per.tasks) || !per.tasks.length) {
    throw new Error(`prototype: plan.json day ${day} is missing clusters.${cluster.id}.tasks`);
  }
  const lines = [
    `NGÀY ${day}/${PROTOTYPE_LAST_DAY} · CỤM ${index}/${total} · ${cluster.title}`,
    `Mục tiêu: ${lens.lens}`,
    `Vì sao cụm này: ${per.focus}`,
    `Màn: ${cluster.screens}`,
    `Đọc: docs/prototypes/missions/STANDARD.md · docs/prototypes/decisions/day-${pad2(day)}.json (${cluster.question || cluster.id})`,
  ];
  lines.push(
    previous
      ? `  · bản trước: docs/prototypes/day-${pad2(previous.day)}-${previous.slug}/${cluster.id}/index.html`
      : '  · bản trước: không có — đây là bản đầu tiên'
  );
  const refs = (cluster.ref || []).filter(Boolean);
  if (refs.length) lines.push(`  · trong nhà (không copy pixel): ${refs.join(' · ')}`);
  lines.push(`  · ngoài: RESEARCH-SOURCES.md › ${cluster.id} — 2 nguồn, ghi URL + ngày vào notes.md`);
  lines.push(`  · code (chỉ đọc): ${(cluster.read || []).join(', ')}`);
  lines.push('Việc:');
  per.tasks.forEach((step, stepIndex) => lines.push(`${stepIndex + 1}. ${step}`));
  lines.push(`Chung: ${lens.rule}`);
  lines.push(
    `Nộp: docs/prototypes/day-${pad2(day)}-${lens.slug}/${cluster.id}/{index.html,notes.md} + ` +
      `frames/${cluster.id}-{bước}-{390,834,1194,1440}.png + overview + capture.md.`
  );
  const checks = (per.check || []).filter(Boolean);
  if (checks.length) lines.push(`Kiểm: ${checks.join(' · ')}`);
  lines.push(`Giữ: ${cluster.must}`);
  lines.push('Hỏi: tối đa 2 câu, chỉ khi đổi bố cục; bỏ câu đã có trên Glance.');
  lines.push(`Luật: ${PROTOTYPE_RULES}`);
  return lines.join('\n');
}

function wrapPrototypeMessage(header, body) {
  const message = [header, 'Dán khối dưới vào một phiên Freebuff mới (Mission):', '```text', body, '```'].join('\n');
  if (message.length > PROTOTYPE_LIMIT) {
    throw new Error(
      `prototype: a mission message is ${message.length} characters (limit ${PROTOTYPE_LIMIT}) — shorten the mission text`
    );
  }
  return message;
}

/**
 * Five messages a day, one per cluster, in ladder order. `cluster` posts just that
 * one (a deep-dive session); day 8 is the single review mission.
 */
function prototypeMissions(day, { cluster = '' } = {}) {
  const header = (label) =>
    `**Mission PROTOTYPE — ${today()} (${weekdayNameVi(new Date())}) · Ngày ${day}/${PROTOTYPE_LAST_DAY} · ${label}**`;

  if (day >= PROTOTYPE_LAST_DAY) {
    const body = readTextFile(PROTOTYPE_REVIEW);
    if (/^```/m.test(body)) {
      throw new Error(`prototype: ${PROTOTYPE_REVIEW} contains a \`\`\` fence; the script wraps the mission in one block`);
    }
    const title = header('Review + áp dụng');
    return [{ id: 'review', message: wrapPrototypeMessage(title, body) }];
  }

  const plan = prototypePlan();
  const lens = plan.days.find((entry) => entry.day === day);
  if (!lens) throw new Error(`prototype: plan.json has no day ${day}`);

  const fullMission = (entry) => {
    const index = plan.clusters.indexOf(entry) + 1;
    const title = header(`Cụm ${index}/${plan.clusters.length} — ${entry.title}`);
    return {
      id: entry.id,
      message: wrapPrototypeMessage(title, clusterMissionText(day, lens, entry, plan, index, plan.clusters.length)),
    };
  };

  if (cluster) {
    const picked = plan.clusters.find((entry) => entry.id === cluster);
    if (!picked) {
      throw new Error(
        `prototype: unknown cluster "${cluster}" — use ${plan.clusters.map((entry) => entry.id).join(' | ')}`
      );
    }
    return [fullMission(picked)];
  }
  return plan.clusters.map(fullMission);
}

function readHealthState() {
  try {
    const parsed = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function writeHealthState(state) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`);
  } catch (error) {
    console.warn(`could not persist health state at ${STATE_FILE}: ${error.message}`);
  }
}

async function health() {
  const checks = [];
  const probe = async (name, url, options = {}) => {
    const started = Date.now();
    try {
      const response = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(20_000), ...options });
      const ms = Date.now() - started;
      let ok = response.ok;
      let detail = `HTTP ${response.status} in ${ms} ms`;
      if (ok && options.expectRootMarker) {
        const body = await response.text();
        if (!body.includes('id="root"')) {
          ok = false;
          detail += ' · page body is missing the app root';
        }
      }
      checks.push({ name, ok, detail: `${detail} · ${url}` });
    } catch (error) {
      checks.push({ name, ok: false, detail: `${clip(error?.message || error, 160)} · ${url}` });
    }
  };

  await probe('App', APP_URL, { headers: { 'user-agent': 'banbe-cloud-notify/1.0' }, expectRootMarker: true });

  const supabaseUrl = (process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY;
  if (supabaseUrl && anonKey) {
    // Not the /rest/v1/ OpenAPI root: Supabase answers that one with
    // 401 "Only the `service_role` API key can be used for this endpoint",
    // so an anon key would fail even when the API is perfectly healthy.
    // Probe a table the anon role can read (RLS still applies).
    await probe('Supabase REST', `${supabaseUrl}/rest/v1/events?select=id&limit=1`, {
      headers: { apikey: anonKey, authorization: `Bearer ${anonKey}`, 'user-agent': 'banbe-cloud-notify/1.0' },
    });
  } else {
    const missing = [!supabaseUrl && 'SUPABASE_URL', !anonKey && 'SUPABASE_ANON_KEY'].filter(Boolean).join(' + ');
    checks.push({ name: 'Supabase REST', ok: true, skipped: true, detail: `skipped — no ${missing} secret` });
  }

  // Skipped checks are shown but not counted: "1 of 2" must mean two real checks.
  const considered = checks.filter((check) => !check.skipped);
  const failed = considered.filter((check) => !check.ok);
  const failing = failed.map((check) => check.name).sort();
  const healthy = failing.length === 0;
  const previous = readHealthState();
  const now = new Date().toISOString();
  const state = {
    status: healthy ? 'ok' : 'fail',
    since: previous?.status === (healthy ? 'ok' : 'fail') && previous?.since ? previous.since : now,
    failing,
    last_alert_at: previous?.last_alert_at ?? null,
    last_check_at: now,
    repeat_hours: REPEAT_HOURS,
  };

  console.log(
    `health: ${considered.length - failed.length}/${considered.length} ok · previous state: ${previous?.status ?? 'none'} · repeat ${REPEAT_HOURS}h`
  );
  for (const check of checks) {
    console.log(`  ${check.skipped ? 'skip' : check.ok ? 'ok  ' : 'FAIL'} ${check.name}: ${check.detail}`);
  }

  const fields = checks.map((check) => ({
    name: check.name,
    value: `${check.skipped ? '➖' : check.ok ? '✅' : '❌'} ${check.detail}`,
  }));

  if (healthy) {
    if (previous?.status === 'fail') {
      const since = previous.since ? `${ictFrom(previous.since)} ICT` : 'an earlier check';
      return {
        alert: false,
        state,
        embed: embed({
          title: '✅ banbe recovered',
          description: `Every check passes again at ${ictNow()} ICT — the failure had been open since ${since}.`,
          color: BRAND.moss,
          fields,
        }),
      };
    }
    if (ALWAYS) {
      return {
        alert: false,
        state,
        embed: embed({
          title: 'banbe health check (manual)',
          description: `Every check passed at ${ictNow()} ICT.`,
          color: BRAND.moss,
          fields,
        }),
      };
    }
    console.log('healthy — nothing posted (alerts are sent only when a check fails)');
    return { alert: false, state, embed: null };
  }

  const previousFailing = Array.isArray(previous?.failing) ? [...previous.failing].sort() : [];
  const sameFailure = previous?.status === 'fail' && JSON.stringify(previousFailing) === JSON.stringify(failing);
  const lastAlertAt = Date.parse(previous?.last_alert_at || '');
  const sinceLastAlertMs = Number.isFinite(lastAlertAt) ? Date.now() - lastAlertAt : Number.POSITIVE_INFINITY;
  if (sameFailure && sinceLastAlertMs < REPEAT_HOURS * 3600_000) {
    const nextAt = Number.isFinite(lastAlertAt)
      ? `${ictFrom(new Date(lastAlertAt + REPEAT_HOURS * 3600_000).toISOString())} ICT`
      : 'later';
    console.log(
      `same failure as the last alert (${failing.join(', ')}) — suppressed; next repeat after ${nextAt} (HEALTH_REPEAT_HOURS=${REPEAT_HOURS})`
    );
    return { alert: true, state, embed: null };
  }

  return {
    alert: true,
    state,
    embed: embed({
      title: '🚨 banbe health check failed',
      description: sameFailure
        ? `**${failing.length} of ${considered.length}** checks still failing at ${ictNow()} ICT; repeating after ${REPEAT_HOURS}h without recovery.`
        : `**${failing.length} of ${considered.length}** checks failed at ${ictNow()} ICT.`,
      color: BRAND.red,
      fields,
    }),
  };
}

function testMessage() {
  return embed({
    title: 'banbe · cloud notifications are wired',
    description: [
      'This message came from GitHub Actions, not from the Mac.',
      '',
      'Scheduled jobs (ICT):',
      '• standup — 09:00 Mon–Fri',
      '• health — hourly, silent while healthy',
      '• week in review — Fri 17:00',
      '• dependency audit — Sun 18:00',
      '• Freebuff mission prompt — 05:00 daily',
    ].join('\n'),
    color: BRAND.clay,
  });
}

/* ------------------------------------------------------------------ main */

async function main() {
  const job = JOB || 'test';
  if (!CHANNEL_OF[job]) {
    console.error(`unknown job "${job}" — use standup | health | weekly | deps | prompt | prototype | apply | test`);
    process.exit(2);
  }
  if (job === 'prompt') {
    await postText('weekly', dailyPrompt());
    return;
  }
  if (job === 'apply') {
    await postApply();
    return;
  }
  if (job === 'prototype') {
    const day = prototypeDay();
    const clusterFlag = process.argv.indexOf('--cluster');
    const cluster = clusterFlag > -1 ? String(process.argv[clusterFlag + 1] || '') : '';
    const missions = prototypeMissions(day, { cluster });
    for (const [index, mission] of missions.entries()) {
      const result = await postText('weekly', mission.message);
      console.log(
        `prototype: day ${day} · ${mission.id} → ${result.sent ? 'posted' : result.dryRun ? 'dry run' : 'not delivered'}`
      );
      // Discord allows ~5 webhook messages per 2s per channel; five clusters fit, spaced.
      if (index < missions.length - 1 && !DRY_RUN) await new Promise((resolve) => setTimeout(resolve, 1200));
      if (!result.sent && !result.dryRun) process.exitCode = 1;
    }
    console.log(`prototype: day ${day} → ${missions.length} message(s)`);
    return;
  }

  if (job === 'health') {
    const outcome = await health();
    if (outcome.embed) {
      const result = await post('alerts', outcome.embed);
      if (result.sent && outcome.alert) outcome.state.last_alert_at = new Date().toISOString();
      // A failure that could not be delivered must stay visible in the Actions run.
      if (!result.sent && !result.dryRun && outcome.alert) process.exitCode = 1;
    }
    if (!DRY_RUN) writeHealthState(outcome.state);
    return;
  }

  let payload = null;
  if (job === 'standup') payload = await standup();
  else if (job === 'weekly') payload = await weekly();
  else if (job === 'deps') payload = deps();
  else payload = testMessage();

  if (!payload) return;
  await post(CHANNEL_OF[job], payload);
}

main().catch((error) => {
  console.error(`cloud-notify failed: ${error?.stack || error}`);
  process.exit(1);
});
