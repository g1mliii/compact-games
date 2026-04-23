import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

import worker from "../src/index.js";
import { FakeD1Database } from "./support/fake-d1.mjs";

const BASE_TIME_MS = 1_740_000_000_000;
const REPORTER_TOKEN_HEADER = "x-compactgames-reporter-token";

function createEnv() {
  return { DB: new FakeD1Database() };
}

function createPayload(overrides = {}) {
  const base = {
    install_id: "legacy-install-1",
    app_version: "1.2.3",
    generated_at_ms: BASE_TIME_MS,
    reports: [
      {
        folder_name: "Example Game",
        first_reported_at_ms: BASE_TIME_MS - 20_000,
        active_since_ms: BASE_TIME_MS - 10_000,
        last_reported_at_ms: BASE_TIME_MS - 5_000,
        last_withdrawn_at_ms: null,
        report_count: 2,
      },
    ],
  };

  return {
    ...base,
    ...overrides,
    reports: overrides.reports ?? base.reports,
  };
}

async function fetchJson(env, path, init = {}) {
  const request = new Request(`https://example.test${path}`, init);
  const response = await worker.fetch(request, env);
  const bodyText = await response.text();

  return {
    response,
    json: bodyText ? JSON.parse(bodyText) : null,
  };
}

function createJsonRequest(payload, headers = {}) {
  return {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(payload),
  };
}

function seedCurrentSnapshot(env, row) {
  env.DB.seedClientSubmission({
    install_id: row.install_id,
    app_version: row.app_version ?? "1.0.0",
    generated_at_ms: row.generated_at_ms ?? BASE_TIME_MS - 1_000,
    submitted_at_ms: row.submitted_at_ms ?? BASE_TIME_MS - 1_000,
    report_count: row.report_count ?? 1,
  });

  if (row.folder_name) {
    env.DB.seedClientReport({
      install_id: row.install_id,
      folder_name: row.folder_name,
      app_version: row.app_version ?? "1.0.0",
      first_reported_at_ms: row.first_reported_at_ms ?? BASE_TIME_MS - 20_000,
      active_since_ms: row.active_since_ms ?? BASE_TIME_MS - 10_000,
      last_reported_at_ms: row.last_reported_at_ms ?? BASE_TIME_MS - 5_000,
      last_withdrawn_at_ms: row.last_withdrawn_at_ms ?? null,
      report_count: row.report_count ?? 1,
      payload_generated_at_ms: row.payload_generated_at_ms ?? BASE_TIME_MS - 2_000,
      submitted_at_ms: row.submitted_at_ms ?? BASE_TIME_MS - 1_000,
    });
    env.DB.seedClientReportHistory({
      install_id: row.install_id,
      folder_name: row.folder_name,
      first_server_seen_at_ms: row.first_server_seen_at_ms ?? BASE_TIME_MS - 50_000,
      last_server_seen_at_ms: row.last_server_seen_at_ms ?? BASE_TIME_MS - 1_000,
      server_submission_count: row.server_submission_count ?? 1,
    });
  }
}

test("router handles health, options, and not-found responses", async () => {
  const env = createEnv();

  const health = await fetchJson(env, "/health");
  assert.equal(health.response.status, 200);
  assert.deepEqual(health.json, {
    ok: true,
    service: "unsupported-report-ingest",
  });
  assert.equal(health.response.headers.get("access-control-allow-origin"), "*");

  const options = await worker.fetch(
    new Request("https://example.test/unsupported-reports", { method: "OPTIONS" }),
    env,
  );
  assert.equal(options.status, 204);
  assert.equal(
    options.headers.get("access-control-allow-headers"),
    "content-type,x-compactgames-reporter-token",
  );

  const notFound = await fetchJson(env, "/missing");
  assert.equal(notFound.response.status, 404);
  assert.deepEqual(notFound.json, { error: "Not found" });
});

test("submission validation rejects non-json and malformed payloads", async () => {
  const env = createEnv();

  const nonJson = await fetchJson(env, "/unsupported-reports", {
    method: "POST",
    headers: { "content-type": "text/plain" },
    body: "nope",
  });
  assert.equal(nonJson.response.status, 415);
  assert.equal(nonJson.response.headers.get("access-control-allow-origin"), "*");
  assert.deepEqual(nonJson.json, { error: "Expected application/json body" });

  const invalid = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest({ app_version: "", generated_at_ms: -1, reports: [] }),
  );
  assert.equal(invalid.response.status, 400);
  assert.equal(invalid.json.error, "Missing or invalid app_version");

  const invalidWithdrawnAt = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(
      createPayload({
        reports: [
          {
            folder_name: "Example Game",
            first_reported_at_ms: BASE_TIME_MS - 20_000,
            active_since_ms: BASE_TIME_MS - 10_000,
            last_reported_at_ms: BASE_TIME_MS - 5_000,
            last_withdrawn_at_ms: "bad-timestamp",
            report_count: 2,
          },
        ],
      }),
    ),
  );
  assert.equal(invalidWithdrawnAt.response.status, 400);
  assert.equal(
    invalidWithdrawnAt.json.error,
    "Invalid report timestamp/count fields",
  );
});

