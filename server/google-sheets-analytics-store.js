"use strict";

const fs = require("node:fs");
const crypto = require("node:crypto");
const { AnalyticsStore, buildSummary, normalizeEvent } = require("./analytics-store");

const DEFAULT_SPREADSHEET_ID = "1cbvBLeqODtcOFhKm37IDyHyxysntyYODRvj5VP9ahWc";
const SHEETS_SCOPE = "https://www.googleapis.com/auth/spreadsheets";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_SHEETS_API = "https://sheets.googleapis.com/v4/spreadsheets";

const SHEETS = Object.freeze({
  events: {
    title: "Evenements",
    headers: [
      "created_at",
      "day",
      "event_type",
      "session_hash",
      "properties_json",
      "players",
      "maze_scale",
      "power_up_count",
      "duration_ms",
      "round",
      "path",
      "choice",
      "reason",
      "phase",
      "room_age_ms",
      "lobby_duration_ms",
      "max_players",
      "rounds_started",
      "completed_rounds",
      "finishers",
    ],
  },
  races: {
    title: "Courses",
    headers: [
      "created_at",
      "status",
      "race_key",
      "round",
      "players",
      "maze_scale",
      "power_up_count",
      "duration_ms",
      "start_at",
      "completed_at",
      "lobby_duration_ms",
    ],
  },
  summary: {
    title: "Synthese",
    headers: ["metric", "value"],
  },
  funnel: {
    title: "Funnel",
    headers: ["metric", "value"],
  },
  friction: {
    title: "Friction",
    headers: ["kind", "phase", "reason", "count"],
  },
  concurrency: {
    title: "Joueurs_10min",
    headers: ["bucket_start", "players", "races"],
  },
  parameters: {
    title: "Parametres",
    headers: ["parameter", "value", "count", "percent"],
  },
});

function normalizePrivateKey(value) {
  let key = String(value || "").trim();
  if (!key) return "";
  if ((key.startsWith("\"") && key.endsWith("\"")) || (key.startsWith("'") && key.endsWith("'"))) {
    try {
      key = JSON.parse(key);
    } catch {
      key = key.slice(1, -1);
    }
  }
  return key.replace(/\\n/g, "\n");
}

function parseServiceAccountJson(value) {
  const raw = String(value || "").trim();
  if (!raw) return {};
  const candidates = [raw];
  if (!raw.startsWith("{")) {
    try {
      candidates.push(Buffer.from(raw, "base64").toString("utf8"));
    } catch {
      // Ignore malformed base64 and fall through to JSON parsing below.
    }
  }
  for (const candidate of candidates) {
    try {
      return JSON.parse(candidate);
    } catch {
      // Try the next encoding candidate.
    }
  }
  return {};
}

function readServiceAccountFile(filePath) {
  const resolved = String(filePath || "").trim();
  if (!resolved) return {};
  try {
    return JSON.parse(fs.readFileSync(resolved, "utf8"));
  } catch {
    return {};
  }
}

function serviceAccountFromOptions(options = {}) {
  const fromJson = parseServiceAccountJson(
    options.serviceAccountJson
      ?? process.env.GOOGLE_SERVICE_ACCOUNT_JSON
      ?? process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON
      ?? "",
  );
  const fromFile = readServiceAccountFile(
    options.applicationCredentials
      ?? process.env.GOOGLE_APPLICATION_CREDENTIALS
      ?? "",
  );
  const credentials = { ...fromFile, ...fromJson };
  return {
    clientEmail: String(
      options.serviceAccountEmail
        ?? process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL
        ?? credentials.client_email
        ?? "",
    ).trim(),
    privateKey: normalizePrivateKey(
      options.privateKey
        ?? process.env.GOOGLE_PRIVATE_KEY
        ?? credentials.private_key
        ?? "",
    ),
  };
}

function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function googleDate(value) {
  return value ? new Date(value).toISOString() : "";
}

function quotedSheet(title) {
  return `'${String(title).replace(/'/g, "''")}'`;
}

function columnName(index) {
  let column = "";
  let value = index;
  while (value > 0) {
    const remainder = (value - 1) % 26;
    column = String.fromCharCode(65 + remainder) + column;
    value = Math.floor((value - 1) / 26);
  }
  return column;
}

function headerRange(sheet) {
  return `${quotedSheet(sheet.title)}!A1:${columnName(sheet.headers.length)}1`;
}

function valuesRange(sheet, rowCount) {
  return `${quotedSheet(sheet.title)}!A1:${columnName(sheet.headers.length)}${Math.max(1, rowCount)}`;
}

function tableRange(sheet) {
  return `${quotedSheet(sheet.title)}!A:${columnName(sheet.headers.length)}`;
}

