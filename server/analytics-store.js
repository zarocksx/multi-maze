"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const DEFAULT_RETENTION_DAYS = 30;
const MAX_STORED_EVENTS = 20_000;

function isoDay(timestamp) {
  return new Date(timestamp).toISOString().slice(0, 10);
}

function clampNumber(value, minimum, maximum, fallback = minimum) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.max(minimum, Math.min(maximum, numeric));
}

function sanitizeType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return /^[a-z0-9_]{2,40}$/.test(normalized) ? normalized : "";
}

function sanitizePathname(value) {
  const normalized = String(value || "").trim();
  if (!normalized.startsWith("/")) return "";
  return normalized.slice(0, 120);
}

function sanitizeProperties(properties = {}) {
  const result = {};
  for (const [rawKey, rawValue] of Object.entries(properties)) {
    const key = String(rawKey || "").trim();
    if (!/^[a-z][a-z0-9_]{1,31}$/.test(key)) continue;
    if (typeof rawValue === "boolean") {
      result[key] = rawValue;
      continue;
    }
    if (typeof rawValue === "number" && Number.isFinite(rawValue)) {
      result[key] = Math.round(rawValue * 100) / 100;
      continue;
    }
    if (typeof rawValue === "string") {
      const value = rawValue.trim().slice(0, 80);
      if (value) result[key] = value;
    }
  }
  return result;
}

function normalizeEvent(event, fallbackTime = Date.now()) {
  const ts = clampNumber(event?.ts, 0, Number.MAX_SAFE_INTEGER, fallbackTime);
  return {
    ts,
    day: isoDay(ts),
    type: sanitizeType(event?.type),
    session: typeof event?.session === "string" ? event.session.slice(0, 24) : "",
    props: sanitizeProperties(event?.props),
  };
}

function buildSummary(events, retentionDays, now, days = 14) {
  const rangeDays = clampNumber(days, 1, 90, 14);
  const cutoff = now - rangeDays * 24 * 60 * 60 * 1000;
  const recentEvents = events.filter((event) => event.ts >= cutoff);
  const totals = {};
  const dailyMap = new Map();
  const mazeScaleMap = new Map();
  const roomSizeMap = new Map();
  const pageMap = new Map();
  const consentMap = new Map();
  const durationValues = [];
  const consentedSessions = new Set();

  for (let index = rangeDays - 1; index >= 0; index -= 1) {
    const day = isoDay(now - index * 24 * 60 * 60 * 1000);
    dailyMap.set(day, {
      day,
      webSessions: 0,
      pageViews: 0,
      roomsCreated: 0,
      roomJoins: 0,
      raceStarts: 0,
      raceCompletions: 0,
    });
  }

  for (const event of recentEvents) {
    totals[event.type] = (totals[event.type] || 0) + 1;
    if (event.session) consentedSessions.add(event.session);
    const daily = dailyMap.get(event.day);
    if (daily) {
      if (event.type === "web_session_started") daily.webSessions += 1;
      if (event.type === "web_page_view") daily.pageViews += 1;
      if (event.type === "room_created") daily.roomsCreated += 1;
      if (event.type === "room_joined") daily.roomJoins += 1;
      if (event.type === "race_started") daily.raceStarts += 1;
      if (event.type === "race_completed") daily.raceCompletions += 1;
    }
    if (typeof event.props.mazeScale === "number") {
      const key = String(event.props.mazeScale);
      mazeScaleMap.set(key, (mazeScaleMap.get(key) || 0) + 1);
    }
    if (typeof event.props.players === "number") {
      const key = String(event.props.players);
      roomSizeMap.set(key, (roomSizeMap.get(key) || 0) + 1);
    }
    if (typeof event.props.path === "string") {
      const key = sanitizePathname(event.props.path);
      if (key) pageMap.set(key, (pageMap.get(key) || 0) + 1);
    }
    if (typeof event.props.choice === "string") {
      const key = event.props.choice.slice(0, 20);
      consentMap.set(key, (consentMap.get(key) || 0) + 1);
    }
    if (event.type === "race_completed" && typeof event.props.durationMs === "number") {
      durationValues.push(event.props.durationMs);
    }
  }

  const averageDurationMs = durationValues.length
    ? Math.round(durationValues.reduce((sum, value) => sum + value, 0) / durationValues.length)
    : 0;

  return {
    generatedAt: new Date(now).toISOString(),
    retentionDays,
    storedEvents: events.length,
    overview: {
      uniqueConsentedSessions: consentedSessions.size,
      pageViews: totals.web_page_view || 0,
      roomsCreated: totals.room_created || 0,
      roomJoins: totals.room_joined || 0,
      raceStarts: totals.race_started || 0,
      raceCompletions: totals.race_completed || 0,
      chatMessages: totals.chat_sent || 0,
      averageRaceDurationMs: averageDurationMs,
    },
    consent: [...consentMap.entries()]
      .map(([choice, count]) => ({ choice, count }))
      .sort((first, second) => second.count - first.count),
    daily: [...dailyMap.values()],
    mazeScales: [...mazeScaleMap.entries()]
      .map(([scale, count]) => ({ scale: Number(scale), count }))
      .sort((first, second) => first.scale - second.scale),
    roomSizes: [...roomSizeMap.entries()]
      .map(([players, count]) => ({ players: Number(players), count }))
      .sort((first, second) => first.players - second.players),
    topPages: [...pageMap.entries()]
      .map(([path, count]) => ({ path, count }))
      .sort((first, second) => second.count - first.count)
      .slice(0, 10),
  };
}

