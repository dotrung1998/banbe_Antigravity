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
 *   node scripts/cloud-notify.mjs health      # hourly — silent unless a check fails
 *   node scripts/cloud-notify.mjs weekly      # Fri 17:00 ICT — the week's commits + hotspots
 *   node scripts/cloud-notify.mjs deps        # Sun 18:00 ICT — outdated packages + npm audit
 *   node scripts/cloud-notify.mjs test        # one message, to prove the webhook wiring
 *
 * Flags: --dry-run  print the payload and send nothing
 *        --always   health: post even when every check passes
 *
 * Webhooks (repo secrets, one URL per channel):
 *   DISCORD_WEBHOOK_STANDUP, DISCORD_WEBHOOK_ALERTS, DISCORD_WEBHOOK_WEEKLY
 *   DISCORD_WEBHOOK is a fallback for any of them, so one URL works everywhere.
 * An unset webhook is not an error: the message is printed to the job log and a
 * warning says which secret to add.
 *
 * Env: GITHUB_REPOSITORY + GITHUB_TOKEN (provided by Actions) for PRs and runs,
 *      APP_URL (default https://www.banbe.app) for the health check,
 *      SUPABASE_URL + SUPABASE_ANON_KEY for the optional API check.
 */
import { execFileSync } from 'node:child_process';

const JOB = process.argv[2];
const DRY_RUN = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
const ALWAYS = process.argv.includes('--always');

const APP_URL = process.env.APP_URL || 'https://www.banbe.app';
const TIME_ZONE = 'Asia/Ho_Chi_Minh';
const BRAND = { gold: 0xf6c453, moss: 0x8a9a7b, clay: 0xc0653f, red: 0xd64541 };

const CHANNEL_OF = {
  standup: 'standup',
  health: 'alerts',
  weekly: 'weekly',
  deps: 'weekly',
  test: 'alerts',
};

const clip = (value, max) => {
  const s = String(value ?? '');
  return s.length <= max ? s : `${s.slice(0, Math.max(0, max - 1))}…`;
};

const ictNow = () =>
  new Intl.DateTimeFormat('en-GB', {
    timeZone: TIME_ZONE,
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date());

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
  const url = process.env[`DISCORD_WEBHOOK_${channel.toUpperCase()}`] || process.env.DISCORD_WEBHOOK;
  if (!url) {
    console.warn(`no webhook configured for "${channel}" — set DISCORD_WEBHOOK_${channel.toUpperCase()} in repo secrets`);
    console.log(JSON.stringify(payload, null, 2));
    return { sent: false };
  }
  if (DRY_RUN) {
    console.log(`dry run — would post to ${channel}:`);
    console.log(JSON.stringify(payload, null, 2));
    return { sent: false, dryRun: true };
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
    await probe('Supabase REST', `${supabaseUrl}/rest/v1/`, {
      headers: { apikey: anonKey, authorization: `Bearer ${anonKey}`, 'user-agent': 'banbe-cloud-notify/1.0' },
    });
  } else {
    checks.push({ name: 'Supabase REST', ok: true, detail: 'skipped — no SUPABASE_ANON_KEY secret' });
  }

  const failed = checks.filter((check) => !check.ok);
  console.log(`health: ${checks.length - failed.length}/${checks.length} ok`);
  for (const check of checks) console.log(`  ${check.ok ? 'ok  ' : 'FAIL'} ${check.name}: ${check.detail}`);
  if (!failed.length && !ALWAYS) {
    console.log('healthy — nothing posted (alerts are sent only when a check fails)');
    return null;
  }
  return embed({
    title: failed.length ? '🚨 banbe health check failed' : 'banbe health check (manual)',
    description: failed.length
      ? `**${failed.length} of ${checks.length}** checks failed at ${ictNow()} ICT.`
      : `Every check passed at ${ictNow()} ICT.`,
    color: failed.length ? BRAND.red : BRAND.moss,
    fields: checks.map((check) => ({ name: check.name, value: `${check.ok ? '✅' : '❌'} ${check.detail}` })),
  });
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
    ].join('\n'),
    color: BRAND.clay,
  });
}

/* ------------------------------------------------------------------ main */

async function main() {
  const job = JOB || 'test';
  if (!CHANNEL_OF[job]) {
    console.error(`unknown job "${job}" — use standup | health | weekly | deps | test`);
    process.exit(2);
  }
  let payload = null;
  if (job === 'standup') payload = await standup();
  else if (job === 'weekly') payload = await weekly();
  else if (job === 'deps') payload = deps();
  else if (job === 'health') payload = await health();
  else payload = testMessage();

  if (!payload) return;
  const channel = CHANNEL_OF[job];
  const result = await post(channel, payload);
  if (job === 'health' && !result.sent && !result.dryRun) {
    // A failed check with no webhook must still be visible in the Actions run.
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`cloud-notify failed: ${error?.stack || error}`);
  process.exit(1);
});
