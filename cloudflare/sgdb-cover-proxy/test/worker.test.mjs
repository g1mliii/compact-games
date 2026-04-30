import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";
import { FakeD1Database } from "./support/fake-d1.mjs";
import { FakeKVNamespace } from "./support/fake-kv.mjs";

const BASE_TIME_MS = 1_775_000_000_000;
const AUTH_HEADER = "X-Compact-Games-Token";
const TOKEN = "test-proxy-token";

function createEnv(fetchHandler) {
  return {
    CACHE: new FakeKVNamespace(),
    DB: new FakeD1Database(),
    SGDB_API_KEY: "test-sgdb-key",
    COMPACT_GAMES_PROXY_TOKEN: TOKEN,
    IP_HASH_SECRET: "test-ip-hash-secret",
    SGDB_FETCH: fetchHandler ?? (() => jsonResponse({ data: [] })),
  };
}

async function fetchJson(env, path, init = {}) {
  const request = new Request(`https://proxy.example.test${path}`, {
    ...init,
    headers: {
      [AUTH_HEADER]: TOKEN,
      "CF-Connecting-IP": "203.0.113.8",
      ...(init.headers ?? {}),
    },
  });
  const response = await worker.fetch(request, env);
  const bodyText = await response.text();
  return {
    response,
    json: bodyText ? JSON.parse(bodyText) : null,
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

test("healthz is public and unknown routes are rejected", async () => {
  const env = createEnv();

  const health = await worker.fetch(new Request("https://proxy.example.test/healthz"), env);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { ok: true, service: "sgdb-cover-proxy" });

  const missing = await worker.fetch(new Request("https://proxy.example.test/missing"), env);
  assert.equal(missing.status, 404);
});

test("sgdb routes require a valid token", async () => {
  const env = createEnv();

  const response = await worker.fetch(
    new Request("https://proxy.example.test/sgdb/grid?steam_app_id=730&dimension=tall", {
      headers: { [AUTH_HEADER]: "wrong" },
    }),
    env,
  );

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "Unauthorized" });
});

test("query validation rejects bad dimensions, app ids, and names", async () => {
  const env = createEnv();

  const badDimension = await fetchJson(env, "/sgdb/grid?steam_app_id=730&dimension=poster");
  assert.equal(badDimension.response.status, 400);
  assert.equal(badDimension.json.error, "Invalid dimension");

  const badAppId = await fetchJson(env, "/sgdb/grid?steam_app_id=abc&dimension=tall");
  assert.equal(badAppId.response.status, 400);
  assert.equal(badAppId.json.error, "Invalid steam_app_id");

  const badName = await fetchJson(env, "/sgdb/by-name?name=%20%20%20&dimension=tall");
  assert.equal(badName.response.status, 400);
  assert.equal(badName.json.error, "Invalid name");
});

test("steam app id lookup returns selected grid url", async (t) => {
  t.mock.method(Date, "now", () => BASE_TIME_MS);
  const upstreamUrls = [];
  const env = createEnv((url) => {
    upstreamUrls.push(url);
    return jsonResponse({
      data: [
        {
          url: "https://cdn2.steamgriddb.com/grid/small.jpg",
          width: 342,
          height: 482,
        },
        {
          url: "https://cdn2.steamgriddb.com/grid/large.jpg",
          width: 660,
          height: 930,
        },
      ],
    });
  });

  const result = await fetchJson(env, "/sgdb/grid?steam_app_id=730&dimension=tall");

  assert.equal(result.response.status, 200);
  assert.deepEqual(result.json, {
    url: "https://cdn2.steamgriddb.com/grid/large.jpg",
    source: "steamgriddb",
  });
  assert.equal(upstreamUrls.length, 1);
  assert.match(upstreamUrls[0], /\/api\/v2\/grids\/steam\/730\?types=static&dimensions=342x482$/);
});