class AnalyticsStore {
  constructor({
    storagePath = path.resolve(__dirname, "data", "analytics.json"),
    retentionDays = DEFAULT_RETENTION_DAYS,
    salt = "",
    now = () => Date.now(),
  } = {}) {
    this.storagePath = storagePath;
    this.retentionDays = clampNumber(retentionDays, 1, 365, DEFAULT_RETENTION_DAYS);
    this.now = typeof now === "function" ? now : () => Date.now();
    this.salt = String(salt || "maze-analytics-salt");
    this.state = {
      events: [],
      lastPrunedAt: 0,
    };
    this.load();
    this.pruneExpired();
  }

  load() {
    try {
      const raw = fs.readFileSync(this.storagePath, "utf8");
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed?.events)) {
        this.state.events = parsed.events
          .filter((event) => event && typeof event === "object")
          .map((event) => normalizeEvent(event, this.now()))
          .filter((event) => event.type);
      }
      this.state.lastPrunedAt = clampNumber(parsed?.lastPrunedAt, 0, Number.MAX_SAFE_INTEGER, 0);
    } catch {
      this.state = { events: [], lastPrunedAt: 0 };
    }
  }

  save() {
    const directory = path.dirname(this.storagePath);
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(this.storagePath, JSON.stringify(this.state, null, 2));
  }

  pseudonymize(value) {
    if (!value) return "";
    return crypto.createHmac("sha256", this.salt).update(String(value)).digest("base64url").slice(0, 20);
  }

  pruneExpired(referenceTime = this.now()) {
    const maxAgeMs = this.retentionDays * 24 * 60 * 60 * 1000;
    const cutoff = referenceTime - maxAgeMs;
    const before = this.state.events.length;
    this.state.events = this.state.events
      .filter((event) => event.ts >= cutoff)
      .slice(-MAX_STORED_EVENTS);
    this.state.lastPrunedAt = referenceTime;
    if (this.state.events.length !== before) this.save();
  }

  record({ type, timestamp = this.now(), sessionId = "", properties = {} } = {}) {
    const eventType = sanitizeType(type);
    if (!eventType) return null;
    const event = normalizeEvent({
      ts: clampNumber(timestamp, 0, Number.MAX_SAFE_INTEGER, this.now()),
      type: eventType,
      session: this.pseudonymize(sessionId),
      props: properties,
    }, this.now());
    this.state.events.push(event);
    this.pruneExpired(event.ts);
    this.save();
    return event;
  }

  summary({ days = 14 } = {}) {
    const now = this.now();
    this.pruneExpired(now);
    return buildSummary(this.state.events, this.retentionDays, now, days);
  }
}

module.exports = {
  AnalyticsStore,
  buildSummary,
  normalizeEvent,
};
