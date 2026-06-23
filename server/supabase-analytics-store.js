"use strict";

const { AnalyticsStore, buildSummary, normalizeEvent } = require("./analytics-store");

class SupabaseAnalyticsStore {
  constructor({
    supabaseUrl,
    serviceRoleKey,
    table = "analytics_events",
    retentionDays = 30,
    salt = "",
    now = () => Date.now(),
    fetchImpl = globalThis.fetch,
    fallbackStore = null,
  } = {}) {
    this.supabaseUrl = String(supabaseUrl || "").replace(/\/+$/, "");
    this.serviceRoleKey = String(serviceRoleKey || "");
    this.table = String(table || "analytics_events");
    this.retentionDays = retentionDays;
    this.salt = salt;
    this.now = typeof now === "function" ? now : () => Date.now();
    this.fetchImpl = typeof fetchImpl === "function" ? fetchImpl : null;
    this.fallbackStore = fallbackStore || new AnalyticsStore({ retentionDays, salt, now });
    this.enabled = Boolean(this.supabaseUrl && this.serviceRoleKey && this.fetchImpl);
  }

  async request(relativePath, options = {}) {
    if (!this.enabled) throw new Error("Supabase analytics indisponible.");
    const response = await this.fetchImpl(`${this.supabaseUrl}/rest/v1/${relativePath}`, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        apikey: this.serviceRoleKey,
        Authorization: `Bearer ${this.serviceRoleKey}`,
        Prefer: "return=minimal",
        ...(options.headers || {}),
      },
    });
    if (!response.ok) {
      throw new Error(`Supabase analytics a répondu ${response.status}.`);
    }
    return response;
  }

  pseudonymize(value) {
    return this.fallbackStore.pseudonymize(value);
  }

  async record({ type, timestamp = this.now(), sessionId = "", properties = {} } = {}) {
    if (!this.enabled) return this.fallbackStore.record({ type, timestamp, sessionId, properties });
    const event = normalizeEvent({
      ts: timestamp,
      type,
      session: this.pseudonymize(sessionId),
      props: properties,
    }, this.now());
    if (!event.type) return null;
    await this.request(this.table, {
      method: "POST",
      body: JSON.stringify([{
        created_at: new Date(event.ts).toISOString(),
        event_type: event.type,
        session_hash: event.session || null,
        properties: event.props,
      }]),
    });
    return event;
  }

  async summary({ days = 14 } = {}) {
    if (!this.enabled) return this.fallbackStore.summary({ days });
    const now = this.now();
    const retentionCutoff = new Date(now - this.retentionDays * 24 * 60 * 60 * 1000).toISOString();
    const response = await this.request(
      `${this.table}?select=created_at,event_type,session_hash,properties&created_at=gte.${encodeURIComponent(retentionCutoff)}&order=created_at.asc&limit=20000`,
      { method: "GET", headers: { Prefer: "count=exact" } },
    );
    const rows = await response.json();
    const events = rows.map((row) => normalizeEvent({
      ts: Date.parse(row.created_at),
      type: row.event_type,
      session: row.session_hash || "",
      props: row.properties || {},
    }, now)).filter((event) => event.type);
    return buildSummary(events, this.retentionDays, now, days);
  }
}

function createAnalyticsStore(options = {}) {
  const fallbackStore = new AnalyticsStore(options);
  const supabaseUrl = options.supabaseUrl ?? process.env.SUPABASE_URL ?? "";
  const serviceRoleKey = options.serviceRoleKey ?? process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  if (!supabaseUrl || !serviceRoleKey) return fallbackStore;
  return new SupabaseAnalyticsStore({
    ...options,
    supabaseUrl,
    serviceRoleKey,
    fallbackStore,
  });
}

module.exports = {
  SupabaseAnalyticsStore,
  createAnalyticsStore,
};
