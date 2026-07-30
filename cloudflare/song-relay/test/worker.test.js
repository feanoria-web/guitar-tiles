import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.js";

class MemoryR2 {
  constructor() {
    this.objects = new Map();
  }

  async put(key, value, options = {}) {
    let bytes;
    if (typeof value === "string") {
      bytes = new TextEncoder().encode(value);
    } else {
      bytes = new Uint8Array(await new Response(value).arrayBuffer());
    }
    this.objects.set(key, {
      bytes,
      httpMetadata: options.httpMetadata || {},
      customMetadata: options.customMetadata || {},
    });
  }

  async get(key) {
    const stored = this.objects.get(key);
    if (!stored) return null;
    return this.object(stored);
  }

  async head(key) {
    const stored = this.objects.get(key);
    if (!stored) return null;
    return this.object(stored);
  }

  async list({ prefix = "" }) {
    const objects = [...this.objects.entries()]
      .filter(([key]) => key.startsWith(prefix))
      .map(([key, stored]) => ({ key, size: stored.bytes.length }));
    return { objects, truncated: false };
  }

  async delete(keys) {
    for (const key of Array.isArray(keys) ? keys : [keys]) {
      this.objects.delete(key);
    }
  }

  object(stored) {
    return {
      size: stored.bytes.length,
      body: stored.bytes,
      httpEtag: '"test-etag"',
      async json() {
        return JSON.parse(new TextDecoder().decode(stored.bytes));
      },
    };
  }
}

function token(uid) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "none" })}.${encode({ sub: uid })}.test`;
}

function apiRequest(path, method, uid, body, contentType = "application/json") {
  const headers = {
    authorization: `Bearer ${token(uid)}`,
    "content-type": contentType,
  };
  return new Request(`https://relay.test${path}`, {
    method,
    headers,
    body: body === undefined
      ? undefined
      : contentType === "application/json"
        ? JSON.stringify(body)
        : body,
  });
}

test("host uploads once and a room guest downloads from R2", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({
    meta: { host_uid: "host-1" },
    players: {
      "host-1": { uid: "host-1" },
      "guest-1": { uid: "guest-1" },
    },
  }), { status: 200, headers: { "content-type": "application/json" } });

  try {
    const env = {
      SONGS: new MemoryR2(),
      FIREBASE_DATABASE_URL: "https://example-default-rtdb.firebaseio.com",
    };
    const fingerprint = "0123456789abcdef0123456789abcdef";
    const base = `/v1/rooms/ABC234/songs/${fingerprint}`;
    const manifest = {
      name: "Test Song",
      single_file: true,
      entry_relative: "test.sng",
      files: [{
        relative_path: "test.sng",
        size: 6,
        md5: "e80b5017098950fc58aad83c8c14978e",
      }],
      total_size: 6,
    };

    const guestPrepare = await worker.fetch(
      apiRequest(`${base}/manifest`, "POST", "guest-1", manifest),
      env,
    );
    assert.equal(guestPrepare.status, 403);

    const prepare = await worker.fetch(
      apiRequest(`${base}/manifest`, "POST", "host-1", manifest),
      env,
    );
    assert.equal(prepare.status, 200);

    const notReady = await worker.fetch(
      apiRequest(`${base}/manifest`, "GET", "guest-1"),
      env,
    );
    assert.equal(notReady.status, 409);

    const bytes = new TextEncoder().encode("abcdef");
    const put = await worker.fetch(
      apiRequest(
        `${base}/files/0/chunks/0`,
        "PUT",
        "host-1",
        bytes,
        "application/octet-stream",
      ),
      env,
    );
    assert.equal(put.status, 200, await put.clone().text());

    const complete = await worker.fetch(
      apiRequest(`${base}/complete`, "POST", "host-1", {}),
      env,
    );
    assert.equal(complete.status, 200);

    const ready = await worker.fetch(
      apiRequest(`${base}/manifest`, "GET", "guest-1"),
      env,
    );
    assert.equal(ready.status, 200);

    const download = await worker.fetch(
      apiRequest(`${base}/files/0/chunks/0`, "GET", "guest-1"),
      env,
    );
    assert.equal(download.status, 200);
    assert.equal(await download.text(), "abcdef");
  } finally {
    globalThis.fetch = originalFetch;
  }
});
