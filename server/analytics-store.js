"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const DEFAULT_RETENTION_DAYS = 30;
const MAX_STORED_EVENTS = 20_000;
const TEN_MINUTES_MS = 10 * 60 * 1000;
const MAX_INCOMPLETE_RACE_MS = 2 * 60 * 60 * 1000;

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
    if (!/^[a-zA-Z][a-zA-Z0-9_]{1,31}$/.test(key)) continue;
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

function propertyNumber(properties, ...names) {
  for (const name of names) {
    const value = properties?.[name];
    if (typeof value === "number" && Number.isFinite(value)) return value;
  }
  return null;
}

function propertyString(properties, ...names) {
  for (const name of names) {
    const value = properties?.[name];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

function tenMinuteBucket(timestamp) {
  return Math.floor(timestamp / TEN_MINUTES_MS) * TEN_MINUTES_MS;
}

function incrementMap(map, value) {
  if (value === null || value === undefined || value === "") return;
  const key = String(value);
  map.set(key, (map.get(key) || 0) + 1);
}

function mapRows(map, keyName, numeric = true) {
  return [...map.entries()]
    .map(([key, count]) => ({ [keyName]: numeric ? Number(key) : key, count }))
    .sort((first, second) => {
      const firstValue = first[keyName];
      const secondValue = second[keyName];
      if (typeof firstValue === "number" && typeof secondValue === "number") {
        return firstValue - secondValue;
      }
      return String(firstValue).localeCompare(String(secondValue), "fr");
    });
}

function parameterUsageRows(parameter, values) {
  const total = [...values.values()].reduce((sum, count) => sum + count, 0);
  if (!total) return [];
  const numeric = [...values.keys()].every((key) => Number.isFinite(Number(key)));
  return mapRows(values, "value", numeric).map((row) => ({
    parameter,
    value: row.value,
    count: row.count,
    percent: Math.round((row.count / total) * 10_000) / 10_000,
  }));
}

function average(values) {
  return values.length
    ? Math.round(values.reduce((sum, value) => sum + value, 0) / values.length)
    : 0;
}

function ratio(numerator, denominator) {
  return denominator > 0 ? Math.round((numerator / denominator) * 10_000) / 10_000 : 0;
}

function buildRaceSessions(events, now) {
  const sessions = new Map();
  let anonymousIndex = 0;

  function raceKey(event) {
    if (event.session) return event.session;
    anonymousIndex += 1;
    return `event:${event.ts}:${anonymousIndex}`;
  }

  for (const event of events) {
    if (event.type !== "race_started" && event.type !== "race_completed") continue;
    const key = raceKey(event);
    const existing = sessions.get(key) || { key };
    const players = propertyNumber(event.props, "players");
    const mazeScale = propertyNumber(event.props, "mazeScale", "maze_scale");
    const powerUpCount = propertyNumber(event.props, "powerUpCount", "power_up_count");
    const round = propertyNumber(event.props, "round");

    if (players !== null) existing.players = players;
    if (mazeScale !== null) existing.mazeScale = mazeScale;
    if (powerUpCount !== null) existing.powerUpCount = powerUpCount;
    if (round !== null) existing.round = round;

    if (event.type === "race_started") {
      existing.started = true;
      existing.startTs = propertyNumber(event.props, "startAtMs", "start_at_ms") ?? event.ts;
      existing.startedEventTs = event.ts;
    }

    if (event.type === "race_completed") {
      const durationMs = propertyNumber(event.props, "durationMs", "duration_ms");
      existing.completed = true;
      existing.endTs = propertyNumber(event.props, "completedAtMs", "completed_at_ms") ?? event.ts;
      if (durationMs !== null) {
        existing.durationMs = durationMs;
        if (!existing.startTs) existing.startTs = Math.max(0, existing.endTs - durationMs);
      }
    }

    sessions.set(key, existing);
  }

  return [...sessions.values()]
    .filter((race) => race.started || race.completed)
    .map((race) => {
      const startTs = race.startTs ?? race.startedEventTs ?? race.endTs ?? now;
      const endTs = race.endTs ?? Math.min(now, startTs + MAX_INCOMPLETE_RACE_MS);
      return {
        ...race,
        startTs,
        endTs: Math.max(startTs, endTs),
        players: Math.max(0, Math.round(race.players || 0)),
      };
    });
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
  const joinFailureMap = new Map();
  const roomClosureMap = new Map();
  const durationValues = [];
  const lobbyDurationValues = [];
  const closedRoomRoundValues = [];
  const consentedSessions = new Set();
  const powerUpCountMap = new Map();
  const parameterMaps = {
    mazeScale: new Map(),
    powerUpCount: new Map(),
    players: new Map(),
  };
  const raceSessions = buildRaceSessions(recentEvents, now);

  for (let index = rangeDays - 1; index >= 0; index -= 1) {
    const day = isoDay(now - index * 24 * 60 * 60 * 1000);
    dailyMap.set(day, {
      day,
      webSessions: 0,
      pageViews: 0,
      roomsCreated: 0,
      roomJoins: 0,
      roomJoinFailures: 0,
      raceStarts: 0,
      raceCompletions: 0,
      roomsClosed: 0,
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
      if (event.type === "room_join_failed") daily.roomJoinFailures += 1;
      if (event.type === "race_started") daily.raceStarts += 1;
      if (event.type === "race_completed") daily.raceCompletions += 1;
      if (event.type === "room_closed") daily.roomsClosed += 1;
    }
    if (event.type === "room_join_failed") {
      incrementMap(joinFailureMap, propertyString(event.props, "reason") || "unknown");
    }
    if (event.type === "room_closed") {
      const phase = propertyString(event.props, "phase") || "unknown";
      const reason = propertyString(event.props, "reason") || "unknown";
      incrementMap(roomClosureMap, `${phase}:${reason}`);
      const roundsStarted = propertyNumber(event.props, "roundsStarted");
      if (roundsStarted !== null) closedRoomRoundValues.push(roundsStarted);
    }
    if (event.type === "race_started") {
      const lobbyDurationMs = propertyNumber(event.props, "lobbyDurationMs", "lobby_duration_ms");
      if (lobbyDurationMs !== null) lobbyDurationValues.push(lobbyDurationMs);
    }
    if (typeof event.props.path === "string") {
      const key = sanitizePathname(event.props.path);
      if (key) pageMap.set(key, (pageMap.get(key) || 0) + 1);
    }
    if (typeof event.props.choice === "string") {
      const key = event.props.choice.slice(0, 20);
      consentMap.set(key, (consentMap.get(key) || 0) + 1);
    }
  }

  for (const race of raceSessions) {
    if (race.durationMs !== undefined) durationValues.push(race.durationMs);
    incrementMap(mazeScaleMap, race.mazeScale);
    incrementMap(roomSizeMap, race.players);
    incrementMap(powerUpCountMap, race.powerUpCount);
    incrementMap(parameterMaps.mazeScale, race.mazeScale);
    incrementMap(parameterMaps.powerUpCount, race.powerUpCount);
    incrementMap(parameterMaps.players, race.players);
  }

  const averageDurationMs = average(durationValues);
  const joinAttempts = (totals.room_joined || 0) + (totals.room_join_failed || 0);
  const closedRooms = totals.room_closed || 0;

  const concurrentMap = new Map();
  const firstBucket = tenMinuteBucket(cutoff);
  const lastBucket = tenMinuteBucket(now);
  for (let timestamp = firstBucket; timestamp <= lastBucket; timestamp += TEN_MINUTES_MS) {
    concurrentMap.set(timestamp, { bucketStart: new Date(timestamp).toISOString(), players: 0, races: 0 });
  }
  for (const race of raceSessions) {
    if (!race.players || !race.startTs) continue;
    const start = Math.max(firstBucket, tenMinuteBucket(race.startTs));
    const end = Math.min(lastBucket, tenMinuteBucket(Math.max(race.startTs, race.endTs - 1)));
    for (let timestamp = start; timestamp <= end; timestamp += TEN_MINUTES_MS) {
      const bucket = concurrentMap.get(timestamp);
      if (!bucket) continue;
      bucket.players += race.players;
      bucket.races += 1;
    }
  }

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
      raceRestarts: totals.race_restarted || 0,
      roomJoinFailures: totals.room_join_failed || 0,
      roomsClosed: closedRooms,
      chatMessages: totals.chat_sent || 0,
      averageRaceDurationMs: averageDurationMs,
      averageLobbyDurationMs: average(lobbyDurationValues),
      averageRoundsPerClosedRoom: average(closedRoomRoundValues),
      peakConcurrentPlayers10m: Math.max(0, ...[...concurrentMap.values()].map((bucket) => bucket.players)),
    },
    funnel: {
      startRate: ratio(totals.race_started || 0, totals.room_created || 0),
      completionRate: ratio(totals.race_completed || 0, totals.race_started || 0),
      joinFailureRate: ratio(totals.room_join_failed || 0, joinAttempts),
      restartRate: ratio(totals.race_restarted || 0, totals.race_completed || 0),
    },
    consent: [...consentMap.entries()]
      .map(([choice, count]) => ({ choice, count }))
      .sort((first, second) => second.count - first.count),
    daily: [...dailyMap.values()],
    joinFailures: mapRows(joinFailureMap, "reason", false),
    roomClosures: mapRows(roomClosureMap, "closure", false).map((row) => {
      const [phase, reason] = String(row.closure).split(":");
      return { phase, reason, count: row.count };
    }),
    concurrentPlayers10m: [...concurrentMap.values()],
    parameterUsage: [
      ...parameterUsageRows("mazeScale", parameterMaps.mazeScale),
      ...parameterUsageRows("powerUpCount", parameterMaps.powerUpCount),
      ...parameterUsageRows("players", parameterMaps.players),
    ],
    mazeScales: mapRows(mazeScaleMap, "scale"),
    powerUpCounts: mapRows(powerUpCountMap, "powerUpCount"),
    roomSizes: mapRows(roomSizeMap, "players"),
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
