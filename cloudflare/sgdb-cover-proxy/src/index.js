const AUTH_HEADER = "x-compact-games-token";
const SGDB_BASE_URL = "https://www.steamgriddb.com";
const USER_AGENT = "CompactGamesCoverProxy/1.0";
const SUCCESS_CACHE_TTL_SECONDS = 30 * 24 * 60 * 60;
const NEGATIVE_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const RATE_LIMIT_MAX_MISSES = 60;
const RATE_LIMIT_PRUNE_AGE_MS = 25 * 60 * 60 * 1000;
const CIRCUIT_WINDOW_MS = 5 * 60 * 1000;
const CIRCUIT_MAX_429S = 5;
const CIRCUIT_KEY = "sgdb:v1:circuit:429";
const UPSTREAM_TIMEOUT_MS = 4_000;
const MAX_NAME_LENGTH = 120;

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

const DIMENSION_PREFERENCES = {
  tall: ["342x482", "660x930", "600x900"],
  wide: ["460x215", "920x430"],
  square: ["512x512", "1024x1024"],
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/healthz") {
      return jsonResponse({ ok: true, service: "sgdb-cover-proxy" });
    }

    if (url.pathname.startsWith("/sgdb/")) {
      return handleSgdbRequest(request, env, url);
    }

    return jsonResponse({ error: "Not found" }, 404);
  },
};

async function handleSgdbRequest(request, env, url) {
  if (request.method !== "GET") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const bindingError = validateBindings(env);
  if (bindingError) {
    return jsonResponse({ error: bindingError }, 503);
  }

  const authorized = await isAuthorized(
    request.headers.get(AUTH_HEADER),
    readSecret(env, "COMPACT_GAMES_PROXY_TOKEN"),
  );
  if (!authorized) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const parsed = await parseLookup(url);
  if (parsed.error) {
    return jsonResponse({ error: parsed.error }, 400);
  }

  const [cached, circuit] = await Promise.all([
    readLookupCache(env, parsed.cacheKey),
    readCircuit(env),
  ]);
  if (cached?.kind === "hit") {
    return jsonResponse({ url: cached.url, source: "cache" });
  }
  if (cached?.kind === "miss") {
    return jsonResponse({ error: "Not found", source: "negative_cache" }, 404);
  }

  if (circuit.open) {
    return jsonResponse(
      { error: "SteamGridDB temporarily unavailable" },
      503,
      retryAfterHeaders(circuit.retryAfterSeconds),
    );
  }

  const rateLimit = await consumeRateLimit(request, env);
  if (!rateLimit.allowed) {
    return jsonResponse(
      { error: "Rate limit exceeded. Try again later." },
      429,
      retryAfterHeaders(rateLimit.retryAfterSeconds),
    );
  }

  try {
    const imageUrl =
      parsed.kind === "grid"
        ? await resolveGridBySteamAppId(env, parsed.steamAppId, parsed.dimension)
        : await resolveGridByName(env, parsed.name, parsed.dimension);

    if (!imageUrl) {
      await writeLookupCache(env, parsed.cacheKey, { status: "miss" }, NEGATIVE_CACHE_TTL_SECONDS);
      return jsonResponse({ error: "Not found", source: "steamgriddb" }, 404);
    }

    await writeLookupCache(
      env,
      parsed.cacheKey,
      { status: "hit", url: imageUrl },
      SUCCESS_CACHE_TTL_SECONDS,
    );
    return jsonResponse({ url: imageUrl, source: "steamgriddb" });
  } catch (error) {
    if (error instanceof UpstreamRateLimitedError) {
      const breaker = await recordUpstream429(env);
      return jsonResponse(
        { error: "SteamGridDB temporarily unavailable" },
        503,
        retryAfterHeaders(breaker.retryAfterSeconds),
      );
    }

    return jsonResponse({ error: "SteamGridDB lookup failed" }, 503);
  }
}

function validateBindings(env) {
  if (!env?.CACHE || !env?.DB) {
    return "Proxy storage is not configured";
  }
  if (
    !readSecret(env, "SGDB_API_KEY") ||
    !readSecret(env, "COMPACT_GAMES_PROXY_TOKEN") ||
    !readSecret(env, "IP_HASH_SECRET")
  ) {
    return "Proxy secrets are not configured";
  }
  return null;
}

async function parseLookup(url) {
  const dimension = url.searchParams.get("dimension")?.trim().toLowerCase();
  if (!dimension || !Object.hasOwn(DIMENSION_PREFERENCES, dimension)) {
    return { error: "Invalid dimension" };
  }

  if (url.pathname === "/sgdb/grid") {
    const steamAppId = url.searchParams.get("steam_app_id")?.trim() ?? "";
    if (!/^\d{1,10}$/.test(steamAppId)) {
      return { error: "Invalid steam_app_id" };
    }
    return {
      kind: "grid",
      dimension,
      steamAppId,
      cacheKey: `sgdb:v1:grid:steam:${steamAppId}:${dimension}`,
    };
  }

  if (url.pathname === "/sgdb/by-name") {
    const name = normalizeLookupName(url.searchParams.get("name") ?? "");
    if (!name) {
      return { error: "Invalid name" };
    }
    const digest = await sha256Hex(name.toLowerCase());
    return {
      kind: "name",
      dimension,
      name,
      cacheKey: `sgdb:v1:grid:name:${digest}:${dimension}`,
    };
  }

  return { error: "Not found" };
}

