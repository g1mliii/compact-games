#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const DEFAULT_INPUT = "compactgui-database/database.json";
const DEFAULT_OUTPUT_DIR = "dist/compression-db";
const DEFAULT_MIN_SAMPLES = 3;
const SCHEMA_VERSION = 1;

const COMP_TYPE_TO_KEY = new Map([
  [0, "xpress4k"],
  [1, "xpress8k"],
  [2, "xpress16k"],
  [3, "lzx"],
]);

async function main() {
  const inputPath = path.resolve(
    readOption("input", process.env.COMPACT_GAMES_COMPRESSION_DB_INPUT) ??
      DEFAULT_INPUT,
  );
  const outputDir = path.resolve(
    readOption("out-dir", process.env.COMPACT_GAMES_COMPRESSION_DB_OUTPUT_DIR) ??
      DEFAULT_OUTPUT_DIR,
  );
  const minSamples = parsePositiveInteger(
    readOption("min-samples", process.env.COMPACT_GAMES_COMPRESSION_DB_MIN_SAMPLES),
    DEFAULT_MIN_SAMPLES,
  );
  const source = readOption("source", process.env.COMPACTGUI_SOURCE_REF) ??
    "IridiumIO/CompactGUI@database";

  const raw = await readFile(inputPath, "utf8");
  const upstream = JSON.parse(raw);
  if (!Array.isArray(upstream)) {
    throw new Error("CompactGUI database must be a JSON array");
  }

  const entries = {};
  const aliasCandidates = new Map();
  let included = 0;
  let skipped = 0;

  for (const item of upstream) {
    const entry = normalizeEntry(item, minSamples);
    if (!entry) {
      skipped += 1;
      continue;
    }

    entries[entry.key] = entry.value;
    included += 1;

    collectAlias(aliasCandidates, `name:${normalizeKey(entry.value.name)}`, entry.key);
    if (entry.value.folder_name) {
      collectAlias(
        aliasCandidates,
        `folder:${normalizeKey(entry.value.folder_name)}`,
        entry.key,
      );
    }
  }

  const aliases = {};
  for (const [alias, targets] of [...aliasCandidates.entries()].sort()) {
    if (targets.size === 1 && !entries[alias]) {
      aliases[alias] = [...targets][0];
    }
  }

  const payload = {
    version: SCHEMA_VERSION,
    generated_at: new Date().toISOString(),
    source,
    min_samples: minSamples,
    entries: sortObject(entries),
    aliases: sortObject(aliases),
  };

  await mkdir(outputDir, { recursive: true });
  const json = `${JSON.stringify(payload, null, 2)}\n`;
  const sha256 = createHash("sha256").update(json).digest("hex");
  const bundle = {
    version: SCHEMA_VERSION,
    generated_at: payload.generated_at,
    source,
    asset: "compression_db.v1.json",
    sha256,
    entries: included,
    skipped,
    aliases: Object.keys(aliases).length,
    license: "GPL-3.0",
    attribution: "CompactGUI by IridiumIO",
  };

  const dbPath = path.join(outputDir, "compression_db.v1.json");
  const bundlePath = path.join(outputDir, "compression_db.v1.bundle.json");
  await Promise.all([
    writeFile(dbPath, json, "utf8"),
    writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`, "utf8"),
  ]);

  console.log(`Wrote ${included} compression entries to ${dbPath}`);
  console.log(`Wrote ${Object.keys(aliases).length} aliases to ${dbPath}`);
  console.log(`Wrote bundle metadata to ${bundlePath}`);
  console.log(`Skipped ${skipped} entries below min_samples=${minSamples}`);
}

function normalizeEntry(item, minSamples) {
  const steamId = Number(item?.SteamID);
  if (!Number.isSafeInteger(steamId) || steamId <= 0) return null;

  const ratios = {};
  const ratioSamples = {};
  let totalSamples = 0;

  for (const result of item.CompressionResults ?? []) {
    const compType = Number(result?.CompType);
    const key = COMP_TYPE_TO_KEY.get(compType);
    if (!key) continue;

    const beforeBytes = Number(result?.BeforeBytes);
    const afterBytes = Number(result?.AfterBytes);
    const samples = Number(result?.TotalResults);
    if (
      !Number.isFinite(beforeBytes) ||
      !Number.isFinite(afterBytes) ||
      !Number.isSafeInteger(samples) ||
      beforeBytes <= 0 ||
      afterBytes < 0 ||
      samples < minSamples
    ) {
      continue;
    }

    const savedRatio = clamp(1 - afterBytes / beforeBytes, 0, 0.95);
    ratios[key] = Number(savedRatio.toFixed(6));
    ratioSamples[key] = samples;
    totalSamples += samples;
  }

  if (Object.keys(ratios).length === 0) return null;

  const name = normalizeDisplayText(item.GameName);
  if (!name) return null;

  return {
    key: `steam:${steamId}`,
    value: {
      name,
      folder_name: normalizeDisplayText(item.FolderName),
      samples: totalSamples,
      ratios: sortObject(ratios),
      ratio_samples: sortObject(ratioSamples),
    },
  };
}

function collectAlias(aliasCandidates, alias, target) {
  if (!alias || alias.endsWith(":")) return;
  const targets = aliasCandidates.get(alias) ?? new Set();
  targets.add(target);
  aliasCandidates.set(alias, targets);
}

function normalizeDisplayText(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeKey(value) {
  if (typeof value !== "string") return "";
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function sortObject(value) {
  return Object.fromEntries(Object.entries(value).sort(([left], [right]) => left.localeCompare(right)));
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function parsePositiveInteger(raw, fallback) {
  if (raw == null || raw === "") return fallback;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`Expected a positive integer, got ${raw}`);
  }
  return parsed;
}

function readOption(name, explicitValue) {
  const prefix = `--${name}=`;
  const fromArg = process.argv
    .slice(2)
    .find((argument) => argument.startsWith(prefix));
  if (fromArg) {
    return fromArg.slice(prefix.length);
  }
  return explicitValue ?? null;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