test("by-name lookup resolves game id before grid lookup", async (t) => {
  t.mock.method(Date, "now", () => BASE_TIME_MS);
  const upstreamUrls = [];
  const env = createEnv((url) => {
    upstreamUrls.push(url);
    if (url.includes("/search/autocomplete/")) {
      return jsonResponse({
        data: [
          { id: 10, name: "Other Game" },
          { id: 20, name: "Half-Life 2" },
        ],
      });
    }
    return jsonResponse({
      data: [
        {
          url: "https://cdn2.steamgriddb.com/grid/hl2.jpg",
          width: 600,
          height: 900,
        },
      ],
    });
  });

  const result = await fetchJson(env, "/sgdb/by-name?name=Half-Life%202&dimension=tall");

  assert.equal(result.response.status, 200);
  assert.deepEqual(result.json, {
    url: "https://cdn2.steamgriddb.com/grid/hl2.jpg",
    source: "steamgriddb",
  });
  assert.equal(upstreamUrls.length, 2);
  assert.match(upstreamUrls[0], /\/api\/v2\/search\/autocomplete\/Half-Life%202$/);
  assert.match(upstreamUrls[1], /\/api\/v2\/grids\/game\/20\?types=static&dimensions=342x482$/);
});

test("positive KV hits do not spend D1 rate-limit quota", async (t) => {
  t.mock.method(Date, "now", () => BASE_TIME_MS);
  let upstreamCalls = 0;
  const env = createEnv(() => {
    upstreamCalls += 1;
    return jsonResponse({
      data: [
        {
          url: "https://cdn2.steamgriddb.com/grid/cached.jpg",
          width: 600,
          height: 900,
        },
      ],
    });
  });

  const first = await fetchJson(env, "/sgdb/grid?steam_app_id=440&dimension=tall");
  const second = await fetchJson(env, "/sgdb/grid?steam_app_id=440&dimension=tall");

  assert.equal(first.response.status, 200);
  assert.equal(first.json.source, "steamgriddb");
  assert.equal(second.response.status, 200);
  assert.deepEqual(second.json, {
    url: "https://cdn2.steamgriddb.com/grid/cached.jpg",
    source: "cache",
  });
  assert.equal(upstreamCalls, 1);
  assert.equal([...env.DB.rateLimits.values()][0].count, 1);
});

test("negative-cache misses avoid repeated upstream calls", async (t) => {
  t.mock.method(Date, "now", () => BASE_TIME_MS);
  let upstreamCalls = 0;
  const env = createEnv(() => {
    upstreamCalls += 1;
    return jsonResponse({ data: [] });
  });

  const first = await fetchJson(env, "/sgdb/grid?steam_app_id=999999&dimension=tall");
  const second = await fetchJson(env, "/sgdb/grid?steam_app_id=999999&dimension=tall");

  assert.equal(first.response.status, 404);
  assert.equal(first.json.source, "steamgriddb");
  assert.equal(second.response.status, 404);
  assert.deepEqual(second.json, { error: "Not found", source: "negative_cache" });
  assert.equal(upstreamCalls, 3);
});

test("hourly hashed-IP miss limit rejects after 60 upstream cache misses", async (t) => {
  t.mock.method(Date, "now", () => BASE_TIME_MS);
  let upstreamCalls = 0;
  const env = createEnv(() => {
    upstreamCalls += 1;
    return jsonResponse({ data: [] });
  });

  for (let index = 0; index < 60; index += 1) {
    const result = await fetchJson(
      env,
      `/sgdb/grid?steam_app_id=${1000 + index}&dimension=tall`,
    );
    assert.equal(result.response.status, 404);
  }

  const rejected = await fetchJson(env, "/sgdb/grid?steam_app_id=2000&dimension=tall");
  assert.equal(rejected.response.status, 429);
  const expectedRetryAfter = Math.ceil(
    (Math.floor(BASE_TIME_MS / 3_600_000) * 3_600_000 + 3_600_000 - BASE_TIME_MS) /
      1000,
  );
  assert.equal(rejected.response.headers.get("retry-after"), String(expectedRetryAfter));
  assert.equal(upstreamCalls, 180);
});

test("five upstream 429s open the circuit breaker", async (t) => {
  t.mock.method(Date, "now", () => BASE_TIME_MS);
  let upstreamCalls = 0;
  const env = createEnv(() => {
    upstreamCalls += 1;
    return jsonResponse({ error: "Too many requests" }, 429);
  });

  for (let index = 0; index < 5; index += 1) {
    const result = await fetchJson(
      env,
      `/sgdb/grid?steam_app_id=${3000 + index}&dimension=tall`,
    );
    assert.equal(result.response.status, 503);
  }

  const blocked = await fetchJson(env, "/sgdb/grid?steam_app_id=4000&dimension=tall");
  assert.equal(blocked.response.status, 503);
  assert.equal(blocked.response.headers.get("retry-after"), "300");
  assert.equal(upstreamCalls, 5);
});
