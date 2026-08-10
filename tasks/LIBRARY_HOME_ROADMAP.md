# Library Home Roadmap

Status: Deferred after the lightweight list-view expansion is complete and
validated. This document is the authoritative plan for the larger no-selection
experience; it is not part of the resize change.

## Product direction

- Add a persistent **Library Home** row above the list. Selecting it clears the
  current game selection and displays the home surface in the details pane.
- Replace the current no-selection prompt with a lightweight Library Home made
  from existing cards, typography, spacing, platform chips, and cover-art
  components.
- Show compact local highlights: total games, compressed games, actual space
  saved, largest install, biggest actual space saver, and most recently
  compressed game.
- Add a horizontally scrolling **What's New** shelf containing at most 12
  recent Steam Community items. Each card shows its date, headline, game,
  source, and existing library cover art; it does not download separate news
  thumbnails or embed a browser.

## Catalog identity and news

- Use native Steam App IDs whenever available.
- For Epic Games, Ubisoft Connect, EA, GOG, Battle.net, Xbox, and custom games,
  reuse the cover lookup's normalized game-name identity work but accept only a
  strict normalized exact match to the Steam catalog. Do not use prefix,
  contains, or fuzzy matches for news.
- Keep identity resolution shared, but keep news requests independent from
  cover requests so hidden or disabled news never causes network work.
- Fetch news from Steam's public `ISteamNews/GetNewsForApp/v2` endpoint. Label
  cross-store matches as **Steam Community**. Do not scrape SteamDB or publisher
  websites.
- After first paint, fetch only while Library Home is visible and networking is
  enabled. Use at most 16 candidate games, concurrency 2, and one result per
  candidate; prioritize recently compressed games, then larger games, with a
  stable path tie-breaker.
- Retain the newest 12 visible items. Persist at most 24 sanitized items or
  128 KiB with a six-hour freshness window, and show stale cached results when
  refresh fails.
- Bound and sanitize remote strings, validate Steam URLs, reject malformed
  payloads, and deduplicate stable item IDs/URLs before updating UI state.

## Offline mode

- Add `AppSettings.offlineMode`, defaulting to `false`, with a settings schema
  migration and a master Offline switch.
- While offline, disable news, remote cover/catalog requests, automatic and
  manual update checks/downloads, community compatibility database refreshes,
  compression database refreshes, and unsupported-report uploads. Continue to
  use already persisted local/cache data.
- Keep local loopback IPC available. Keep unsupported-report sharing as its own
  separately disabled-by-default consent setting.
- Start the native network gate disabled during bootstrap. Enable it only after
  settings load confirms online mode, and enforce `setNetworkAccessEnabled` in
  every native outbound path.
- When Offline is enabled, cancel Dart network timers and queues, close clients,
  and ignore results from requests that were already in flight.

## Data and lifecycle

- Introduce bounded internal models for `GameCatalogIdentity`, `GameNewsItem`,
  and `LibraryHomeUiModel`. Keep the home model to scalar totals, three game
  paths, and the bounded news list.
- Derive local highlights in one pass over the library and reuse that aggregate
  work for the existing overview where possible.
- Use disposable providers and existing image/runtime cache lifecycle hooks. Do
  not add polling timers, retained web views, unbounded maps, or duplicate image
  caches.

## Delivery stages

1. Add and test one-pass local highlights and the Library Home selection row.
2. Add strict catalog identity resolution with deterministic match fixtures.
3. Add bounded Steam news retrieval, persistence, stale fallback, and cards.
4. Add the master Offline setting plus Dart and native network enforcement.
5. Run localization, accessibility, failure-mode, lifecycle, and release-memory
   validation before enabling the feature by default.

## Acceptance and performance gates

- Empty, partial, compressed, large, and mixed-platform libraries produce
  deterministic highlights without additional library scans.
- News covers offline, timeout, malformed response, duplicates, strict-match
  rejection, stale cache, visibility gating, cancellation, and bounded
  concurrency.
- Offline tests prove every remote integration is blocked while local IPC and
  cached content continue to work.
- Library Home with five visible cards adds no more than 6 MiB median foreground
  working set over the current blank state.
- Expanded selected-game details add no more than 3 MiB median foreground
  working set; after 30 resize cycles, working set settles within 2 MiB of its
  pre-cycle baseline with no retained thread or handle growth.
- No commit, push, release, Steam upload, or production network enablement is
  included without a separate explicit request.