test("submission accepts a valid payload and canonicalizes current reports", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);

  const payload = createPayload({
    reports: [
      {
        folder_name: "EXAMPLE GAME",
        first_reported_at_ms: BASE_TIME_MS - 20_000,
        active_since_ms: BASE_TIME_MS - 10_000,
        last_reported_at_ms: BASE_TIME_MS - 5_000,
        last_withdrawn_at_ms: null,
        report_count: 2,
      },
      {
        folder_name: "example game",
        first_reported_at_ms: BASE_TIME_MS - 19_000,
        active_since_ms: BASE_TIME_MS - 9_000,
        last_reported_at_ms: BASE_TIME_MS - 4_000,
        last_withdrawn_at_ms: null,
        report_count: 3,
      },
    ],
  });

  const result = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(payload),
  );

  assert.equal(result.response.status, 200);
  assert.equal(result.response.headers.get("access-control-allow-origin"), "*");
  assert.equal(result.json.reporterId, "legacy-install-1");
  assert.equal(result.json.acceptedReports, 1);
  assert.equal(env.DB.clientSubmissions.get("legacy-install-1").report_count, 1);
  assert(env.DB.clientReports.has("legacy-install-1\u0000example game"));
});

test("legacy install_id cannot hijack an existing reporter identity", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);
  t.mock.method(globalThis.crypto, "randomUUID", () => "11111111-2222-3333-4444-555555555555");

  seedCurrentSnapshot(env, {
    install_id: "victim-id",
    folder_name: "victim-game",
    server_submission_count: 2,
  });

  const result = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(
      createPayload({
        install_id: "victim-id",
        reports: [
          {
            folder_name: "attacker-game",
            first_reported_at_ms: BASE_TIME_MS - 20_000,
            active_since_ms: BASE_TIME_MS - 10_000,
            last_reported_at_ms: BASE_TIME_MS - 5_000,
            last_withdrawn_at_ms: null,
            report_count: 1,
          },
        ],
      }),
    ),
  );

  assert.equal(result.response.status, 200);
  assert.notEqual(result.json.reporterId, "victim-id");
  assert.match(result.json.reporterId, /^ppr-/);
  assert(env.DB.clientSubmissions.has("victim-id"));
  assert(env.DB.clientSubmissions.has(result.json.reporterId));
  assert(env.DB.clientReports.has(`${result.json.reporterId}\u0000attacker-game`));
  assert(env.DB.clientReports.has("victim-id\u0000victim-game"));
});

test("existing reporter header token reuses the current reporter identity", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);

  seedCurrentSnapshot(env, {
    install_id: "ppr-existing-token",
    folder_name: "before",
  });

  const result = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(createPayload({ install_id: "spoofed-legacy" }), {
      [REPORTER_TOKEN_HEADER]: "ppr-existing-token",
    }),
  );

  assert.equal(result.response.status, 200);
  assert.equal(result.json.reporterId, "ppr-existing-token");
  assert(env.DB.clientReports.has("ppr-existing-token\u0000example game"));
});

test("rolling submission history enforces the per-reporter rate limit", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);

  seedCurrentSnapshot(env, {
    install_id: "ppr-rate-limited",
    folder_name: "existing",
  });

  for (let index = 0; index < 5; index += 1) {
    env.DB.seedClientSubmissionHistory({
      install_id: "ppr-rate-limited",
      submitted_at_ms: BASE_TIME_MS - index * 5_000,
      report_count: 1,
    });
  }

  const beforeCount = env.DB.clientSubmissionHistory.length;
  const result = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(createPayload({ install_id: "ignored-legacy" }), {
      [REPORTER_TOKEN_HEADER]: "ppr-rate-limited",
    }),
  );

  assert.equal(result.response.status, 429);
  assert.deepEqual(result.json, {
    error: "Rate limit exceeded. Try again later.",
  });
  assert.equal(env.DB.clientSubmissionHistory.length, beforeCount);
});

test("per-ip submission rate limiting blocks excessive POST volume even when reporter IDs rotate", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);

  const ip = "203.0.113.9";
  for (let index = 0; index < 15; index += 1) {
    env.DB.seedIpSubmissionHistory({
      ip,
      install_id: `ppr-spam-${index}`,
      is_new_reporter: 1,
      submitted_at_ms: BASE_TIME_MS - index * 2_000,
      report_count: 1,
    });
  }

  const result = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(createPayload({ install_id: "new-legacy" }), {
      "CF-Connecting-IP": ip,
    }),
  );

  assert.equal(result.response.status, 429);
  assert.deepEqual(result.json, {
    error: "Rate limit exceeded. Try again later.",
  });
});

