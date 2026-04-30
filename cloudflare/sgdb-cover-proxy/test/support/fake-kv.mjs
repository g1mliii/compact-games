export class FakeKVNamespace {
  constructor() {
    this.entries = new Map();
  }

  async get(key) {
    const entry = this.entries.get(key);
    if (!entry) {
      return null;
    }
    if (entry.expiresAtMs != null && entry.expiresAtMs <= Date.now()) {
      this.entries.delete(key);
      return null;
    }
    return entry.value;
  }

  async put(key, value, options = {}) {
    const ttl = Number.isFinite(options.expirationTtl)
      ? options.expirationTtl
      : null;
    this.entries.set(key, {
      value,
      expiresAtMs: ttl == null ? null : Date.now() + ttl * 1000,
    });
  }
}
