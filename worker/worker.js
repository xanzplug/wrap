// Wrap delivery service (Cloudflare Worker, free plan).
//
// - Receives a file from the Wrap Mac app and stores it in Supabase Storage.
// - Gives each file a share link: /d/<token> is a download page for the client.
// - Deletes files an hour after the first download, or after 48 hours unused.
//
// Settings (Cloudflare dashboard > Worker > Settings):
//   Variables: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY
//   Secret:    SUPABASE_SECRET_KEY  (Supabase > Project Settings > API Keys > secret key)
//   Cron:      every hour  (0 * * * *)

const BUCKET = "deliveries";               // private Supabase Storage bucket
const MAX_FILE_BYTES = 50 * 1024 * 1024;   // Supabase free plan: 50 MB per file
const MAX_ACTIVE_BYTES = 900 * 1024 * 1024; // Supabase free plan has 1 GB of storage in total
const EXPIRY_HOURS = 48;                   // unused links expire after this
const GRACE_MINUTES_AFTER_DOWNLOAD = 60;   // time to retry a dropped download

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);

    try {
      // Client-facing download page and file
      if (parts[0] === "d" && parts[1] && request.method === "GET") {
        if (parts[2] === "file") return await serveFile(parts[1], request, env, ctx);
        return await downloadPage(parts[1], env);
      }

      // App-facing API (needs a logged-in Wrap user)
      if (parts[0] === "deliveries") {
        const user = await authenticate(request, env);
        if (!user) return json({ error: "Please log in to Wrap again." }, 401);

        if (parts.length === 1 && request.method === "POST") return await createDelivery(request, env, user, url);
        if (parts.length === 2 && request.method === "DELETE") return await cancelDelivery(parts[1], env, user);
      }

      if (url.pathname === "/") return new Response("Wrap delivery service is running.", { status: 200 });
      return new Response("Not found", { status: 404 });
    } catch (error) {
      return json({ error: error.message || "Something went wrong." }, 500);
    }
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(cleanup(env));
  },
};

// ---------- App API ----------

async function createDelivery(request, env, user, url) {
  const fileName = cleanFileName(decodeURIComponent(request.headers.get("X-File-Name") || "file"));
  const projectId = request.headers.get("X-Project-Id") || null;
  const size = Number(request.headers.get("Content-Length")) || 0;
  const contentType = request.headers.get("Content-Type") || "application/octet-stream";

  if (size > MAX_FILE_BYTES) {
    return json({ error: `That file is ${formatBytes(size)}. Files can be up to 50 MB on the free plan.` }, 413);
  }

  // Space for files that are still waiting to be downloaded.
  const active = await db(env, `deliveries?user_id=eq.${user.id}&status=in.(uploading,ready,downloaded)&select=size_bytes`);
  const used = active.reduce((sum, d) => sum + Number(d.size_bytes || 0), 0);
  if (used + size > MAX_ACTIVE_BYTES) {
    return json({ error: `Not enough space. ${formatBytes(used)} is still waiting for clients to download. Space frees up as they do.` }, 413);
  }

  const id = crypto.randomUUID();
  const token = randomToken();
  const key = `${user.id}/${id}/${fileName}`;

  const stored = await fetch(`${env.SUPABASE_URL}/storage/v1/object/${BUCKET}/${encodePath(key)}`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SECRET_KEY,
      "Content-Type": contentType,
      "x-upsert": "false",
    },
    body: request.body,
  });
  if (!stored.ok) {
    return json({ error: `Couldn't store the file (${stored.status}). ${await stored.text()}` }, 502);
  }

  const expiresAt = new Date(Date.now() + EXPIRY_HOURS * 3600e3).toISOString();
  await db(env, "deliveries", {
    method: "POST",
    body: JSON.stringify({
      id,
      user_id: user.id,
      project_id: projectId,
      file_name: fileName,
      size_bytes: size,
      r2_key: key,
      token,
      status: "ready",
      expires_at: expiresAt,
    }),
  });

  return json({ id, link: `${url.origin}/d/${token}`, token, expires_at: expiresAt });
}

async function cancelDelivery(id, env, user) {
  const row = await ownDelivery(id, env, user);
  if (!row) return json({ error: "Not found." }, 404);
  await removeFile(row, env);
  await db(env, `deliveries?id=eq.${id}`, {
    method: "PATCH",
    body: JSON.stringify({ status: "cancelled", upload_id: null }),
  });
  return json({ ok: true });
}

// ---------- Client download ----------

async function downloadPage(token, env) {
  const row = await deliveryByToken(token, env);
  if (!isAvailable(row)) {
    return html(page(`
      <p class="eyebrow">Wrap delivery</p>
      <h1>This link has expired.</h1>
      <p class="hint">Files are removed after they've been downloaded, or after 48 hours. Ask the sender for a new link.</p>`), 410);
  }

  const until = new Date(availableUntil(row)).toUTCString().replace(" GMT", " UTC");
  return html(page(`
    <p class="eyebrow">Wrap delivery</p>
    <h1>${escapeHTML(row.file_name)}</h1>
    <p class="meta">${formatBytes(row.size_bytes)} · available until ${until}</p>
    <a class="button" href="/d/${encodeURIComponent(token)}/file">Download</a>
    <p class="hint">No account needed. This file is deleted after it's downloaded.</p>`));
}