function normalizeLookupName(value) {
  const normalized = value.replace(/\s+/g, " ").trim();
  if (
    normalized.length === 0 ||
    normalized.length > MAX_NAME_LENGTH ||
    /[\u0000-\u001f\u007f]/u.test(normalized)
  ) {
    return "";
  }
  return normalized;
}

async function resolveGridBySteamAppId(env, steamAppId, dimension) {
  return findGridUrlForTarget(env, `/api/v2/grids/steam/${steamAppId}`, dimension);
}

async function resolveGridByName(env, name, dimension) {
  const encodedName = encodeURIComponent(name);
  const searchJson = await steamGridDbGetJson(env, `/api/v2/search/autocomplete/${encodedName}`);
  const data = Array.isArray(searchJson?.data) ? searchJson.data : [];
  if (data.length === 0) {
    return null;
  }

  const normalized = name.toLowerCase();
  let fallbackId = null;
  for (const item of data) {
    const id = readInteger(item?.id);
    if (id == null) {
      continue;
    }
    fallbackId ??= id;
    if (typeof item?.name === "string" && item.name.toLowerCase() === normalized) {
      return findGridUrlForTarget(env, `/api/v2/grids/game/${id}`, dimension);
    }
  }

  return fallbackId == null
    ? null
    : findGridUrlForTarget(env, `/api/v2/grids/game/${fallbackId}`, dimension);
}

async function findGridUrlForTarget(env, endpointBase, dimension) {
  for (const dimensions of DIMENSION_PREFERENCES[dimension]) {
    const json = await steamGridDbGetJson(
      env,
      `${endpointBase}?types=static&dimensions=${encodeURIComponent(dimensions)}`,
    );
    const selected = selectSteamGridUrl(json);
    if (selected) {
      return selected;
    }
  }
  return null;
}

async function steamGridDbGetJson(env, endpoint) {
  const response = await upstreamFetch(env, `${SGDB_BASE_URL}${endpoint}`);
  if (response.status === 429) {
    throw new UpstreamRateLimitedError(response.status);
  }
  if (response.status === 401 || response.status === 403 || response.status >= 500) {
    throw new UpstreamUnavailableError(response.status);
  }
  if (response.status === 404 || response.status !== 200 || !response.body) {
    return null;
  }

  let decoded;
  try {
    decoded = await response.json();
  } catch {
    throw new UpstreamUnavailableError("invalid_json");
  }
  return typeof decoded === "object" && decoded != null ? decoded : null;
}

async function upstreamFetch(env, url) {
  const fetcher = env.SGDB_FETCH ?? fetch;
  const apiKey = readSecret(env, "SGDB_API_KEY");
  const signal =
    typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function"
      ? AbortSignal.timeout(UPSTREAM_TIMEOUT_MS)
      : undefined;
  return fetcher(url, {
    method: "GET",
    signal,
    headers: {
      authorization: `Bearer ${apiKey}`,
      accept: "application/json",
      "user-agent": USER_AGENT,
    },
  });
}

function readSecret(env, name) {
  const value = env?.[name];
  return typeof value === "string" ? value.trim() : "";
}

function selectSteamGridUrl(json) {
  const data = Array.isArray(json?.data) ? json.data : [];
  let fallbackUrl = null;
  let fallbackArea = -1;
  let preferredUrl = null;
  let preferredArea = -1;

  for (const item of data) {
    const url = typeof item?.url === "string" ? item.url : "";
    if (!url || !isSteamGridImageUrl(url)) {
      continue;
    }

    const width = readInteger(item?.width) ?? 0;
    const height = readInteger(item?.height) ?? 0;
    const area = width > 0 && height > 0 ? width * height : 0;
    if (area > fallbackArea) {
      fallbackUrl = url;
      fallbackArea = area;
    }
    if (width <= 0 || height <= 0) {
      continue;
    }
    const aspect = width / height;
    if (aspect >= 0.5 && aspect <= 2.5 && area > preferredArea) {
      preferredUrl = url;
      preferredArea = area;
    }
  }

  return preferredUrl ?? fallbackUrl;
}

function isSteamGridImageUrl(value) {
  let uri;
  try {
    uri = new URL(value);
  } catch {
    return false;
  }

  const host = uri.hostname.toLowerCase();
  return uri.protocol === "https:" && (host === "steamgriddb.com" || host.endsWith(".steamgriddb.com"));
}

async function readLookupCache(env, cacheKey) {
  const raw = await env.CACHE.get(cacheKey);
  if (!raw) {
    return null;
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }

  if (parsed?.status === "hit" && typeof parsed.url === "string") {
    return { kind: "hit", url: parsed.url };
  }
  if (parsed?.status === "miss") {
    return { kind: "miss" };
  }
  return null;
}

