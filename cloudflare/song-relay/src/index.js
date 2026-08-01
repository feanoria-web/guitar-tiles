const CHUNK_BYTES = 4 * 1024 * 1024;
const MAX_SONG_BYTES = 512 * 1024 * 1024;
const MAX_FILES = 256;
const MAX_NAME_LENGTH = 160;
const MAX_PATH_LENGTH = 512;
const CACHE_SECONDS = 15;

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export default {
  async fetch(request, env) {
    try {
      if (request.method === "OPTIONS") {
        return withCors(new Response(null, { status: 204 }), request, env);
      }

      const url = new URL(request.url);
      if (url.pathname === "/health" && request.method === "GET") {
        return withCors(json({ ok: true, service: "riffline-song-relay" }), request, env);
      }

      const route = parseRoute(url.pathname);
      if (!route) {
        return withCors(json({ ok: false, error: "Not found" }, 404), request, env);
      }

      const token = bearerToken(request);
      if (!token) {
        return withCors(json({ ok: false, error: "Firebase token missing" }, 401), request, env);
      }

      const membership = await authorizeRoom(env, token, route.room);
      if (!membership.ok) {
        return withCors(json({ ok: false, error: membership.error }, membership.status), request, env);
      }

      let response;
      if (route.action === "manifest" && request.method === "POST") {
        response = await prepareSong(request, env, route, membership);
      } else if (route.action === "manifest" && request.method === "GET") {
        response = await getManifest(env, route);
      } else if (route.action === "complete" && request.method === "POST") {
        response = await completeSong(env, route, membership);
      } else if (route.action === "chunk" && request.method === "PUT") {
        response = await putChunk(request, env, route, membership);
      } else if (route.action === "chunk" && request.method === "GET") {
        response = await getChunk(env, route);
      } else if (route.action === "song" && request.method === "DELETE") {
        response = await deleteSong(env, route, membership);
      } else {
        response = json({ ok: false, error: "Method not allowed" }, 405);
      }
      return withCors(response, request, env);
    } catch (error) {
      console.error("Unhandled request error", error);
      return withCors(
        json({ ok: false, error: "Internal server error" }, 500),
        request,
        env,
      );
    }
  },
};

function parseRoute(pathname) {
  const parts = pathname.split("/").filter(Boolean);
  if (parts.length < 5 || parts[0] !== "v1" || parts[1] !== "rooms" || parts[3] !== "songs") {
    return null;
  }
  const room = parts[2].toUpperCase();
  const fingerprint = parts[4].toLowerCase();
  if (!/^[A-Z2-9]{6}$/.test(room) || !/^[a-f0-9]{32}$/.test(fingerprint)) {
    return null;
  }
  if (parts.length === 5) {
    return { room, fingerprint, action: "song" };
  }
  if (parts.length === 6 && parts[5] === "manifest") {
    return { room, fingerprint, action: "manifest" };
  }
  if (parts.length === 6 && parts[5] === "complete") {
    return { room, fingerprint, action: "complete" };
  }
  if (
    parts.length === 9
    && parts[5] === "files"
    && parts[7] === "chunks"
    && /^\d+$/.test(parts[6])
    && /^\d+$/.test(parts[8])
  ) {
    return {
      room,
      fingerprint,
      action: "chunk",
      fileIndex: Number(parts[6]),
      chunkIndex: Number(parts[8]),
    };
  }
  return null;
}

async function authorizeRoom(env, token, roomCode) {
  const uid = tokenUid(token);
  if (!uid) {
    return { ok: false, status: 401, error: "Invalid Firebase token" };
  }
  const baseUrl = String(env.FIREBASE_DATABASE_URL || "").replace(/\/+$/, "");
  if (!baseUrl.startsWith("https://")) {
    return { ok: false, status: 500, error: "Firebase database URL is not configured" };
  }

  const roomUrl = `${baseUrl}/rooms/${roomCode}.json?auth=${encodeURIComponent(token)}`;
  let firebaseResponse;
  try {
    firebaseResponse = await fetch(roomUrl, {
      headers: { accept: "application/json" },
      cf: { cacheTtl: 0, cacheEverything: false },
    });
  } catch {
    return { ok: false, status: 503, error: "Firebase could not be reached" };
  }
  if (firebaseResponse.status === 401 || firebaseResponse.status === 403) {
    return { ok: false, status: 401, error: "Firebase token rejected" };
  }
  if (!firebaseResponse.ok) {
    return { ok: false, status: 503, error: "Room validation failed" };
  }
  const room = await firebaseResponse.json();
  if (!room || typeof room !== "object") {
    return { ok: false, status: 404, error: "Room not found" };
  }
  const player = room.players?.[uid];
  if (!player || player.uid !== uid) {
    return { ok: false, status: 403, error: "Player is not in this room" };
  }
  return {
    ok: true,
    uid,
    isHost: room.meta?.host_uid === uid,
  };
}

