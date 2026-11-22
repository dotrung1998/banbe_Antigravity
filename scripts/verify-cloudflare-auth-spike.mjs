#!/usr/bin/env node
/**
 * Starts the local D1 + Better Auth Worker, then proves:
 *   1. health / D1 reachable
 *   2. two independent email/password accounts can sign up and get sessions
 *   3. account B cannot list or delete account A's note
 *   4. a SQL-injection string is stored as data (bind(), not concatenation)
 *   5. sign-out invalidates A's session while B stays signed in
 *
 * Local only: wrangler runs with --local, and the secret is generated for this
 * process. No remote D1, no production credentials, no network probes.
 */
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const config = join(root, "cloudflare/auth-spike/wrangler.jsonc");
const bin = join(root, "node_modules/.bin/wrangler");
const port = 8788;
const base = `http://127.0.0.1:${port}`;
const secret = randomBytes(32).toString("base64url");

if (!existsSync(bin)) {
  console.error("wrangler is not installed. Run npm install first.");
  process.exit(1);
}

function runMigrations() {
  execFileSync(bin, [
    "d1", "migrations", "apply", "banbe-auth-spike",
    "--local", "--config", config, "--force",
  ], { stdio: "inherit" });
}

async function waitForHealth(child, logs) {
  const deadline = Date.now() + 45_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`wrangler exited early (${child.exitCode})\n${logs()}`);
    }
    try {
      const response = await fetch(`${base}/health`);
      if (response.ok) return response.json();
    } catch {
      // not listening yet
    }
    await new Promise((resolve) => setTimeout(resolve, 400));
  }
  throw new Error(`wrangler did not answer ${base}/health\n${logs()}`);
}

function cookies(response) {
  const values = typeof response.headers.getSetCookie === "function"
    ? response.headers.getSetCookie()
    : [response.headers.get("set-cookie")].filter(Boolean);
  return values.map((value) => value.split(";")[0]).join("; ");
}

async function request(path, { method = "GET", cookie, body } = {}) {
  const headers = { origin: base };
  if (cookie) headers.cookie = cookie;
  if (body !== undefined) headers["content-type"] = "application/json";
  const response = await fetch(`${base}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { response, data, cookie: cookies(response) };
}

async function signUp(label) {
  const email = `spike-${label}-${Date.now()}-${randomUUID().slice(0, 8)}@example.test`;
  const result = await request("/api/auth/sign-up/email", {
    method: "POST",
    body: { email, password: "correct-horse-battery-staple", name: `Spike ${label}` },
  });
  assert.equal(result.response.status, 200, `sign-up ${label}: ${JSON.stringify(result.data)}`);
  assert.ok(result.cookie, `sign-up ${label} did not set a session cookie`);
  const session = await request("/api/auth/get-session", { cookie: result.cookie });
  assert.equal(session.response.status, 200);
  assert.equal(session.data?.user?.email, email, `sign-up ${label} has no session`);
  return { email, cookie: result.cookie };
}

runMigrations();

let child;
let stdout = "";
let stderr = "";
try {
  child = spawn(bin, [
    "dev",
    "--config", config,
    "--local",
    "--ip", "127.0.0.1",
    "--port", String(port),
    "--var", `BETTER_AUTH_URL:${base}`,
    "--var", `BETTER_AUTH_SECRET:${secret}`,
    "--log-level", "warn",
  ], { stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });

  const health = await waitForHealth(child, () => `${stdout}\n${stderr}`);
  assert.equal(health.ok, true);
  console.log("PASS  health: local D1 reachable on workerd");

  const anon = await request("/api/notes");
  assert.equal(anon.response.status, 401, "notes must require a session");
  console.log("PASS  no session: notes request is 401");

  const a = await signUp("a");
  console.log("PASS  account A: sign-up + session");

  const b = await signUp("b");
  console.log("PASS  account B: sign-up + session");

  const bEmpty = await request("/api/notes", { cookie: b.cookie });
  assert.deepEqual(bEmpty.data.notes, []);
  console.log("PASS  B sees zero notes before creating one");

  const created = await request("/api/notes", {
    method: "POST",
    cookie: a.cookie,
    body: { body: "A private note" },
  });
  assert.equal(created.response.status, 201, JSON.stringify(created.data));
  assert.ok(created.data.id);

  const bList = await request("/api/notes", { cookie: b.cookie });
  assert.deepEqual(bList.data.notes, []);
  console.log("PASS  B cannot list A's note");

  const bDelete = await request(`/api/notes/${created.data.id}`, {
    method: "DELETE",
    cookie: b.cookie,
  });
  assert.equal(bDelete.response.status, 404);
  console.log("PASS  B cannot delete A's note");

  const injected = await request("/api/notes", {
    method: "POST",
    cookie: a.cookie,
    body: { body: "x'); DROP TABLE notes; --" },
  });
  assert.equal(injected.response.status, 201);
  const aList = await request("/api/notes", { cookie: a.cookie });
  assert.equal(aList.data.notes.length, 2);
  assert.ok(aList.data.notes.some((note) => note.body === "x'); DROP TABLE notes; --"));
  console.log("PASS  SQL-injection text stays text: bind(), table intact");

  const signedOut = await request("/api/auth/sign-out", {
    method: "POST",
    cookie: a.cookie,
    body: {},
  });
  assert.equal(signedOut.response.status, 200, JSON.stringify(signedOut.data));
  const aSession = await request("/api/auth/get-session", {
    cookie: signedOut.cookie || a.cookie,
  });
  assert.equal(aSession.data?.user ?? null, null);
  const bSession = await request("/api/auth/get-session", { cookie: b.cookie });
  assert.equal(bSession.data?.user?.email, b.email);
  console.log("PASS  sign-out invalidates A; B's session is unaffected");

  console.log("\n8/8 checks passed: D1 + Better Auth + tenant isolation");
} finally {
  if (child && child.exitCode === null) {
    child.kill("SIGTERM");
    await new Promise((resolve) => {
      const timer = setTimeout(() => { child.kill("SIGKILL"); resolve(); }, 3_000);
      child.once("exit", () => { clearTimeout(timer); resolve(); });
    });
  }
}