function parseProperties(value) {
  try {
    const parsed = JSON.parse(String(value || "{}"));
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function propertyNumber(properties, ...names) {
  for (const name of names) {
    const value = properties?.[name];
    if (typeof value === "number" && Number.isFinite(value)) return value;
  }
  return "";
}

function propertyString(properties, ...names) {
  for (const name of names) {
    const value = properties?.[name];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

function rowEvent(row, fallbackTime) {
  const properties = parseProperties(row[4]);
  if (row[5] !== "" && row[5] !== undefined && properties.players === undefined) {
    properties.players = Number(row[5]);
  }
  if (row[6] !== "" && row[6] !== undefined && properties.mazeScale === undefined) {
    properties.mazeScale = Number(row[6]);
  }
  if (row[7] !== "" && row[7] !== undefined && properties.powerUpCount === undefined) {
    properties.powerUpCount = Number(row[7]);
  }
  if (row[8] !== "" && row[8] !== undefined && properties.durationMs === undefined) {
    properties.durationMs = Number(row[8]);
  }
  if (row[9] !== "" && row[9] !== undefined && properties.round === undefined) {
    properties.round = Number(row[9]);
  }
  if (row[10] && properties.path === undefined) properties.path = String(row[10]);
  if (row[11] && properties.choice === undefined) properties.choice = String(row[11]);
  if (row[12] && properties.reason === undefined) properties.reason = String(row[12]);
  if (row[13] && properties.phase === undefined) properties.phase = String(row[13]);
  if (row[14] !== "" && row[14] !== undefined && properties.roomAgeMs === undefined) {
    properties.roomAgeMs = Number(row[14]);
  }
  if (row[15] !== "" && row[15] !== undefined && properties.lobbyDurationMs === undefined) {
    properties.lobbyDurationMs = Number(row[15]);
  }
  if (row[16] !== "" && row[16] !== undefined && properties.maxPlayers === undefined) {
    properties.maxPlayers = Number(row[16]);
  }
  if (row[17] !== "" && row[17] !== undefined && properties.roundsStarted === undefined) {
    properties.roundsStarted = Number(row[17]);
  }
  if (row[18] !== "" && row[18] !== undefined && properties.completedRounds === undefined) {
    properties.completedRounds = Number(row[18]);
  }
  if (row[19] !== "" && row[19] !== undefined && properties.finishers === undefined) {
    properties.finishers = Number(row[19]);
  }
  return normalizeEvent({
    ts: Date.parse(row[0]),
    type: row[2],
    session: row[3] || "",
    props: properties,
  }, fallbackTime);
}

class GoogleSheetsAnalyticsStore {
  constructor({
    spreadsheetId = process.env.GOOGLE_SHEETS_SPREADSHEET_ID
      ?? process.env.GOOGLE_SPREADSHEET_ID
      ?? DEFAULT_SPREADSHEET_ID,
    retentionDays = 30,
    salt = "",
    now = () => Date.now(),
    fetchImpl = globalThis.fetch,
    fallbackStore = null,
    serviceAccountEmail,
    privateKey,
    serviceAccountJson,
    applicationCredentials,
  } = {}) {
    const serviceAccount = serviceAccountFromOptions({
      serviceAccountEmail,
      privateKey,
      serviceAccountJson,
      applicationCredentials,
    });
    this.spreadsheetId = String(spreadsheetId || "").trim();
    this.retentionDays = retentionDays;
    this.now = typeof now === "function" ? now : () => Date.now();
    this.fetchImpl = typeof fetchImpl === "function" ? fetchImpl : null;
    this.fallbackStore = fallbackStore || new AnalyticsStore({ retentionDays, salt, now });
    this.clientEmail = serviceAccount.clientEmail;
    this.privateKey = serviceAccount.privateKey;
    this.enabled = Boolean(this.spreadsheetId && this.clientEmail && this.privateKey && this.fetchImpl);
    this.token = null;
    this.ensurePromise = null;
    this.writeQueue = Promise.resolve();
  }

  pseudonymize(value) {
    return this.fallbackStore.pseudonymize(value);
  }

  async accessToken() {
    const now = Math.floor(this.now() / 1000);
    if (this.token && this.token.expiresAt > now + 60) return this.token.value;
    const unsigned = [
      base64urlJson({ alg: "RS256", typ: "JWT" }),
      base64urlJson({
        iss: this.clientEmail,
        scope: SHEETS_SCOPE,
        aud: GOOGLE_TOKEN_URL,
        exp: now + 3600,
        iat: now,
      }),
    ].join(".");
    const signer = crypto.createSign("RSA-SHA256");
    signer.update(unsigned);
    signer.end();
    const signature = signer.sign(this.privateKey).toString("base64url");
    const response = await this.fetchImpl(GOOGLE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: `${unsigned}.${signature}`,
      }),
    });
    if (!response.ok) throw new Error(`Google OAuth a repondu ${response.status}.`);
    const payload = await response.json();
    this.token = {
      value: payload.access_token,
      expiresAt: now + Number(payload.expires_in || 3600),
    };
    return this.token.value;
  }

  async request(suffix, options = {}) {
    if (!this.enabled) throw new Error("Google Sheets analytics indisponible.");
    const token = await this.accessToken();
    const response = await this.fetchImpl(`${GOOGLE_SHEETS_API}/${this.spreadsheetId}${suffix}`, {
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...(options.headers || {}),
      },
    });
    if (!response.ok) {
      throw new Error(`Google Sheets a repondu ${response.status}.`);
    }
    return response;
  }

  async ensureStructure() {
    if (!this.enabled) return;
    if (!this.ensurePromise) {
      this.ensurePromise = this.ensureStructureOnce().catch((error) => {
        this.ensurePromise = null;
        throw error;
      });
    }
    await this.ensurePromise;
  }

  async ensureStructureOnce() {
    const response = await this.request("?fields=sheets.properties.title", { method: "GET" });
    const workbook = await response.json();
    const existing = new Set((workbook.sheets || []).map((sheet) => sheet.properties?.title).filter(Boolean));
    const missing = Object.values(SHEETS).filter((sheet) => !existing.has(sheet.title));
    if (missing.length) {
      await this.request(":batchUpdate", {
        method: "POST",
        body: JSON.stringify({
          requests: missing.map((sheet) => ({ addSheet: { properties: { title: sheet.title } } })),
        }),
      });
    }
    for (const sheet of Object.values(SHEETS)) {
      await this.updateValues(headerRange(sheet), [sheet.headers]);
    }
  }

  enqueueWrite(task) {
    const run = this.writeQueue.then(task, task);
    this.writeQueue = run.catch(() => {});
    return run;
  }

  async updateValues(range, values) {
    await this.request(`/values/${encodeURIComponent(range)}?valueInputOption=RAW`, {
      method: "PUT",
      body: JSON.stringify({ values }),
    });
  }

  async appendValues(sheet, row) {
    await this.request(`/values/${encodeURIComponent(tableRange(sheet))}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS`, {
      method: "POST",
      body: JSON.stringify({ values: [row] }),
    });
  }

  async clearValues(sheet) {
    await this.request(`/values/${encodeURIComponent(tableRange(sheet))}:clear`, {
      method: "POST",
      body: JSON.stringify({}),
    });
  }

  eventRow(event) {
    return [
      new Date(event.ts).toISOString(),
      event.day,
      event.type,
      event.session,
      JSON.stringify(event.props),
      propertyNumber(event.props, "players"),
      propertyNumber(event.props, "mazeScale", "maze_scale"),
      propertyNumber(event.props, "powerUpCount", "power_up_count"),
      propertyNumber(event.props, "durationMs", "duration_ms"),
      propertyNumber(event.props, "round"),
      propertyString(event.props, "path"),
      propertyString(event.props, "choice"),
      propertyString(event.props, "reason"),
      propertyString(event.props, "phase"),
      propertyNumber(event.props, "roomAgeMs", "room_age_ms"),
      propertyNumber(event.props, "lobbyDurationMs", "lobby_duration_ms"),
      propertyNumber(event.props, "maxPlayers", "max_players"),
      propertyNumber(event.props, "roundsStarted", "rounds_started"),
      propertyNumber(event.props, "completedRounds", "completed_rounds"),
      propertyNumber(event.props, "finishers"),
    ];
  }

  raceRow(event) {
    const startedAt = propertyNumber(event.props, "startAtMs", "start_at_ms");
    const completedAt = propertyNumber(event.props, "completedAtMs", "completed_at_ms");
    return [
      new Date(event.ts).toISOString(),
      event.type === "race_started" ? "started" : "completed",
      event.session,
      propertyNumber(event.props, "round"),
      propertyNumber(event.props, "players"),
      propertyNumber(event.props, "mazeScale", "maze_scale"),
      propertyNumber(event.props, "powerUpCount", "power_up_count"),
      propertyNumber(event.props, "durationMs", "duration_ms"),
      googleDate(startedAt),
      googleDate(completedAt),
      propertyNumber(event.props, "lobbyDurationMs", "lobby_duration_ms"),
    ];
  }

  async writeEvent(event) {
    await this.ensureStructure();
    await this.appendValues(SHEETS.events, this.eventRow(event));
    if (event.type === "race_started" || event.type === "race_completed") {
      await this.appendValues(SHEETS.races, this.raceRow(event));
    }
  }

  async readEvents() {
    await this.ensureStructure();
    const response = await this.request(`/values/${encodeURIComponent(`${quotedSheet(SHEETS.events.title)}!A2:${columnName(SHEETS.events.headers.length)}`)}?majorDimension=ROWS`, {
      method: "GET",
    });
    const payload = await response.json();
    const fallbackTime = this.now();
    return (payload.values || [])
      .map((row) => rowEvent(row, fallbackTime))
      .filter((event) => event.type);
  }

  async writeSummary(summary) {
    const overviewRows = [
      ["generated_at", summary.generatedAt],
      ["stored_events", summary.storedEvents],
      ["unique_consented_sessions", summary.overview.uniqueConsentedSessions],
      ["page_views", summary.overview.pageViews],
      ["rooms_created", summary.overview.roomsCreated],
      ["room_joins", summary.overview.roomJoins],
      ["room_join_failures", summary.overview.roomJoinFailures],
      ["rooms_closed", summary.overview.roomsClosed],
      ["race_starts", summary.overview.raceStarts],
      ["race_completions", summary.overview.raceCompletions],
      ["race_restarts", summary.overview.raceRestarts],
      ["average_race_duration_ms", summary.overview.averageRaceDurationMs],
      ["average_lobby_duration_ms", summary.overview.averageLobbyDurationMs],
      ["average_rounds_per_closed_room", summary.overview.averageRoundsPerClosedRoom],
      ["peak_concurrent_players_10m", summary.overview.peakConcurrentPlayers10m],
      ["start_rate", summary.funnel.startRate],
      ["completion_rate", summary.funnel.completionRate],
      ["join_failure_rate", summary.funnel.joinFailureRate],
      ["restart_rate", summary.funnel.restartRate],
    ];
    const concurrencyRows = summary.concurrentPlayers10m.map((bucket) => [
      bucket.bucketStart,
      bucket.players,
      bucket.races,
    ]);
    const funnelRows = [
      ["start_rate", summary.funnel.startRate],
      ["completion_rate", summary.funnel.completionRate],
      ["join_failure_rate", summary.funnel.joinFailureRate],
      ["restart_rate", summary.funnel.restartRate],
      ["average_lobby_duration_ms", summary.overview.averageLobbyDurationMs],
      ["average_rounds_per_closed_room", summary.overview.averageRoundsPerClosedRoom],
    ];
    const frictionRows = [
      ...summary.joinFailures.map((row) => ["join_failed", "", row.reason, row.count]),
      ...summary.roomClosures.map((row) => ["room_closed", row.phase, row.reason, row.count]),
    ];
    const parameterRows = summary.parameterUsage.map((row) => [
      row.parameter,
      row.value,
      row.count,
      row.percent,
    ]);

    await this.clearValues(SHEETS.summary);
    await this.updateValues(valuesRange(SHEETS.summary, overviewRows.length + 1), [SHEETS.summary.headers, ...overviewRows]);
    await this.clearValues(SHEETS.funnel);
    await this.updateValues(valuesRange(SHEETS.funnel, funnelRows.length + 1), [SHEETS.funnel.headers, ...funnelRows]);
    await this.clearValues(SHEETS.friction);
    await this.updateValues(valuesRange(SHEETS.friction, frictionRows.length + 1), [SHEETS.friction.headers, ...frictionRows]);
    await this.clearValues(SHEETS.concurrency);
    await this.updateValues(valuesRange(SHEETS.concurrency, concurrencyRows.length + 1), [SHEETS.concurrency.headers, ...concurrencyRows]);
    await this.clearValues(SHEETS.parameters);
    await this.updateValues(valuesRange(SHEETS.parameters, parameterRows.length + 1), [SHEETS.parameters.headers, ...parameterRows]);
  }

  async record({ type, timestamp = this.now(), sessionId = "", properties = {} } = {}) {
    const event = this.fallbackStore.record({ type, timestamp, sessionId, properties });
    if (!event || !this.enabled) return event;
    await this.enqueueWrite(() => this.writeEvent(event)).catch(() => {});
    return event;
  }

  async summary({ days = 14 } = {}) {
    if (!this.enabled) return this.fallbackStore.summary({ days });
    try {
      await this.writeQueue.catch(() => {});
      const events = await this.readEvents();
      const summary = buildSummary(events, this.retentionDays, this.now(), days);
      await this.enqueueWrite(() => this.writeSummary(summary)).catch(() => {});
      return summary;
    } catch {
      return this.fallbackStore.summary({ days });
    }
  }
}

module.exports = {
  DEFAULT_SPREADSHEET_ID,
  GoogleSheetsAnalyticsStore,
  serviceAccountFromOptions,
};