async function prepareSong(request, env, route, membership) {
  if (!membership.isHost) {
    return json({ ok: false, error: "Only the room host may upload a song" }, 403);
  }
  let input;
  try {
    input = await request.json();
  } catch {
    return json({ ok: false, error: "Manifest must be valid JSON" }, 400);
  }
  const normalized = normalizeManifest(input, route.fingerprint, membership.uid);
  if (!normalized.ok) {
    return json({ ok: false, error: normalized.error }, 400);
  }

  const key = manifestKey(route);
  const existingObject = await env.SONGS.get(key);
  if (existingObject) {
    try {
      const existing = await existingObject.json();
      if (existing.ready === true && manifestSignature(existing) === manifestSignature(normalized.manifest)) {
        return json({ ok: true, already_ready: true, manifest: publicManifest(existing) });
      }
    } catch {
      // A malformed/incomplete old manifest is safe to replace.
    }
  }

  await deletePrefix(env.SONGS, chunkPrefix(route));
  await env.SONGS.put(key, JSON.stringify(normalized.manifest), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
    customMetadata: {
      owner: membership.uid,
      ready: "false",
      expires_at: String(normalized.manifest.expires_at),
    },
  });
  return json({ ok: true, already_ready: false, manifest: publicManifest(normalized.manifest) });
}

async function putChunk(request, env, route, membership) {
  if (!membership.isHost) {
    return json({ ok: false, error: "Only the room host may upload chunks" }, 403);
  }
  const stored = await readStoredManifest(env.SONGS, route);
  if (!stored.ok) {
    return json({ ok: false, error: stored.error }, stored.status);
  }
  const manifest = stored.manifest;
  if (manifest.owner_uid !== membership.uid) {
    return json({ ok: false, error: "Upload owner mismatch" }, 403);
  }
  if (manifest.ready) {
    return json({ ok: true, already_ready: true });
  }
  const expected = expectedChunkSize(manifest, route.fileIndex, route.chunkIndex);
  if (expected < 0) {
    return json({ ok: false, error: "Chunk index is outside the manifest" }, 400);
  }
  const contentLengthHeader = request.headers.get("content-length");
  const contentLength = contentLengthHeader === null ? null : Number(contentLengthHeader);
  if (contentLength !== null && contentLength !== expected) {
    return json({ ok: false, error: `Expected ${expected} bytes` }, 400);
  }
  let uploadBody = request.body;
  if (contentLength === null) {
    const buffered = await request.arrayBuffer();
    if (buffered.byteLength !== expected) {
      return json({ ok: false, error: `Expected ${expected} bytes` }, 400);
    }
    uploadBody = buffered;
  }
  await env.SONGS.put(chunkKey(route), uploadBody, {
    httpMetadata: { contentType: "application/octet-stream" },
    customMetadata: {
      owner: membership.uid,
      expected_size: String(expected),
    },
  });
  return json({ ok: true });
}