async function writeLookupCache(env, cacheKey, value, ttlSeconds) {
  await env.CACHE.put(cacheKey, JSON.stringify(value), {
    expirationTtl: ttlSeconds,
  });
}

async function consumeRateLimit(request, env) {
  const clientIp = resolveClientIp(request);
  if (!clientIp) {
    return { allowed: true };
  }

  const now = Date.now();
  const windowStartMs = Math.floor(now / RATE_LIMIT_WINDOW_MS) * RATE_LIMIT_WINDOW_MS;
  const retryAfterSeconds = Math.max(1, Math.ceil((windowStartMs + RATE_LIMIT_WINDOW_MS - now) / 1000));
  const ipHash = await hmacSha256Hex(readSecret(env, "IP_HASH_SECRET"), clientIp);
  const row = await env.DB.prepare(
    `INSERT INTO ip_rate_limits (ip_hash, window_start_ms, count, updated_at_ms)
     VALUES (?, ?, 1, ?)
     ON CONFLICT(ip_hash, window_start_ms) DO UPDATE SET
       count = ip_rate_limits.count + 1,
       updated_at_ms = excluded.updated_at_ms
     RETURNING count AS count`,
  )
    .bind(ipHash, windowStartMs, now)
    .first();
  const current = readInteger(row?.count) ?? RATE_LIMIT_MAX_MISSES + 1;
  if (current > RATE_LIMIT_MAX_MISSES) {
    return { allowed: false, retryAfterSeconds };
  }

  // Prune only on the first request of a new window to avoid one DELETE per lookup.
  if (current === 1) {
    try {
      await env.DB.prepare("DELETE FROM ip_rate_limits WHERE updated_at_ms < ?")
        .bind(now - RATE_LIMIT_PRUNE_AGE_MS)
        .run();
    } catch {
      // Best-effort pruning should never block lookups.
    }
  }

  return { allowed: true };
}

function resolveClientIp(request) {
  const cfIp = request.headers.get("cf-connecting-ip")?.trim();
  if (cfIp) {
    return cfIp;
  }
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || "";
}

async function readCircuit(env) {
  const raw = await env.CACHE.get(CIRCUIT_KEY);
  if (!raw) {
    return { open: false };
  }

  let state;
  try {
    state = JSON.parse(raw);
  } catch {
    return { open: false };
  }

  const now = Date.now();
  const openUntilMs = readInteger(state?.openUntilMs) ?? 0;
  if (openUntilMs <= now) {
    return { open: false };
  }

  return {
    open: true,
    retryAfterSeconds: Math.max(1, Math.ceil((openUntilMs - now) / 1000)),
  };
}

async function recordUpstream429(env) {
  const now = Date.now();
  const raw = await env.CACHE.get(CIRCUIT_KEY);
  let state = null;
  try {
    state = raw ? JSON.parse(raw) : null;
  } catch {
    state = null;
  }

  const windowStartMs =
    state && now - (readInteger(state.windowStartMs) ?? 0) < CIRCUIT_WINDOW_MS
      ? readInteger(state.windowStartMs)
      : now;
  const count = windowStartMs === readInteger(state?.windowStartMs)
    ? (readInteger(state?.count) ?? 0) + 1
    : 1;
  const openUntilMs = count >= CIRCUIT_MAX_429S ? now + CIRCUIT_WINDOW_MS : 0;

  await env.CACHE.put(
    CIRCUIT_KEY,
    JSON.stringify({ windowStartMs, count, openUntilMs }),
    { expirationTtl: Math.ceil(CIRCUIT_WINDOW_MS / 1000) },
  );

  return {
    retryAfterSeconds: openUntilMs > now
      ? Math.ceil((openUntilMs - now) / 1000)
      : 60,
  };
}

async function isAuthorized(candidate, expected) {
  if (!candidate || !expected) {
    return false;
  }
  const [candidateHash, expectedHash] = await Promise.all([
    sha256Bytes(candidate),
    sha256Bytes(expected),
  ]);
  let diff = candidate.length ^ expected.length;
  for (let index = 0; index < candidateHash.length; index += 1) {
    diff |= candidateHash[index] ^ expectedHash[index];
  }
  return diff === 0;
}

async function sha256Hex(value) {
  return bytesToHex(await sha256Bytes(value));
}

async function sha256Bytes(value) {
  const input = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", input);
  return new Uint8Array(digest);
}

async function hmacSha256Hex(secret, value) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(signature));
}

function bytesToHex(bytes) {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function readInteger(value) {
  if (Number.isInteger(value)) {
    return value;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && /^-?\d+$/.test(value)) {
    return Number.parseInt(value, 10);
  }
  return null;
}

function jsonResponse(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...headers },
  });
}

function retryAfterHeaders(seconds) {
  return { "retry-after": String(Math.max(1, seconds ?? 1)) };
}

class UpstreamRateLimitedError extends Error {
  constructor(status) {
    super("SteamGridDB rate limited");
    this.status = status;
  }
}

class UpstreamUnavailableError extends Error {
  constructor(status) {
    super("SteamGridDB unavailable");
    this.status = status;
  }
}
