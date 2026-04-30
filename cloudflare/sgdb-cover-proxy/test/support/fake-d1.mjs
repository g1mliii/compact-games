function compactSql(sql) {
  return sql.replace(/\s+/g, " ").trim().toLowerCase();
}

function rateLimitKey(ipHash, windowStartMs) {
  return `${ipHash}\u0000${windowStartMs}`;
}

class FakeStatement {
  constructor(db, sql) {
    this.db = db;
    this.sql = compactSql(sql);
    this.bindings = [];
  }

  bind(...bindings) {
    this.bindings = bindings;
    return this;
  }

  async first() {
    return this.db.executeFirst(this.sql, this.bindings);
  }

  async run() {
    return this.db.executeWrite(this.sql, this.bindings);
  }
}

export class FakeD1Database {
  constructor() {
    this.rateLimits = new Map();
  }

  prepare(sql) {
    return new FakeStatement(this, sql);
  }

  executeFirst(sql, bindings) {
    if (
      sql.startsWith("insert into ip_rate_limits") &&
      sql.includes("returning count as count")
    ) {
      const [ipHash, windowStartMs, updatedAtMs] = bindings;
      const key = rateLimitKey(ipHash, windowStartMs);
      const existing = this.rateLimits.get(key);
      const count = existing ? existing.count + 1 : 1;
      this.rateLimits.set(key, {
        ip_hash: ipHash,
        window_start_ms: windowStartMs,
        count,
        updated_at_ms: updatedAtMs,
      });
      return { count };
    }

    if (
      sql.startsWith(
        "select count as count from ip_rate_limits where ip_hash = ? and window_start_ms = ?",
      )
    ) {
      const [ipHash, windowStartMs] = bindings;
      const row = this.rateLimits.get(rateLimitKey(ipHash, windowStartMs));
      return row ? { count: row.count } : null;
    }

    throw new Error(`Unsupported first() query in fake D1: ${sql}`);
  }

  executeWrite(sql, bindings) {
    if (sql.startsWith("insert into ip_rate_limits")) {
      const [ipHash, windowStartMs, updatedAtMs] = bindings;
      const key = rateLimitKey(ipHash, windowStartMs);
      const existing = this.rateLimits.get(key);
      this.rateLimits.set(key, {
        ip_hash: ipHash,
        window_start_ms: windowStartMs,
        count: existing ? existing.count + 1 : 1,
        updated_at_ms: updatedAtMs,
      });
      return { success: true, meta: { changes: 1 } };
    }

    if (sql.startsWith("delete from ip_rate_limits where updated_at_ms < ?")) {
      const [minUpdatedAtMs] = bindings;
      let changes = 0;
      for (const [key, row] of this.rateLimits) {
        if (row.updated_at_ms < minUpdatedAtMs) {
          this.rateLimits.delete(key);
          changes += 1;
        }
      }
      return { success: true, meta: { changes } };
    }

    throw new Error(`Unsupported run() query in fake D1: ${sql}`);
  }
}
