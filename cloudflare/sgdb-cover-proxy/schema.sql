CREATE TABLE IF NOT EXISTS ip_rate_limits (
  ip_hash TEXT NOT NULL,
  window_start_ms INTEGER NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (ip_hash, window_start_ms)
);

CREATE INDEX IF NOT EXISTS idx_ip_rate_limits_updated_at
  ON ip_rate_limits(updated_at_ms);
