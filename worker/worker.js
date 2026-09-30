// Wrap delivery service (Cloudflare Worker).
//
// - Receives uploads from the Wrap Mac app in parts and stores them in R2.
// - Gives each file a share link: /d/<token> is a download page for the client.
// - Deletes files an hour after the first download, or after 48 hours unused.
//
// Settings (Cloudflare dashboard > Worker > Settings):
//   Bindings:  BUCKET  -> R2 bucket "wrap-deliveries"
//   Variables: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, MAX_ACTIVE_GB (optional, default 10)
//   Secret:    SUPABASE_SECRET_KEY  (Supabase > Project Settings > API Keys > secret key)
//   Cron:      every hour  (0 * * * *)

const PART_SIZE = 50 * 1024 * 1024;       // 50 MB per upload part
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

        if (parts.length === 1 && request.method === "POST") return await createDelivery(request, env, user);
        const id = parts[1];
        if (parts[2] === "parts" && request.method === "PUT") return await uploadPart(id, Number(parts[3]), request, env, user);
        if (parts[2] === "complete" && request.method === "POST") return await completeDelivery(id, request, env, user, url);
        if (parts.length === 2 && request.method === "DELETE") return await cancelDelivery(id, env, user);
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

async function createDelivery(request, env, user) {
  const body = await request.json();
  const fileName = cleanFileName(body.file_name);
  const size = Math.max(0, Number(body.size_bytes) || 0);

  // Per-account space for files that are still waiting to be downloaded.
  const limitBytes = (Number(env.MAX_ACTIVE_GB) || 10) * 1024 ** 3;
  const active = await db(env, `deliveries?user_id=eq.${user.id}&status=in.(uploading,ready)&select=size_bytes`);
  const used = active.reduce((sum, d) => sum + Number(d.size_bytes || 0), 0);
  if (used + size > limitBytes) {
    return json({ error: `Not enough space. ${gb(used)} of ${gb(limitBytes)} is waiting for clients to download.` }, 413);
  }

  const id = crypto.randomUUID();
  const token = randomToken();
  const key = `${user.id}/${id}/${fileName}`;
  const upload = await env.BUCKET.createMultipartUpload(key, {
    httpMetadata: { contentType: body.content_type || "application/octet-stream" },
  });

  await db(env, "deliveries", {
    method: "POST",
    body: JSON.stringify({
      id,
      user_id: user.id,
      project_id: body.project_id || null,
      file_name: fileName,
      size_bytes: size,
      r2_key: key,
      upload_id: upload.uploadId,
      token,
      status: "uploading",
      expires_at: new Date(Date.now() + EXPIRY_HOURS * 3600e3).toISOString(),
    }),
  });

  return json({ id, part_size: PART_SIZE });
}

async function uploadPart(id, partNumber, request, env, user) {
  const row = await ownDelivery(id, env, user);
  if (!row || row.status !== "uploading") return json({ error: "This upload isn't open any more." }, 404);
  if (!Number.isInteger(partNumber) || partNumber < 1) return json({ error: "Bad part number." }, 400);

  const upload = env.BUCKET.resumeMultipartUpload(row.r2_key, row.upload_id);
  const part = await upload.uploadPart(partNumber, request.body);
  return json({ part_number: part.partNumber, etag: part.etag });
}

async function completeDelivery(id, request, env, user, url) {
  const row = await ownDelivery(id, env, user);
  if (!row || row.status !== "uploading") return json({ error: "This upload isn't open any more." }, 404);

  const body = await request.json();
  const parts = (body.parts || []).map((p) => ({ partNumber: p.part_number, etag: p.etag }));
  const upload = env.BUCKET.resumeMultipartUpload(row.r2_key, row.upload_id);
  const object = await upload.complete(parts);

  await db(env, `deliveries?id=eq.${id}`, {
    method: "PATCH",
    body: JSON.stringify({ status: "ready", size_bytes: object.size, upload_id: null }),
  });

  return json({ link: `${url.origin}/d/${row.token}`, token: row.token, expires_at: row.expires_at });
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

  const object = await env.BUCKET.get(row.r2_key, { range: request.headers });
  if (!object) return new Response("File not found.", { status: 404 });

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Content-Disposition", `attachment; filename="${row.file_name.replace(/"/g, "")}"`);

  let status = 200;
  const rangeHeader = request.headers.get("range");
  if (rangeHeader && object.range) {
    let offset = object.range.offset ?? 0;
    let length = object.range.length ?? object.size - offset;
    if (object.range.suffix !== undefined) {
      length = Math.min(object.range.suffix, object.size);
      offset = object.size - length;
    }
    status = 206;
    headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("Content-Length", String(length));
  } else {
    headers.set("Content-Length", String(object.size));
  }

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

  return new Response(object.body, { status, headers });
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
    if (row.status === "uploading" && row.upload_id) {
      await env.BUCKET.resumeMultipartUpload(row.r2_key, row.upload_id).abort();
    } else {
      await env.BUCKET.delete(row.r2_key);
    }
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

function gb(bytes) {
  return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
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
