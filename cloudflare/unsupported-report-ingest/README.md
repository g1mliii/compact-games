# Unsupported Report Ingest

This Worker receives stable unsupported-game snapshots from desktop clients and
stores one current snapshot per anonymous install ID. Community candidates and
the eventual shipped list are derived from positive reporting signals, not raw
post volume and not missing reports.

## Why this target

- Free and lightweight: Cloudflare Workers + D1 is a good fit for low-volume
  ingest and SQL aggregation.
- No GitHub write token in the desktop app.
- Easy threshold queries for "which folder names have enough independent
  evidence to ship?"

## Storage model

The Worker stores data in Cloudflare D1:

- `client_submissions`
  - One current row per anonymous install ID.
  - Tracks when that install last submitted and how many stable reports were in
    the snapshot.
- `client_reports`
  - One current row per install ID + folder name.
  - Represents the install's latest stable view of "this game is unsupported."
- `client_report_history`
  - One cumulative row per install ID + folder name.
  - Tracks server-observed repeat submissions and first/last server-seen times.
- `client_submission_history`
  - Append-only recent submission history per install ID.
  - Used for rolling per-reporter rate limiting on the ingest endpoint.
- `ip_submission_history`
  - Append-only recent submission history per source IP.
  - Used for per-IP rate limiting (including limiting mass "new reporter ID"
    registration from a single IP).

Absence of a report is intentionally not treated as a negative vote, because we
do not know whether another install even has that game. Thresholding is based on
positive confidence signals only:

- unique reporter count
- repeat reporter count derived from `client_report_history.server_submission_count`
- freshness window (`max_age_days`)

The Worker no longer trusts client-reported counters or timestamps as release
verification signals. It issues or reuses an authoritative reporter token on the
server side and derives repeat-observation metrics from server-seen submissions.
It also enforces a rolling per-reporter submission limit from server-side
submission history, plus a per-IP submission cap.

## API

- `POST /unsupported-reports`
  - Accepts the full stable snapshot for one install ID.
  - Replaces that install ID's prior current rows, so unmarking/removing
    reports is reflected naturally on the next sync.
  - Returns a server-issued/reused `reporterId` that the desktop client stores
    and reuses on later submissions.
  - Rejects bursts above the recent per-reporter submission window with `429`.
  - Rejects bursts above the recent per-IP submission window with `429`.
  - Rejects excessive "new reporter registrations" from one IP with `429`.
- `GET /community-candidates?min_reporters=3&min_repeat_reporters=1&max_age_days=180`
  - Returns aggregated candidate metadata.
- `GET /community-list?min_reporters=3&min_repeat_reporters=1&max_age_days=180`
  - Returns the plain folder-name list suitable for packaging into a release.
- `GET /release-bundle?min_reporters=3&min_repeat_reporters=1&max_age_days=180`
  - Returns the exact release-oriented bundle used by the export script/workflow:
    - `games`: plain folder-name list
    - `candidates`: review metadata
    - `summary`: recent install/reporter counts
    - `storage`: where the data is stored
- `GET /health`
  - Basic health response.

## Setup

1. Create the D1 database:

```bash
npx wrangler d1 create compact-games-unsupported-reports
```

2. Copy the returned `database_id` into [wrangler.toml](./wrangler.toml).

3. Apply the schema:

```bash
npx wrangler d1 execute compact-games-unsupported-reports --remote --file=./schema.sql
```

4. Deploy:

```bash
npx wrangler deploy
```

5. Export the current community bundle locally from the repo root if you want
   to review/package it:

```bash
node ./scripts/export-unsupported-community-list.mjs
```

## Local verification

From `cloudflare/unsupported-report-ingest/`:

```bash
npm run security:check
npm run check
npm test
```

The regression suite covers:

- router health/options/not-found handling
- submission validation
- current-snapshot ingestion behavior
- reporter token reuse and legacy `install_id` spoof protection
- rolling rate limiting
- per-IP rate limiting (including new reporter caps)
- community candidates/list/release-bundle responses
- required rate-limit schema artifacts

## Dependency hygiene

- Commit a lockfile with any future npm dependency change in this directory.
- Run `npm run security:check` before merging dependency updates.
- Review any install-time lifecycle scripts (`preinstall`, `install`, `postinstall`,
  `prepare`) before allowing them into the repo or CI.

## Desktop app configuration

Point the desktop client at the Worker using either:

- Environment variable: `PRESSPLAY_UNSUPPORTED_REPORT_ENDPOINT`
- Config file in the Compact Games config directory:
  - `unsupported_report_endpoint.txt`
  - contents: the full Worker URL, for example
    `https://compact-games-unsupported-report-ingest.example.workers.dev/unsupported-reports`

The client only submits:

- Stable reports that have remained active for at least 7 days
- At most once per 7-day submission interval when the stable payload changed

## Cloudflare WAF / Rate Limiting (recommended)

The Worker includes a server-side IP guard, but you should still configure a
Cloudflare Rate Limiting rule so bursts never reach the Worker/D1 in the first
place.

Suggested Cloudflare rule (tune to your usage):

- Expression: `http.request.method eq "POST" and http.request.uri.path eq "/unsupported-reports"`
- Characteristics: `IP`
- Rate: `15 requests per 1 minute`
- Action: `Block` (or `Managed Challenge` if you expect false positives)

## Optional: anonymize stored IPs (recommended)

The Worker can anonymize IP addresses before storing them in D1 (it will store a
stable HMAC instead of the raw IP). To enable this, set the secret:

```bash
npx wrangler secret put IP_HASH_SECRET
```

## Suggested release flow

1. Collect submissions continuously.
2. Review `GET /community-candidates` or the richer `GET /release-bundle`.
3. Run `node ./scripts/export-unsupported-community-list.mjs` from the repo root
   or trigger the
   GitHub workflow `.github/workflows/export-unsupported-community-list.yml`.
4. Use `dist/unsupported-community/unsupported_games.json` as the package/release
   input:
   - If your future packaging pipeline bundles files into the installer/app,
     copy this file in before the release build.
   - If your future updater downloads release assets, the workflow already
     attaches the JSON and review bundle to GitHub Releases.
5. Ship the next GitHub/package update so clients receive the new list on update.
