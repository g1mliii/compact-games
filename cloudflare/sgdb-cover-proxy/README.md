# SteamGridDB Cover Proxy

Cloudflare Worker that returns selected SteamGridDB grid image URLs for Compact Games. It does not proxy image bytes; the desktop app still downloads SteamGridDB images through its strict image downloader and local cache.

## Setup

1. Create the bindings if they do not already exist, then update the IDs in `wrangler.toml`:

   ```powershell
   npx wrangler kv namespace create compact-games-sgdb-cover-cache
   npx wrangler d1 create compact-games-sgdb-cover-proxy
   npx wrangler d1 execute compact-games-sgdb-cover-proxy --file schema.sql --remote
   ```

   The current Compact Games Cloudflare account has `CACHE` bound to KV namespace
   `c5fa8f43dded42c9ac307dbcb9685259` and `DB` bound to D1 database
   `b9e85744-0156-4848-9a14-ac3cba8ce9a8`.

2. Set secrets:

   ```powershell
   npx wrangler secret put SGDB_API_KEY
   npx wrangler secret put COMPACT_GAMES_PROXY_TOKEN
   npx wrangler secret put IP_HASH_SECRET
   ```

3. Verify and deploy:

   ```powershell
   npm run check
   npm test
   npx wrangler deploy --dry-run
   npx wrangler deploy
   ```

## Endpoints

- `GET /healthz`
- `GET /sgdb/grid?steam_app_id=<id>&dimension=<tall|wide|square>`
- `GET /sgdb/by-name?name=<encoded>&dimension=<tall|wide|square>`

`/sgdb/*` requires `X-Compact-Games-Token` matching `COMPACT_GAMES_PROXY_TOKEN`.
