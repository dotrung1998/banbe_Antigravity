import { betterAuth } from "better-auth";

// Local-only proof that Better Auth can own users/sessions in D1 on Workers.
//
// This is NOT wired into the banbe app. Supabase Auth, RLS and the 224-entry
// Postgres migration chain remain the production source of truth until the
// phases in docs/cloudflare-d1-better-auth-migration.md have passed.
//
// D1 has no row-level security. Every query for tenant data below resolves the
// caller with auth.api.getSession(request.headers) and binds session.user.id;
// no user id is ever read from the path, query string or JSON body.

const AUTH_PREFIX = "/api/auth";
const MAX_NOTE_LENGTH = 500;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const authCache = new WeakMap();

function baseUrl(env) {
  const value = env.BETTER_AUTH_URL;
  if (!value) throw new Error("BETTER_AUTH_URL_MISSING");
  return String(value).replace(/\/+$/, "");
}

function getAuth(env) {
  let auth = authCache.get(env.DB);
  if (!auth) {
    if (!env.BETTER_AUTH_SECRET) throw new Error("BETTER_AUTH_SECRET_MISSING");
    auth = betterAuth({
      database: env.DB,
      secret: env.BETTER_AUTH_SECRET,
      baseURL: baseUrl(env),
      basePath: AUTH_PREFIX,
      trustedOrigins: [baseUrl(env)],
      emailAndPassword: { enabled: true },
      advanced: {
        // Workers do not carry the client address in X-Forwarded-For.
        ipAddress: { ipAddressHeaders: ["cf-connecting-ip"] },
      },
    });
    authCache.set(env.DB, auth);
  }
  return auth;
}

function withSecurityHeaders(response) {
  const headers = new Headers(response.headers);
  headers.set("x-content-type-options", "nosniff");
  headers.set("referrer-policy", "no-referrer");
  if (!headers.has("cache-control")) headers.set("cache-control", "no-store");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function json(body, status = 200) {
  return withSecurityHeaders(new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  }));
}

function sameOrigin(request, env) {
  const origin = request.headers.get("origin");
  // Non-browser clients do not send Origin; browsers do, including on a
  // cross-site form/fetch, so an unexpected Origin is refused.
  return !origin || origin === baseUrl(env);
}

async function currentUser(auth, request) {
  const session = await auth.api.getSession({ headers: request.headers });
  return session?.user || null;
}

async function listNotes(env, userId) {
  const { results } = await env.DB
    .prepare("SELECT id, body, created_at FROM notes WHERE user_id = ? ORDER BY created_at DESC, id")
    .bind(userId)
    .all();
  return results || [];
}

async function createNote(env, userId, body) {
  const text = typeof body?.body === "string" ? body.body.trim() : "";
  if (!text || text.length > MAX_NOTE_LENGTH) {
    return { error: "VALID_NOTE_REQUIRED", status: 400 };
  }
  const id = crypto.randomUUID();
  await env.DB
    .prepare("INSERT INTO notes (id, user_id, body) VALUES (?, ?, ?)")
    .bind(id, userId, text)
    .run();
  return { id, body: text };
}

async function deleteNote(env, userId, id) {
  if (!UUID.test(id)) return false;
  const { meta } = await env.DB
    .prepare("DELETE FROM notes WHERE id = ? AND user_id = ?")
    .bind(id, userId)
    .run();
  return (meta?.changes || 0) > 0;
}

async function handleNotes(request, env, url) {
  const auth = getAuth(env);
  const user = await currentUser(auth, request);
  if (!user) return json({ error: "AUTH_REQUIRED" }, 401);

  if (url.pathname === "/api/notes" && request.method === "GET") {
    return json({ notes: await listNotes(env, user.id) });
  }

  if (url.pathname === "/api/notes" && request.method === "POST") {
    if (!sameOrigin(request, env)) return json({ error: "INVALID_ORIGIN" }, 403);
    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "INVALID_JSON" }, 400);
    }
    const result = await createNote(env, user.id, body);
    if (result.error) return json({ error: result.error }, result.status);
    return json(result, 201);
  }

  if (url.pathname.startsWith("/api/notes/") && request.method === "DELETE") {
    if (!sameOrigin(request, env)) return json({ error: "INVALID_ORIGIN" }, 403);
    const id = decodeURIComponent(url.pathname.slice("/api/notes/".length));
    const deleted = await deleteNote(env, user.id, id);
    return deleted ? json({ ok: true }) : json({ error: "NOT_FOUND" }, 404);
  }

  return json({ error: "METHOD_NOT_ALLOWED" }, 405);
}

async function handle(request, env) {
  const url = new URL(request.url);

  if (url.pathname === "/health") {
    const row = await env.DB.prepare('SELECT count(*) AS users FROM "user"').first();
    return json({ ok: true, runtime: "workers", users: row?.users ?? 0 });
  }

  if (url.pathname.startsWith(AUTH_PREFIX)) {
    return withSecurityHeaders(await getAuth(env).handler(request));
  }

  if (url.pathname === "/api/notes" || url.pathname.startsWith("/api/notes/")) {
    return handleNotes(request, env, url);
  }

  return json({
    ok: true,
    note: "banbe D1 + Better Auth spike. Not the production app.",
    endpoints: ["GET /health", "/api/auth/*", "GET|POST /api/notes", "DELETE /api/notes/:id"],
  });
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      // Never echo a secret, cookie or D1 error detail to the caller.
      console.error("auth-spike request failed:", error?.message || error);
      return json({ error: "INTERNAL_ERROR" }, 500);
    }
  },
};