async function completeSong(env, route, membership) {
  if (!membership.isHost) {
    return json({ ok: false, error: "Only the room host may complete an upload" }, 403);
  }
  const stored = await readStoredManifest(env.SONGS, route);
  if (!stored.ok) {
    return json({ ok: false, error: stored.error }, stored.status);
  }
  const manifest = stored.manifest;
  if (manifest.owner_uid !== membership.uid) {
    return json({ ok: false, error: "Upload owner mismatch" }, 403);
  }
  if (manifest.ready) {
    return json({ ok: true, already_ready: true, manifest: publicManifest(manifest) });
  }

  for (let fileIndex = 0; fileIndex < manifest.files.length; fileIndex += 1) {
    const file = manifest.files[fileIndex];
    for (let chunkIndex = 0; chunkIndex < file.chunk_count; chunkIndex += 1) {
      const expected = expectedChunkSize(manifest, fileIndex, chunkIndex);
      const object = await env.SONGS.head(chunkKey({ ...route, fileIndex, chunkIndex }));
      if (!object || object.size !== expected) {
        return json({
          ok: false,
          error: "Upload is incomplete",
          missing_file: fileIndex,
          missing_chunk: chunkIndex,
        }, 409);
      }
    }
  }

  manifest.ready = true;
  manifest.completed_at = Date.now();
  await env.SONGS.put(manifestKey(route), JSON.stringify(manifest), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
    customMetadata: {
      owner: membership.uid,
      ready: "true",
      expires_at: String(manifest.expires_at),
    },
  });
  return json({ ok: true, manifest: publicManifest(manifest) });
}

async function getManifest(env, route) {
  const stored = await readStoredManifest(env.SONGS, route);
  if (!stored.ok) {
    return json({ ok: false, error: stored.error }, stored.status);
  }
  if (!stored.manifest.ready) {
    return json({ ok: false, error: "Song is still uploading" }, 409);
  }
  return json({ ok: true, manifest: publicManifest(stored.manifest) });
}

async function getChunk(env, route) {
  const stored = await readStoredManifest(env.SONGS, route);
  if (!stored.ok) {
    return json({ ok: false, error: stored.error }, stored.status);
  }
  if (!stored.manifest.ready) {
    return json({ ok: false, error: "Song is still uploading" }, 409);
  }
  const expected = expectedChunkSize(stored.manifest, route.fileIndex, route.chunkIndex);
  if (expected < 0) {
    return json({ ok: false, error: "Chunk not found" }, 404);
  }
  const object = await env.SONGS.get(chunkKey(route));
  if (!object || object.size !== expected) {
    return json({ ok: false, error: "Chunk not found" }, 404);
  }
  return new Response(object.body, {
    headers: {
      "content-type": "application/octet-stream",
      "content-length": String(object.size),
      "cache-control": `private, max-age=${CACHE_SECONDS}`,
      etag: object.httpEtag,
    },
  });
}

async function deleteSong(env, route, membership) {
  if (!membership.isHost) {
    return json({ ok: false, error: "Only the room host may delete a song" }, 403);
  }
  await deletePrefix(env.SONGS, songPrefix(route));
  return json({ ok: true });
}

function normalizeManifest(input, fingerprint, ownerUid) {
  if (!input || typeof input !== "object" || !Array.isArray(input.files)) {
    return { ok: false, error: "Invalid manifest" };
  }
  if (input.files.length < 1 || input.files.length > MAX_FILES) {
    return { ok: false, error: "Invalid file count" };
  }
  const name = cleanText(input.name, MAX_NAME_LENGTH);
  const entryRelative = safeRelativePath(input.entry_relative);
  if (!name || !entryRelative) {
    return { ok: false, error: "Song name or entry path is invalid" };
  }

  let totalSize = 0;
  const files = [];
  for (const item of input.files) {
    const relativePath = safeRelativePath(item?.relative_path);
    const size = Number(item?.size);
    const md5 = String(item?.md5 || "").toLowerCase();
    if (
      !relativePath
      || !Number.isSafeInteger(size)
      || size < 0
      || size > MAX_SONG_BYTES
      || !/^[a-f0-9]{32}$/.test(md5)
    ) {
      return { ok: false, error: "Invalid file entry" };
    }
    totalSize += size;
    if (totalSize > MAX_SONG_BYTES) {
      return { ok: false, error: "Song is too large" };
    }
    files.push({
      relative_path: relativePath,
      size,
      md5,
      chunk_count: Math.ceil(size / CHUNK_BYTES),
    });
  }
  if (totalSize < 1 || !files.some((file) => file.relative_path === entryRelative)) {
    return { ok: false, error: "Entry file is missing" };
  }
  return {
    ok: true,
    manifest: {
      version: 1,
      fingerprint,
      name,
      single_file: input.single_file === true,
      entry_relative: entryRelative,
      total_size: totalSize,
      chunk_bytes: CHUNK_BYTES,
      files,
      owner_uid: ownerUid,
      ready: false,
      created_at: Date.now(),
      expires_at: Date.now() + 24 * 60 * 60 * 1000,
    },
  };
}

