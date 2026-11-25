#!/usr/bin/env node
// UserPromptSubmit hook: append every prompt the owner types in this repo to the Second Brain inbox
// (docs/second-brain/raw/inbox/YYYY-MM-DD-chat.md, gitignored). Never blocks the prompt: always exits 0, prints nothing.
import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

try {
  const input = JSON.parse(readFileSync(0, 'utf8') || '{}');
  const prompt = String(input.prompt || '').trim();
  if (!prompt) process.exit(0);

  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const day = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  const time = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  const file = join(root, 'docs/second-brain/raw/inbox', `${day}-chat.md`);

  // Vault rule: no secrets, even in raw/. Mask the common token shapes.
  const clean = prompt
    .replace(/\b(sk|pk|rk)[-_][A-Za-z0-9_-]{16,}/g, '[redacted-key]')
    .replace(/\bgh[pousr]_[A-Za-z0-9]{20,}/g, '[redacted-github-token]')
    .replace(/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, '[redacted-jwt]')
    .replace(/\b[a-f0-9]{40,}\b/gi, '[redacted-hex]');

  const head = existsSync(file)
    ? ''
    : `---\ntype: chat\ndate: ${day}\nagent: claude-code hook\n---\n\n# Chat log — ${day}\n\nOwner prompts typed in this repo, appended by \`scripts/vault-log-prompt.mjs\`.\n`;
  const session = String(input.session_id || '').slice(0, 8);
  const body = clean.split('\n').map((l) => `> ${l}`).join('\n');
  appendFileSync(file, `${head}\n## ${time}${session ? ` · session ${session}` : ''}\n\n${body}\n`);
} catch {
  // logging must never get in the owner's way
}
process.exit(0);
