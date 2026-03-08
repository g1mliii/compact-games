const DEFAULT_MIN_REPORTERS = 3;
const DEFAULT_MIN_REPEAT_REPORTERS = 1;
const DEFAULT_MAX_SUBMISSION_AGE_DAYS = 180;
const MAX_THRESHOLD = 100;
const MAX_SUBMISSION_AGE_DAYS = 3650;
const MAX_REPORTS_PER_REQUEST = 512;
const MAX_FOLDER_NAME_LENGTH = 160;
const MAX_REPORTER_ID_LENGTH = 64;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_MAX_SUBMISSIONS = 5;
const REPORTER_TOKEN_HEADER = "x-pressplay-reporter-token";
const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": `content-type,${REPORTER_TOKEN_HEADER}`,
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: JSON_HEADERS });
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "unsupported-report-ingest" });
    }

    if (request.method === "POST" && url.pathname === "/unsupported-reports") {
      return handleSubmission(request, env);
    }

    if (request.method === "GET" && url.pathname === "/community-candidates") {
      return handleCandidates(request, env);
    }

    if (request.method === "GET" && url.pathname === "/community-list") {
      return handleCommunityList(request, env);
    }

    if (request.method === "GET" && url.pathname === "/release-bundle") {
      return handleReleaseBundle(request, env);
    }

    return json({ error: "Not found" }, 404);
  },
};