function publicManifest(manifest) {
  return {
    version: manifest.version,
    fingerprint: manifest.fingerprint,
    name: manifest.name,
    single_file: manifest.single_file,
    entry_relative: manifest.entry_relative,
    total_size: manifest.total_size,
    chunk_bytes: manifest.chunk_bytes,
    files: manifest.files,
    ready: manifest.ready,
    expires_at: manifest.expires_at,
  };
}

function manifestSignature(manifest) {
  return JSON.stringify({
    fingerprint: manifest.fingerprint,
    single_file: manifest.single_file,
    entry_relative: manifest.entry_relative,
    total_size: manifest.total_size,
    files: manifest.files?.map((file) => ({
      relative_path: file.relative_path,
      size: file.size,
      md5: file.md5,
      chunk_count: file.chunk_count,
    })),
  });
}

async function readStoredManifest(bucket, route) {
  const object = await bucket.get(manifestKey(route));
  if (!object) {
    return { ok: false, status: 404, error: "Song has not been uploaded yet" };
  }
  try {
    const manifest = await object.json();
    return { ok: true, manifest };
  } catch {
    return { ok: false, status: 500, error: "Stored manifest is invalid" };
  }
}

function expectedChunkSize(manifest, fileIndex, chunkIndex) {
  if (!Number.isSafeInteger(fileIndex) || !Number.isSafeInteger(chunkIndex)) {
    return -1;
  }
  const file = manifest.files?.[fileIndex];
  if (!file || chunkIndex < 0 || chunkIndex >= file.chunk_count) {
    return -1;
  }
  const offset = chunkIndex * manifest.chunk_bytes;
  return Math.min(manifest.chunk_bytes, file.size - offset);
}

async function deletePrefix(bucket, prefix) {
  let cursor;
  do {
    const page = await bucket.list({ prefix, cursor, limit: 1000 });
    if (page.objects.length > 0) {
      await bucket.delete(page.objects.map((object) => object.key));
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}

function songPrefix(route) {
  return `rooms/${route.room}/${route.fingerprint}/`;
}

function chunkPrefix(route) {
  return `${songPrefix(route)}chunks/`;
}

function manifestKey(route) {
  return `${songPrefix(route)}manifest.json`;
}

function chunkKey(route) {
  return `${chunkPrefix(route)}${route.fileIndex}/${route.chunkIndex}`;
}

function bearerToken(request) {
  const header = request.headers.get("authorization") || "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() : "";
}

function tokenUid(token) {
  try {
    const payload = token.split(".")[1];
    if (!payload) return "";
    const padded = payload.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(payload.length / 4) * 4, "=");
    const decoded = JSON.parse(atob(padded));
    return cleanText(decoded.sub || decoded.user_id, 128);
  } catch {
    return "";
  }
}

function safeRelativePath(value) {
  const text = String(value || "").replace(/\\/g, "/").trim();
  if (!text || text.length > MAX_PATH_LENGTH || text.startsWith("/") || text.includes("\0")) {
    return "";
  }
  const parts = text.split("/");
  if (parts.some((part) => !part || part === "." || part === ".." || part.includes(":"))) {
    return "";
  }
  return parts.join("/");
}

function cleanText(value, maxLength) {
  const text = String(value || "").trim();
  if (!text || text.length > maxLength || /[\u0000-\u001f]/.test(text)) {
    return "";
  }
  return text;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function withCors(response, request, env) {
  const origin = request.headers.get("origin") || "";
  const allowed = String(env.ALLOWED_ORIGIN || "*");
  const allowOrigin = allowed === "*" || allowed === origin ? (allowed === "*" ? "*" : origin) : "null";
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", allowOrigin);
  headers.set("access-control-allow-methods", "GET,POST,PUT,DELETE,OPTIONS");
  headers.set("access-control-allow-headers", "authorization,content-type");
  headers.set("access-control-max-age", "86400");
  headers.set("vary", "Origin");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
