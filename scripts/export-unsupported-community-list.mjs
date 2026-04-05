#!/usr/bin/env node

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const DEFAULT_WORKER_URL =
  "https://compact-games-unsupported-report-ingest.pressplay-subai.workers.dev";
const DEFAULT_OUTPUT_DIR = "dist/unsupported-community";
const DEFAULTS = {
  minReporters: "3",
  minRepeatReporters: "1",
  maxAgeDays: "180",
};

async function main() {
  const workerUrl = normalizeWorkerBaseUrl(
    readOption(
      "worker-url",
      process.env.COMPACT_GAMES_UNSUPPORTED_WORKER_URL ??
        process.env.PRESSPLAY_UNSUPPORTED_WORKER_URL,
    ) ??
      DEFAULT_WORKER_URL,
  );
  const outputDir = path.resolve(
    readOption(
      "out-dir",
      process.env.COMPACT_GAMES_UNSUPPORTED_OUTPUT_DIR ??
        process.env.PRESSPLAY_UNSUPPORTED_OUTPUT_DIR,
    ) ??
      DEFAULT_OUTPUT_DIR,
  );
  const bundleUrl = new URL("/release-bundle", workerUrl);
  bundleUrl.searchParams.set(
    "min_reporters",
    readOption(
      "min-reporters",
      process.env.COMPACT_GAMES_UNSUPPORTED_MIN_REPORTERS ??
        process.env.PRESSPLAY_UNSUPPORTED_MIN_REPORTERS,
      DEFAULTS.minReporters,
    ),
  );
  bundleUrl.searchParams.set(
    "min_repeat_reporters",
    readOption(
      "min-repeat-reporters",
      process.env.COMPACT_GAMES_UNSUPPORTED_MIN_REPEAT_REPORTERS ??
        process.env.PRESSPLAY_UNSUPPORTED_MIN_REPEAT_REPORTERS,
      DEFAULTS.minRepeatReporters,
    ),
  );
  bundleUrl.searchParams.set(
    "max_age_days",
    readOption(
      "max-age-days",
      process.env.COMPACT_GAMES_UNSUPPORTED_MAX_AGE_DAYS ??
        process.env.PRESSPLAY_UNSUPPORTED_MAX_AGE_DAYS,
      DEFAULTS.maxAgeDays,
    ),
  );

  const response = await fetch(bundleUrl, {
    headers: {
      accept: "application/json",
      "user-agent": "CompactGames-Unsupported-Export/1",
    },
  });

  if (!response.ok) {
    throw new Error(
      `Export request failed (${response.status} ${response.statusText}) for ${bundleUrl}`,
    );
  }

  const bundle = await response.json();
  if (!bundle || !Array.isArray(bundle.games) || !Array.isArray(bundle.candidates)) {
    throw new Error("Worker response did not include the expected release bundle shape");
  }

  await mkdir(outputDir, { recursive: true });

  const gamesPath = path.join(outputDir, "unsupported_games.json");
  const bundlePath = path.join(outputDir, "unsupported_games.bundle.json");

  await Promise.all([
    writeFile(gamesPath, `${JSON.stringify(bundle.games, null, 2)}\n`, "utf8"),
    writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`, "utf8"),
  ]);

  console.log(`Wrote ${bundle.games.length} unsupported games to ${gamesPath}`);
  console.log(`Wrote review bundle to ${bundlePath}`);
  console.log(
    `Criteria: reporters>=${bundle.criteria?.minReporters ?? "?"}, repeat>=${bundle.criteria?.minRepeatReporters ?? "?"}, maxAgeDays=${bundle.criteria?.maxSubmissionAgeDays ?? "?"}`,
  );
}

function readOption(name, explicitValue, fallback = null) {
  const prefix = `--${name}=`;
  const fromArg = process.argv
    .slice(2)
    .find((argument) => argument.startsWith(prefix));
  if (fromArg) {
    return fromArg.slice(prefix.length);
  }
  return explicitValue ?? fallback;
}

function normalizeWorkerBaseUrl(rawValue) {
  const url = new URL(rawValue);
  if (url.pathname.endsWith("/unsupported-reports")) {
    url.pathname = url.pathname.slice(0, -"/unsupported-reports".length) || "/";
  }
  return url;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