async function serveFile(token, request, env, ctx) {
  const row = await deliveryByToken(token, env);
  if (!isAvailable(row)) return new Response("This link has expired.", { status: 410 });

  const rangeHeader = request.headers.get("range");
  const upstream = await fetch(`${env.SUPABASE_URL}/storage/v1/object/authenticated/${BUCKET}/${encodePath(row.r2_key)}`, {
    headers: {
      apikey: env.SUPABASE_SECRET_KEY,
      ...(rangeHeader ? { Range: rangeHeader } : {}),
    },
  });
  if (!upstream.ok && upstream.status !== 206) return new Response("File not found.", { status: 404 });

  const headers = new Headers();
  for (const name of ["Content-Type", "Content-Length", "Content-Range", "ETag", "Last-Modified"]) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  headers.set("Accept-Ranges", "bytes");
  headers.set("Content-Disposition", `attachment; filename="${row.file_name.replace(/"/g, "")}"`);

  // Count a download when it starts from the beginning of the file.
  if (!rangeHeader || /^bytes=0-/.test(rangeHeader)) {
    ctx.waitUntil(db(env, `deliveries?id=eq.${row.id}`, {
      method: "PATCH",
      body: JSON.stringify({
        status: "downloaded",
        downloaded_at: row.downloaded_at || new Date().toISOString(),
        download_count: (row.download_count || 0) + 1,
      }),
    }));
  }

  return new Response(upstream.body, { status: upstream.status, headers });
}

function isAvailable(row) {
  if (!row || (row.status !== "ready" && row.status !== "downloaded")) return false;
  return Date.now() < availableUntil(row);
}

function availableUntil(row) {
  const expires = Date.parse(row.expires_at);
  if (!row.downloaded_at) return expires;
  return Math.min(expires, Date.parse(row.downloaded_at) + GRACE_MINUTES_AFTER_DOWNLOAD * 60e3);
}

// ---------- Cleanup (runs every hour) ----------

async function cleanup(env) {
  const now = new Date().toISOString();
  const grace = new Date(Date.now() - GRACE_MINUTES_AFTER_DOWNLOAD * 60e3).toISOString();
  const filter = encodeURIComponent(`(expires_at.lt.${now},and(status.eq.downloaded,downloaded_at.lt.${grace}))`);
  const rows = await db(env, `deliveries?status=in.(uploading,ready,downloaded)&or=${filter}&select=*`);
  for (const row of rows) {
    await removeFile(row, env);
    await db(env, `deliveries?id=eq.${row.id}`, {
      method: "PATCH",
      body: JSON.stringify({ status: "expired", upload_id: null }),
    });
  }
}

async function removeFile(row, env) {
  try {
    await fetch(`${env.SUPABASE_URL}/storage/v1/object/${BUCKET}`, {
      method: "DELETE",
      headers: { apikey: env.SUPABASE_SECRET_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ prefixes: [row.r2_key] }),
    });
  } catch (_) {
    // Already gone.
  }
}

// ---------- Supabase ----------

async function authenticate(request, env) {
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return null;
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: auth },
  });
  if (!response.ok) return null;
  const user = await response.json();
  return user && user.id ? user : null;
}

async function db(env, path, init = {}) {
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env.SUPABASE_SECRET_KEY,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers || {}),
    },
  });
  if (!response.ok) throw new Error(`Database error ${response.status}: ${await response.text()}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

async function ownDelivery(id, env, user) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const rows = await db(env, `deliveries?id=eq.${id}&user_id=eq.${user.id}&select=*`);
  return rows[0] || null;
}

async function deliveryByToken(token, env) {
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(token)) return null;
  const rows = await db(env, `deliveries?token=eq.${token}&select=*`);
  return rows[0] || null;
}

// ---------- Helpers ----------

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(18));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function cleanFileName(name) {
  const cleaned = String(name || "file").replace(/[\/\\\u0000-\u001f"]/g, "_").trim();
  return (cleaned || "file").slice(0, 200);
}

function formatBytes(bytes) {
  const n = Number(bytes) || 0;
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  let value = n;
  while (value >= 1000 && i < units.length - 1) { value /= 1000; i++; }
  return `${value.toFixed(value < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

function encodePath(path) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}

function html(body, status = 200) {
  return new Response(body, { status, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

function page(content) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Wrap delivery</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: #0a0a0a; color: #fff;
         font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", sans-serif;
         display: flex; flex-direction: column; }
  header { padding: 20px 24px; border-bottom: 1px solid rgba(255,255,255,.09);
           font-weight: 600; letter-spacing: -.02em; font-size: 16px; }
  main { flex: 1; display: flex; align-items: center; justify-content: center; padding: 48px 20px; }
  .card { width: 100%; max-width: 520px; }
  .eyebrow { margin: 0 0 12px; font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: rgba(255,255,255,.55); }
  h1 { margin: 0 0 10px; font-size: clamp(28px, 6vw, 40px); font-weight: 500; letter-spacing: -.03em; line-height: 1.1; word-break: break-word; }
  .meta { margin: 0 0 28px; color: rgba(255,255,255,.55); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }
  .button { display: inline-block; background: #fff; color: #000; text-decoration: none;
            padding: 11px 26px; border-radius: 999px; font-weight: 500; }
  .button:hover { opacity: .85; }
  .hint { margin-top: 24px; color: rgba(255,255,255,.55); font-size: 13px; }
</style>
</head>
<body>
<header>wrap</header>
<main><div class="card">${content}</div></main>
</body>
</html>`;
}
