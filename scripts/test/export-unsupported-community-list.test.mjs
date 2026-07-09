import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { once } from "node:events";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { test } from "node:test";

const scriptsDirectory = path.dirname(fileURLToPath(import.meta.url));
const exporterPath = path.join(
  scriptsDirectory,
  "..",
  "export-unsupported-community-list.mjs",
);

function runExporter(args, envOverrides = {}) {
  const environment = { ...process.env, ...envOverrides };
  delete environment.COMPACT_GAMES_UNSUPPORTED_MIN_REPORTERS;
  delete environment.COMPACT_GAMES_UNSUPPORTED_MIN_REPEAT_REPORTERS;
  delete environment.COMPACT_GAMES_UNSUPPORTED_MAX_AGE_DAYS;
  delete environment.PRESSPLAY_UNSUPPORTED_MIN_REPORTERS;
  delete environment.PRESSPLAY_UNSUPPORTED_MIN_REPEAT_REPORTERS;
  delete environment.PRESSPLAY_UNSUPPORTED_MAX_AGE_DAYS;

  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [exporterPath, ...args], {
      env: environment,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.once("error", reject);
    child.once("close", (code) => resolve({ code, stdout, stderr }));
  });
}

async function startWorker(handler) {
  const server = createServer(handler);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())),
  };
}

test("exporter uses safe defaults and signs the exact emitted asset bytes", async () => {
  let requestUrl;
  const worker = await startWorker((request, response) => {
    requestUrl = new URL(request.url, "http://worker.test");
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({
      games: ["safe-game"],
      candidates: [],
      criteria: {
        minReporters: 3,
        minRepeatReporters: 1,
        maxSubmissionAgeDays: 180,
      },
    }));
  });
  const outputDir = await mkdtemp(path.join(tmpdir(), "compact-games-unsupported-"));

  try {
    const result = await runExporter([
      `--worker-url=${worker.baseUrl}`,
      `--out-dir=${outputDir}`,
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(requestUrl.pathname, "/release-bundle");
    assert.equal(requestUrl.searchParams.get("min_reporters"), "3");
    assert.equal(requestUrl.searchParams.get("min_repeat_reporters"), "1");
    assert.equal(requestUrl.searchParams.get("max_age_days"), "180");

    const asset = await readFile(path.join(outputDir, "unsupported_games.json"));
    const bundle = JSON.parse(
      await readFile(path.join(outputDir, "unsupported_games.bundle.json"), "utf8"),
    );
    assert.equal(bundle.version, 1);
    assert.equal(bundle.asset, "unsupported_games.json");
    assert.equal(
      bundle.sha256,
      createHash("sha256").update(asset).digest("hex"),
    );
  } finally {
    await worker.close();
    await rm(outputDir, { recursive: true, force: true });
  }
});

test("exporter rejects a release threshold below three before fetching", async () => {
  let requestCount = 0;
  const worker = await startWorker((_request, response) => {
    requestCount += 1;
    response.writeHead(200, { "content-type": "application/json" });
    response.end("{}");
  });
  const outputDir = await mkdtemp(path.join(tmpdir(), "compact-games-unsupported-"));

  try {
    const result = await runExporter([
      `--worker-url=${worker.baseUrl}`,
      `--out-dir=${outputDir}`,
      "--min-reporters=2",
    ]);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /min-reporters must be at least 3/);
    assert.equal(requestCount, 0);
  } finally {
    await worker.close();
    await rm(outputDir, { recursive: true, force: true });
  }
});