test("per-ip new reporter limiting blocks mass registration of reporter IDs", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);

  const ip = "198.51.100.77";
  for (let index = 0; index < 10; index += 1) {
    env.DB.seedIpSubmissionHistory({
      ip,
      install_id: `ppr-new-${index}`,
      is_new_reporter: 1,
      submitted_at_ms: BASE_TIME_MS - 5 * 60 * 1000 - index * 1000,
      report_count: 1,
    });
  }

  const result = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(createPayload({ install_id: "fresh-legacy" }), {
      "CF-Connecting-IP": ip,
    }),
  );

  assert.equal(result.response.status, 429);
  assert.deepEqual(result.json, {
    error: "Rate limit exceeded. Try again later.",
  });
});

test("expired submission history is pruned and does not block a new submission", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);

  seedCurrentSnapshot(env, {
    install_id: "ppr-prune-history",
    folder_name: "older-game",
  });
  env.DB.seedClientSubmissionHistory({
    install_id: "ppr-prune-history",
    submitted_at_ms: BASE_TIME_MS - 120_000,
    report_count: 1,
  });

  const result = await fetchJson(
    env,
    "/unsupported-reports",
    createJsonRequest(createPayload({ install_id: "ignored-legacy" }), {
      [REPORTER_TOKEN_HEADER]: "ppr-prune-history",
    }),
  );

  assert.equal(result.response.status, 200);
  assert.equal(
    env.DB.clientSubmissionHistory.filter(
      (row) => row.install_id === "ppr-prune-history",
    ).length,
    1,
  );
  assert.equal(
    env.DB.clientSubmissionHistory[0].submitted_at_ms,
    BASE_TIME_MS,
  );
});

test("community endpoints expose thresholded candidates, list, and release bundle", async (t) => {
  const env = createEnv();
  t.mock.method(Date, "now", () => BASE_TIME_MS);

  seedCurrentSnapshot(env, {
    install_id: "reporter-a",
    folder_name: "shared-game",
    server_submission_count: 2,
    submitted_at_ms: BASE_TIME_MS - 1_000,
  });
  seedCurrentSnapshot(env, {
    install_id: "reporter-b",
    folder_name: "shared-game",
    server_submission_count: 1,
    submitted_at_ms: BASE_TIME_MS - 2_000,
  });
  seedCurrentSnapshot(env, {
    install_id: "reporter-c",
    folder_name: "single-game",
    server_submission_count: 3,
    submitted_at_ms: BASE_TIME_MS - 3_000,
  });
  seedCurrentSnapshot(env, {
    install_id: "reporter-old",
    folder_name: "stale-game",
    server_submission_count: 4,
    submitted_at_ms: BASE_TIME_MS - 400 * 24 * 60 * 60 * 1000,
  });

  const candidates = await fetchJson(
    env,
    "/community-candidates?threshold=2&min_repeat_reporters=1&max_age_days=180",
  );
  assert.equal(candidates.response.status, 200);
  assert.equal(candidates.json.summary.candidateCount, 1);
  assert.deepEqual(candidates.json.candidates, [
    {
      folderName: "shared-game",
      reporterCount: 2,
      repeatReporterCount: 1,
      totalServerSubmissionCount: 3,
      firstServerSeenAtMs: BASE_TIME_MS - 50_000,
      lastServerSeenAtMs: BASE_TIME_MS - 1_000,
      lastCurrentSubmissionAtMs: BASE_TIME_MS - 1_000,
    },
  ]);

  const communityList = await fetchJson(
    env,
    "/community-list?min_reporters=2&min_repeat_reporters=1&max_age_days=180",
  );
  assert.equal(communityList.response.status, 200);
  assert.deepEqual(communityList.json, ["shared-game"]);

  const releaseBundle = await fetchJson(
    env,
    "/release-bundle?min_reporters=2&min_repeat_reporters=1&max_age_days=180",
  );
  assert.equal(releaseBundle.response.status, 200);
  assert.deepEqual(releaseBundle.json.games, ["shared-game"]);
  assert.deepEqual(releaseBundle.json.storage.tables, [
    "client_submissions",
    "client_reports",
    "client_report_history",
    "client_submission_history",
  ]);
});

test("schema keeps the submission history table and indexes required by rate limiting", async () => {
  const schema = await readFile(
    new URL("../schema.sql", import.meta.url),
    "utf8",
  );

  assert.match(schema, /CREATE TABLE IF NOT EXISTS client_submission_history/i);
  assert.match(
    schema,
    /CREATE INDEX IF NOT EXISTS idx_client_submission_history_install_submitted_at/i,
  );
  assert.match(
    schema,
    /CREATE INDEX IF NOT EXISTS idx_client_submission_history_submitted_at/i,
  );

  assert.match(schema, /CREATE TABLE IF NOT EXISTS ip_submission_history/i);
  assert.match(
    schema,
    /CREATE INDEX IF NOT EXISTS idx_ip_submission_history_ip_submitted_at/i,
  );
  assert.match(
    schema,
    /CREATE INDEX IF NOT EXISTS idx_ip_submission_history_submitted_at/i,
  );
});