async function handleSubmission(request, env) {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return json({ error: "Expected application/json body" }, 415);
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const validated = validatePayload(payload);
  if (validated.error) {
    return json({ error: validated.error }, 400);
  }

  const submittedAtMs = Date.now();
  const rateLimitWindowStartMs = submittedAtMs - RATE_LIMIT_WINDOW_MS;
  const installId = await resolveReporterId(
    env,
    request.headers.get(REPORTER_TOKEN_HEADER),
    validated.legacyInstallId,
  );

  // Per-reporter rate limiting: reject after too many accepted submissions
  // in the recent window. This uses server-side submission history rather than
  // the current snapshot table, which only stores one row per reporter.
  const recentSubmissionCount = await env.DB
    .prepare(
      `SELECT COUNT(*) AS cnt
       FROM client_submission_history
       WHERE install_id = ? AND submitted_at_ms >= ?`,
    )
    .bind(installId, rateLimitWindowStartMs)
    .first();
  if (readInteger(recentSubmissionCount?.cnt) >= RATE_LIMIT_MAX_SUBMISSIONS) {
    return json({ error: "Rate limit exceeded. Try again later." }, 429);
  }
  const statements = [
    env.DB.prepare("DELETE FROM client_reports WHERE install_id = ?").bind(installId),
  ];

  for (const report of validated.reports) {
    statements.push(
      env.DB
        .prepare(
          `INSERT INTO client_report_history (
            install_id,
            folder_name,
            first_server_seen_at_ms,
            last_server_seen_at_ms,
            server_submission_count
          ) VALUES (?, ?, ?, ?, 1)
          ON CONFLICT(install_id, folder_name) DO UPDATE SET
            last_server_seen_at_ms = excluded.last_server_seen_at_ms,
            server_submission_count = client_report_history.server_submission_count + 1`,
        )
        .bind(
          installId,
          report.folderName,
          submittedAtMs,
          submittedAtMs,
        ),
    );

    statements.push(
      env.DB
        .prepare(
          `INSERT INTO client_reports (
            install_id,
            folder_name,
            app_version,
            first_reported_at_ms,
            active_since_ms,
            last_reported_at_ms,
            last_withdrawn_at_ms,
            report_count,
            payload_generated_at_ms,
            submitted_at_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          installId,
          report.folderName,
          validated.appVersion,
          report.firstReportedAtMs,
          report.activeSinceMs,
          report.lastReportedAtMs,
          report.lastWithdrawnAtMs,
          report.reportCount,
          validated.generatedAtMs,
          submittedAtMs,
        ),
    );
  }

  statements.push(
    env.DB
      .prepare(
        `INSERT INTO client_submissions (
          install_id,
          app_version,
          generated_at_ms,
          submitted_at_ms,
          report_count
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(install_id) DO UPDATE SET
          app_version = excluded.app_version,
          generated_at_ms = excluded.generated_at_ms,
          submitted_at_ms = excluded.submitted_at_ms,
          report_count = excluded.report_count`,
      )
      .bind(
        installId,
        validated.appVersion,
        validated.generatedAtMs,
        submittedAtMs,
        validated.reports.length,
      ),
  );

  statements.push(
    env.DB
      .prepare(
        `DELETE FROM client_submission_history
         WHERE install_id = ? AND submitted_at_ms < ?`,
      )
      .bind(installId, rateLimitWindowStartMs),
  );

  statements.push(
    env.DB
      .prepare(
        `INSERT INTO client_submission_history (
          install_id,
          submitted_at_ms,
          report_count
        ) VALUES (?, ?, ?)`,
      )
      .bind(installId, submittedAtMs, validated.reports.length),
  );

  await env.DB.batch(statements);

  return json({
    ok: true,
    acceptedReports: validated.reports.length,
    reporterId: installId,
    submittedAtMs,
  });
}

async function handleCandidates(request, env) {
  const criteria = buildCriteria(new URL(request.url).searchParams);
  const [candidates, storageSummary] = await Promise.all([
    queryCommunityCandidates(env, criteria),
    queryStorageSummary(env, criteria),
  ]);
  return json({
    generatedAtMs: Date.now(),
    criteria: describeCriteria(criteria),
    storage: {
      provider: "cloudflare-d1",
      tables: [
        "client_submissions",
        "client_reports",
        "client_report_history",
        "client_submission_history",
      ],
    },
    summary: {
      candidateCount: candidates.length,
      activeInstallCount: storageSummary.activeInstalls,
      installsWithReportsCount: storageSummary.installsWithReports,
      uniqueReporterCount: storageSummary.uniqueReporters,
    },
    candidates,
  });
}

async function handleCommunityList(request, env) {
  const criteria = buildCriteria(new URL(request.url).searchParams);
  const candidates = await queryCommunityCandidates(env, criteria);
  return json(candidates.map((candidate) => candidate.folderName));
}

async function handleReleaseBundle(request, env) {
  const criteria = buildCriteria(new URL(request.url).searchParams);
  return json(await buildReleaseBundle(env, criteria));
}

async function queryCommunityCandidates(env, criteria) {
  const { results } = await env.DB
    .prepare(
      `SELECT
        current.folder_name,
        COUNT(*) AS reporter_count,
        SUM(CASE WHEN history.server_submission_count >= 2 THEN 1 ELSE 0 END) AS repeat_reporter_count,
        SUM(history.server_submission_count) AS total_server_submission_count,
        MIN(history.first_server_seen_at_ms) AS first_server_seen_at_ms,
        MAX(history.last_server_seen_at_ms) AS last_server_seen_at_ms,
        MAX(current.submitted_at_ms) AS last_current_submission_at_ms
      FROM client_reports AS current
      INNER JOIN client_report_history AS history
        ON history.install_id = current.install_id
       AND history.folder_name = current.folder_name
      WHERE current.submitted_at_ms >= ?
      GROUP BY current.folder_name
      HAVING COUNT(*) >= ?
         AND SUM(CASE WHEN history.server_submission_count >= 2 THEN 1 ELSE 0 END) >= ?
      ORDER BY reporter_count DESC, repeat_reporter_count DESC, total_server_submission_count DESC, current.folder_name ASC`,
    )
    .bind(
      criteria.minSubmittedAtMs,
      criteria.minReporters,
      criteria.minRepeatReporters,
    )
    .all();

  return (results ?? []).map((row) => ({
    folderName: String(row.folder_name),
    reporterCount: readInteger(row.reporter_count),
    repeatReporterCount: readInteger(row.repeat_reporter_count),
    totalServerSubmissionCount: readInteger(row.total_server_submission_count),
    firstServerSeenAtMs: readInteger(row.first_server_seen_at_ms),
    lastServerSeenAtMs: readInteger(row.last_server_seen_at_ms),
    lastCurrentSubmissionAtMs: readInteger(row.last_current_submission_at_ms),
  }));
}

async function queryStorageSummary(env, criteria) {
  const [submissionResult, reporterResult] = await Promise.all([
    env.DB
      .prepare(
        `SELECT
          COUNT(*) AS active_installs,
          SUM(CASE WHEN report_count > 0 THEN 1 ELSE 0 END) AS installs_with_reports
        FROM client_submissions
        WHERE submitted_at_ms >= ?`,
      )
      .bind(criteria.minSubmittedAtMs)
      .first(),
    env.DB
      .prepare(
        `SELECT COUNT(DISTINCT install_id) AS unique_reporters
        FROM client_reports
        WHERE submitted_at_ms >= ?`,
      )
      .bind(criteria.minSubmittedAtMs)
      .first(),
  ]);

  return {
    activeInstalls: readInteger(submissionResult?.active_installs),
    installsWithReports: readInteger(submissionResult?.installs_with_reports),
    uniqueReporters: readInteger(reporterResult?.unique_reporters),
  };
}

async function buildReleaseBundle(env, criteria) {
  const generatedAtMs = Date.now();
  const [candidates, storageSummary] = await Promise.all([
    queryCommunityCandidates(env, criteria),
    queryStorageSummary(env, criteria),
  ]);

  return {
    generatedAtMs,
    storage: {
      provider: "cloudflare-d1",
      tables: [
        "client_submissions",
        "client_reports",
        "client_report_history",
        "client_submission_history",
      ],
    },
    criteria: describeCriteria(criteria),
    summary: {
      candidateCount: candidates.length,
      activeInstallCount: storageSummary.activeInstalls,
      installsWithReportsCount: storageSummary.installsWithReports,
      uniqueReporterCount: storageSummary.uniqueReporters,
    },
    games: candidates.map((candidate) => candidate.folderName),
    candidates,
  };
}

function buildCriteria(searchParams) {
  const maxSubmissionAgeDays = parsePositiveInt(
    searchParams.get("max_age_days"),
    DEFAULT_MAX_SUBMISSION_AGE_DAYS,
    MAX_SUBMISSION_AGE_DAYS,
  );
  const minReporters = parsePositiveInt(
    searchParams.get("min_reporters") ?? searchParams.get("threshold"),
    DEFAULT_MIN_REPORTERS,
    MAX_THRESHOLD,
  );
  const minRepeatReporters = parsePositiveInt(
    searchParams.get("min_repeat_reporters"),
    DEFAULT_MIN_REPEAT_REPORTERS,
    MAX_THRESHOLD,
  );
  const minSubmittedAtMs =
    Date.now() - maxSubmissionAgeDays * 24 * 60 * 60 * 1000;

  return {
    minReporters,
    minRepeatReporters,
    maxSubmissionAgeDays,
    minSubmittedAtMs,
  };
}

function validatePayload(payload) {
  if (!payload || typeof payload !== "object") {
    return { error: "Expected JSON object payload" };
  }

  const appVersion = normalizeAppVersion(payload.app_version);
  if (!appVersion) {
    return { error: "Missing or invalid app_version" };
  }

  const generatedAtMs = normalizeTimestamp(payload.generated_at_ms);
  if (generatedAtMs === null) {
    return { error: "Missing or invalid generated_at_ms" };
  }

  if (!Array.isArray(payload.reports)) {
    return { error: "Missing reports array" };
  }

  if (payload.reports.length > MAX_REPORTS_PER_REQUEST) {
    return { error: "Too many reports in one submission" };
  }

  const reportsByFolder = new Map();
  for (const entry of payload.reports) {
    if (!entry || typeof entry !== "object") {
      return { error: "Every report must be an object" };
    }

    const folderName = normalizeFolderName(entry.folder_name);
    if (!folderName) {
      return { error: "Every report needs a valid folder_name" };
    }

    const firstReportedAtMs = normalizeTimestamp(entry.first_reported_at_ms);
    const activeSinceMs = normalizeTimestamp(entry.active_since_ms);
    const lastReportedAtMs = normalizeTimestamp(entry.last_reported_at_ms);
    const lastWithdrawnAtMs =
      entry.last_withdrawn_at_ms == null
        ? null
        : normalizeTimestamp(entry.last_withdrawn_at_ms);
    const reportCount = normalizeCount(entry.report_count);

    if (
      firstReportedAtMs === null ||
      activeSinceMs === null ||
      lastReportedAtMs === null ||
      (entry.last_withdrawn_at_ms != null && lastWithdrawnAtMs === null) ||
      reportCount === null
    ) {
      return { error: "Invalid report timestamp/count fields" };
    }

    reportsByFolder.set(folderName, {
      folderName,
      firstReportedAtMs,
      activeSinceMs,
      lastReportedAtMs,
      lastWithdrawnAtMs,
      reportCount,
    });
  }

  return {
    legacyInstallId: normalizeReporterId(payload.install_id),
    appVersion,
    generatedAtMs,
    reports: [...reportsByFolder.values()],
  };
}

function normalizeReporterId(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > MAX_REPORTER_ID_LENGTH) {
    return null;
  }
  return trimmed;
}

async function resolveReporterId(env, headerReporterId, legacyInstallId) {
  // Only the header token (set by server on first submission) is trusted for
  // claiming an existing reporter identity.  The legacy install_id from the
  // payload body is user-generated and could be spoofed to overwrite another
  // client's reports, so it is only used as a weak hint for new registrations.
  const trustedToken = normalizeReporterId(headerReporterId);
  if (trustedToken && (await reporterExists(env, trustedToken))) {
    return trustedToken;
  }

  // Legacy install_id is only accepted if no existing reporter owns it —
  // i.e., it can seed a new identity but never hijack an existing one.
  const legacyId = normalizeReporterId(legacyInstallId);
  if (legacyId && !(await reporterExists(env, legacyId))) {
    // No existing reporter — safe to use as a new identity seed.
    return legacyId;
  }

  if (legacyId) {
    // Existing reporter with this ID but caller has no matching header token —
    // refuse to claim it. Fall through to generate a fresh ID.
  }

  return createReporterId();
}

async function reporterExists(env, reporterId) {
  const [currentSubmission, historicalReport] = await Promise.all([
    env.DB
      .prepare(
        `SELECT install_id
         FROM client_submissions
         WHERE install_id = ?
         LIMIT 1`,
      )
      .bind(reporterId)
      .first(),
    env.DB
      .prepare(
        `SELECT install_id
         FROM client_report_history
         WHERE install_id = ?
         LIMIT 1`,
      )
      .bind(reporterId)
      .first(),
  ]);

  return Boolean(
    currentSubmission?.install_id || historicalReport?.install_id,
  );
}

function createReporterId() {
  return `ppr-${crypto.randomUUID().replaceAll("-", "")}`.slice(
    0,
    MAX_REPORTER_ID_LENGTH,
  );
}

function normalizeAppVersion(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 64) {
    return null;
  }
  return trimmed;
}

function normalizeFolderName(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim().toLowerCase();
  if (!trimmed || trimmed.startsWith(".") || trimmed.length > MAX_FOLDER_NAME_LENGTH) {
    return null;
  }
  return trimmed;
}

function normalizeTimestamp(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    return null;
  }
  return value;
}

function normalizeCount(value) {
  if (!Number.isSafeInteger(value) || value < 1 || value > 1_000_000) {
    return null;
  }
  return value;
}

function describeCriteria(criteria) {
  return {
    minReporters: criteria.minReporters,
    minRepeatReporters: criteria.minRepeatReporters,
    maxSubmissionAgeDays: criteria.maxSubmissionAgeDays,
    minSubmittedAtMs: criteria.minSubmittedAtMs,
    note:
      "Thresholds are based on server-observed positive reporting signals only. Missing reports are not treated as negative votes.",
  };
}

function parsePositiveInt(value, fallback, maxValue) {
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return fallback;
  }
  return Math.min(parsed, maxValue);
}

function readInteger(value) {
  const parsed =
    typeof value === "number" ? value : Number.parseInt(String(value ?? "0"), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function json(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: JSON_HEADERS,
  });
}
