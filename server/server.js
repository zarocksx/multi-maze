"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { WebSocketServer, WebSocket } = require("ws");
const { createAnalyticsStore } = require("./supabase-analytics-store");

const Wall = Object.freeze({
  TOP: 1,
  RIGHT: 2,
  BOTTOM: 4,
  LEFT: 8,
});
const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const COLORS = [
  "#45d9ff", "#ff5c8a", "#ffd166", "#79e36a", "#b58cff",
  "#ff914d", "#55efc4", "#f7aef8", "#8bd3ff", "#ffb703",
  "#90dbf4", "#fb6f92", "#caffbf", "#a0c4ff", "#ffc6ff",
  "#bde0fe", "#fdffb6", "#9bf6ff", "#d0f4de", "#e4c1f9",
];
const MAX_PLAYERS = 20;
const MOVE_COOLDOWN_MS = 55;
const COUNTDOWN_MS = 3500;
const DEFAULT_POWER_UP_COUNT = 10;
const MIN_POWER_UP_COUNT = 0;
const MAX_POWER_UP_COUNT = 30;
const POWER_UP_RESPAWN_MS = 8000;
const RANK_POINTS = [
  10, 7, 5, 3, 2,
  1, 1, 1, 1, 1,
  1, 1, 1, 1, 1,
  1, 1, 1, 1, 1,
];
const POWER_UP_KINDS = ["speed", "shield", "slow_all", "confuse_all", "freeze_all"];
const BASE_MAZE_WIDTH = 19;
const BASE_MAZE_HEIGHT = 13;
const DEFAULT_MAZE_SCALE = 5;
const MIN_MAZE_SCALE = 1;
const MAX_MAZE_SCALE = 10;
const MAZE_SCALE_STEP = 0.25;
const DEFAULT_MAZE_FACTOR = 0.75 + DEFAULT_MAZE_SCALE * MAZE_SCALE_STEP;
const MAZE_WIDTH = Math.round(BASE_MAZE_WIDTH * DEFAULT_MAZE_FACTOR);
const MAZE_HEIGHT = Math.round(BASE_MAZE_HEIGHT * DEFAULT_MAZE_FACTOR);

const DIRECTIONS = {
  up: { dx: 0, dy: -1, wall: Wall.TOP },
  right: { dx: 1, dy: 0, wall: Wall.RIGHT },
  down: { dx: 0, dy: 1, wall: Wall.BOTTOM },
  left: { dx: -1, dy: 0, wall: Wall.LEFT },
};

const AUTH_COOKIE = "maze_discord_session";
const OAUTH_STATE_COOKIE = "maze_discord_oauth_state";
const AUTH_SESSION_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const ANALYTICS_CONSENT_COOKIE = "maze_analytics_consent";
const ANALYTICS_ID_COOKIE = "maze_analytics_id";
const ANALYTICS_COOKIE_MAX_AGE_S = 180 * 24 * 60 * 60;

function parseCookies(header = "") {
  return String(header).split(";").reduce((cookies, part) => {
    const separator = part.indexOf("=");
    if (separator < 0) return cookies;
    const name = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (name) {
      try {
        cookies[name] = decodeURIComponent(value);
      } catch {
        cookies[name] = value;
      }
    }
    return cookies;
  }, {});
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 32_768) {
        reject(new Error("Corps de requête trop volumineux."));
      }
    });
    request.on("end", () => {
      if (!body) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new Error("JSON invalide."));
      }
    });
    request.on("error", reject);
  });
}

function cookieValue(value) {
  return encodeURIComponent(String(value));
}

function sameOriginBaseUrl(request) {
  return `${request.headers["x-forwarded-proto"] === "https" ? "https" : "http"}://${request.headers.host || "localhost"}`;
}

function isDoNotTrackEnabled(request) {
  const dnt = String(request.headers.dnt || request.headers["sec-gpc"] || "").trim();
  return dnt === "1" || dnt.toLowerCase() === "yes";
}

function requestPathForAnalytics(requestUrl) {
  const pathname = requestUrl.pathname || "/";
  if (pathname.length > 120) return pathname.slice(0, 120);
  return pathname;
}

function signValue(value, secret) {
  return crypto.createHmac("sha256", secret).update(value).digest("base64url");
}

function discordSnowflake(value) {
  const id = String(value ?? "");
  return /^\d+$/.test(id) ? id : "";
}

function discordAvatarHash(value) {
  return typeof value === "string" && /^[a-zA-Z0-9_]+$/.test(value) ? value : "";
}

function discordDefaultAvatarIndex(user) {
  const explicit = String(user?.defaultAvatar ?? user?.default_avatar ?? "");
  if (/^[0-5]$/.test(explicit)) return explicit;
  const id = discordSnowflake(user?.id);
  if (!id) return "0";
  return String(Number((BigInt(id) >> 22n) % 6n));
}

function createAuthSession(user, secret, now = Date.now()) {
  if (!secret) throw new Error("Un secret de session est requis.");
  const avatar = discordAvatarHash(user.avatar);
  const payload = Buffer.from(JSON.stringify({
    id: String(user.id),
    username: String(user.username || "Joueur Discord").slice(0, 32),
    displayName: String(user.global_name || user.displayName || user.username || "Joueur Discord").slice(0, 32),
    avatar,
    guildId: discordSnowflake(user.guildId ?? user.guild_id),
    guildAvatar: discordAvatarHash(user.guildAvatar ?? user.guild_avatar),
    defaultAvatar: avatar ? "" : discordDefaultAvatarIndex(user),
    expiresAt: now + AUTH_SESSION_MAX_AGE_MS,
  })).toString("base64url");
  return `${payload}.${signValue(payload, secret)}`;
}

function readAuthSession(value, secret, now = Date.now()) {
  if (!value || !secret) return null;
  const [payload, signature, extra] = String(value).split(".");
  if (!payload || !signature || extra) return null;
  const expected = signValue(payload, secret);
  const actualBuffer = Buffer.from(signature);
  const expectedBuffer = Buffer.from(expected);
  if (actualBuffer.length !== expectedBuffer.length || !crypto.timingSafeEqual(actualBuffer, expectedBuffer)) return null;
  try {
    const user = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    if (!discordSnowflake(user.id) || Number(user.expiresAt) <= now) return null;
    if (user.avatar && !discordAvatarHash(user.avatar)) return null;
    if (user.guildId && !discordSnowflake(user.guildId)) return null;
    if (user.guildAvatar && !discordAvatarHash(user.guildAvatar)) return null;
    return user;
  } catch {
    return null;
  }
}

function discordAvatarUrl(user) {
  const id = discordSnowflake(user?.id);
  if (!id) return "";
  const guildId = discordSnowflake(user.guildId);
  const guildAvatar = discordAvatarHash(user.guildAvatar);
  if (guildId && guildAvatar) {
    return `/api/discord/avatar/guild/${guildId}/user/${id}/${guildAvatar}.png`;
  }
  const avatar = discordAvatarHash(user.avatar);
  if (avatar) {
    return `/api/discord/avatar/${id}/${avatar}.png`;
  }
  const index = discordDefaultAvatarIndex(user);
  return `/api/discord/avatar/default/${index}.png`;
}

function discordActivityUserFromMessage(message) {
  const user = message?.discordActivityUser;
  if (!user || typeof user !== "object") return null;
  const id = discordSnowflake(user.id);
  if (!id) return null;
  const avatar = discordAvatarHash(user.avatar);
  const guildId = discordSnowflake(user.guildId ?? user.guild_id);
  const guildAvatar = discordAvatarHash(user.guildAvatar ?? user.guild_avatar);
  const defaultAvatar = discordDefaultAvatarIndex(user);
  return {
    id,
    username: String(user.username || "Joueur Discord").slice(0, 32),
    displayName: String(user.displayName || user.global_name || user.username || "Joueur Discord").slice(0, 32),
    avatar,
    guildId,
    guildAvatar,
    defaultAvatar,
  };
}

function normalizeMazeScale(value) {
  const scale = Math.round(Number(value) || DEFAULT_MAZE_SCALE);
  return Math.max(MIN_MAZE_SCALE, Math.min(MAX_MAZE_SCALE, scale));
}

function normalizePowerUpCount(value) {
  const count = Math.round(Number(value) || 0);
  return Math.max(MIN_POWER_UP_COUNT, Math.min(MAX_POWER_UP_COUNT, count));
}

function generateScaledMaze(scale) {
  const normalizedScale = normalizeMazeScale(scale);
  const factor = 0.75 + normalizedScale * MAZE_SCALE_STEP;
  return generateMaze(
    Math.round(BASE_MAZE_WIDTH * factor),
    Math.round(BASE_MAZE_HEIGHT * factor),
  );
}

function generateMaze(width = MAZE_WIDTH, height = MAZE_HEIGHT, random = Math.random) {
  const cells = new Array(width * height).fill(15);
  const visited = new Array(width * height).fill(false);
  const stack = [{ x: 0, y: 0 }];
  visited[0] = true;

  const carvingDirections = [
    { dx: 0, dy: -1, wall: Wall.TOP, opposite: Wall.BOTTOM },
    { dx: 1, dy: 0, wall: Wall.RIGHT, opposite: Wall.LEFT },
    { dx: 0, dy: 1, wall: Wall.BOTTOM, opposite: Wall.TOP },
    { dx: -1, dy: 0, wall: Wall.LEFT, opposite: Wall.RIGHT },
  ];

  while (stack.length) {
    const current = stack[stack.length - 1];
    const candidates = carvingDirections.filter(({ dx, dy }) => {
      const x = current.x + dx;
      const y = current.y + dy;
      return x >= 0 && x < width && y >= 0 && y < height && !visited[y * width + x];
    });
    if (!candidates.length) {
      stack.pop();
      continue;
    }
    const direction = candidates[Math.floor(random() * candidates.length)];
    const next = { x: current.x + direction.dx, y: current.y + direction.dy };
    const currentIndex = current.y * width + current.x;
    const nextIndex = next.y * width + next.x;
    cells[currentIndex] &= ~direction.wall;
    cells[nextIndex] &= ~direction.opposite;
    visited[nextIndex] = true;
    stack.push(next);
  }

  // Quelques boucles réduisent les longs culs-de-sac sans ouvrir le bord extérieur.
  const extraOpenings = Math.floor(width * height * 0.08);
  for (let i = 0; i < extraOpenings; i += 1) {
    const x = Math.floor(random() * width);
    const y = Math.floor(random() * height);
    const options = [];
    if (x + 1 < width && (cells[y * width + x] & Wall.RIGHT)) {
      options.push({ dx: 1, dy: 0, wall: Wall.RIGHT, opposite: Wall.LEFT });
    }
    if (y + 1 < height && (cells[y * width + x] & Wall.BOTTOM)) {
      options.push({ dx: 0, dy: 1, wall: Wall.BOTTOM, opposite: Wall.TOP });
    }
    if (!options.length) continue;
    const direction = options[Math.floor(random() * options.length)];
    const neighborIndex = (y + direction.dy) * width + x + direction.dx;
    cells[y * width + x] &= ~direction.wall;
    cells[neighborIndex] &= ~direction.opposite;
  }

  return {
    width,
    height,
    cells,
    start: { x: 0, y: 0 },
    exit: { x: width - 1, y: height - 1 },
  };
}

function createRoomCode(rooms) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    let code = "";
    for (let index = 0; index < 4; index += 1) {
      code += ROOM_ALPHABET[Math.floor(Math.random() * ROOM_ALPHABET.length)];
    }
    if (!rooms.has(code)) return code;
  }
  throw new Error("Impossible de générer un code de salon unique.");
}

function powerUpCountForMaze(maze, baseCount = DEFAULT_POWER_UP_COUNT) {
  const normalizedBaseCount = normalizePowerUpCount(baseCount);
  if (normalizedBaseCount <= 0) return 0;
  const defaultArea = MAZE_WIDTH * MAZE_HEIGHT;
  return Math.max(3, Math.round(normalizedBaseCount * maze.width * maze.height / defaultArea));
}

function createConfiguredPowerUps(maze, baseCount = DEFAULT_POWER_UP_COUNT, random = Math.random) {
  return createPowerUps(maze, powerUpCountForMaze(maze, baseCount), random);
}

function createPowerUps(maze, count = null, random = Math.random) {
  const targetCount = count ?? powerUpCountForMaze(maze);
  const candidates = [];
  for (let y = 0; y < maze.height; y += 1) {
    for (let x = 0; x < maze.width; x += 1) {
      const isStart = x === maze.start.x && y === maze.start.y;
      const isExit = x === maze.exit.x && y === maze.exit.y;
      const farEnoughFromStart = Math.abs(x - maze.start.x) + Math.abs(y - maze.start.y) > 3;
      if (!isStart && !isExit && farEnoughFromStart) candidates.push({ x, y });
    }
  }
  for (let index = candidates.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(random() * (index + 1));
    [candidates[index], candidates[swapIndex]] = [candidates[swapIndex], candidates[index]];
  }
  return candidates.slice(0, Math.min(targetCount, candidates.length)).map((position, index) => ({
    id: `power-${index + 1}`,
    x: position.x,
    y: position.y,
    active: true,
    respawnAt: 0,
  }));
}

function refreshPowerUps(room, now) {
  for (const powerUp of room.powerUps) {
    if (!powerUp.active && powerUp.respawnAt <= now) {
      powerUp.active = true;
      powerUp.respawnAt = 0;
    }
  }
}

function publicPowerUps(room, now) {
  refreshPowerUps(room, now);
  return room.powerUps.map(({ id, x, y, active, respawnAt }) => ({
    id,
    x,
    y,
    active,
    respawnMs: active ? 0 : Math.max(0, respawnAt - now),
  }));
}

function publicPlayer(player, now) {
  return {
    id: player.id,
    name: player.name,
    color: player.color,
    avatarUrl: player.avatarUrl || "",
    discord: Boolean(player.discordUserId || player.discordActivityUserId),
    x: player.x,
    y: player.y,
    finished: Boolean(player.finishedAt),
    timeMs: player.timeMs || 0,
    rank: player.rank || 0,
    effects: {
      speedMs: Math.max(0, (player.speedUntil || 0) - now),
      slowMs: Math.max(0, (player.slowUntil || 0) - now),
      confusedMs: Math.max(0, (player.confusedUntil || 0) - now),
      frozenMs: Math.max(0, (player.frozenUntil || 0) - now),
      shield: Boolean(player.shield),
    },
  };
}

function roomMessage(room) {
  const now = Date.now();
  return {
    type: "room",
    room: room.code,
    host: room.hostId,
    maze: room.maze,
    players: [...room.players.values()].map((player) => publicPlayer(player, now)),
    winner: room.winner || "",
    complete: Boolean(room.complete),
    phase: room.phase,
    startAt: room.startAt,
    serverNow: now,
    powerUps: publicPowerUps(room, now),
    event: room.lastEvent,
    round: room.round,
    mazeScale: room.mazeScale,
    powerUpCount: room.powerUpCount,
    podium: room.podium,
  };
}

function stateMessage(room) {
  const now = Date.now();
  return {
    type: "state",
    host: room.hostId,
    players: [...room.players.values()].map((player) => publicPlayer(player, now)),
    winner: room.winner || "",
    complete: Boolean(room.complete),
    phase: room.phase,
    startAt: room.startAt,
    serverNow: now,
    powerUps: publicPowerUps(room, now),
    event: room.lastEvent,
    round: room.round,
    mazeScale: room.mazeScale,
    powerUpCount: room.powerUpCount,
    podium: room.podium,
  };
}

function sanitizeName(value, fallbackNumber) {
  const cleaned = String(value || "").replace(/[<>\u0000-\u001f]/g, "").trim().slice(0, 16);
  return cleaned || `Joueur ${fallbackNumber}`;
}

function canMove(maze, x, y, directionName) {
  const direction = DIRECTIONS[directionName];
  if (!direction) return false;
  const nextX = x + direction.dx;
  const nextY = y + direction.dy;
  if (nextX < 0 || nextX >= maze.width || nextY < 0 || nextY >= maze.height) return false;
  return (maze.cells[y * maze.width + x] & direction.wall) === 0;
}

function recordRoundResults(room) {
  const results = [...room.players.values()]
    .filter((player) => player.finishedAt)
    .sort((first, second) => first.rank - second.rank);
  for (const player of results) {
    const standing = room.standings.get(player.id) || {
      id: player.id,
      name: player.name,
      color: player.color,
      avatarUrl: player.avatarUrl || "",
      points: 0,
      wins: 0,
      races: 0,
      totalTimeMs: 0,
    };
    standing.name = player.name;
    standing.color = player.color;
    standing.avatarUrl = player.avatarUrl || "";
    standing.points += RANK_POINTS[player.rank - 1] || 1;
    standing.wins += player.rank === 1 ? 1 : 0;
    standing.races += 1;
    standing.totalTimeMs += player.timeMs;
    room.standings.set(player.id, standing);
  }
  room.history.push({
    round: room.round,
    results: results.map((player) => ({
      id: player.id,
      name: player.name,
      color: player.color,
      rank: player.rank,
      timeMs: player.timeMs,
    })),
  });
  room.history = room.history.slice(-10);
  room.podium = [...room.standings.values()]
    .sort((first, second) =>
      second.points - first.points || second.wins - first.wins || first.totalTimeMs - second.totalTimeMs)
    .slice(0, 3)
    .map(({ id, name, color, avatarUrl, points, wins, races }) => ({
      id,
      name,
      color,
      avatarUrl,
      points,
      wins,
      races,
    }));
}

function updateRoomCompletion(room) {
  const wasComplete = room.complete;
  room.complete = room.players.size > 0 && [...room.players.values()].every((player) => player.finishedAt);
  if (room.complete && !wasComplete) {
    room.phase = "complete";
    recordRoundResults(room);
  }
}

function applyPowerUp(room, player, now = Date.now(), random = Math.random) {
  refreshPowerUps(room, now);
  const powerUp = room.powerUps.find((item) => item.active && item.x === player.x && item.y === player.y);
  if (!powerUp) return null;
  powerUp.active = false;
  powerUp.respawnAt = now + POWER_UP_RESPAWN_MS;
  const kind = POWER_UP_KINDS[Math.floor(random() * POWER_UP_KINDS.length)];
  const targets = [];
  let message = "";

  if (kind === "speed") {
    player.speedUntil = now + 5000;
    message = `${player.name} obtient un turbo !`;
  } else if (kind === "shield") {
    player.shield = true;
    message = `${player.name} gagne un bouclier !`;
  } else {
    for (const target of room.players.values()) {
      if (target.id === player.id || target.finishedAt) continue;
      targets.push(target.id);
      if (target.shield) {
        target.shield = false;
        continue;
      }
      if (kind === "slow_all") target.slowUntil = now + 4500;
      if (kind === "confuse_all") target.confusedUntil = now + 4000;
      if (kind === "freeze_all") target.frozenUntil = now + 1400;
    }
    if (kind === "slow_all") message = `${player.name} ralentit ses adversaires !`;
    if (kind === "confuse_all") message = `${player.name} inverse les commandes adverses !`;
    if (kind === "freeze_all") message = `${player.name} gèle ses adversaires !`;
  }

  room.lastEvent = {
    id: crypto.randomUUID(),
    kind,
    actorId: player.id,
    targetIds: targets,
    message,
    createdAt: now,
    x: powerUp.x,
    y: powerUp.y,
  };
  return room.lastEvent;
}

function applyMove(room, player, directionName, now = Date.now()) {
  if (room.phase === "countdown" && now >= room.startAt) room.phase = "running";
  if (room.phase !== "running" || player.finishedAt || player.frozenUntil > now) return false;
  let cooldown = MOVE_COOLDOWN_MS;
  if (player.slowUntil > now) cooldown = 110;
  if (player.speedUntil > now) cooldown = 28;
  if (now - player.lastMoveAt < cooldown) return false;
  if (!canMove(room.maze, player.x, player.y, directionName)) return false;
  const direction = DIRECTIONS[directionName];
  player.x += direction.dx;
  player.y += direction.dy;
  player.lastMoveAt = now;
  applyPowerUp(room, player, now);
  if (player.x === room.maze.exit.x && player.y === room.maze.exit.y) {
    player.finishedAt = now;
    player.timeMs = Math.max(0, player.finishedAt - room.startAt);
    room.finishCount += 1;
    player.rank = room.finishCount;
    if (!room.winner) room.winner = player.id;
    updateRoomCompletion(room);
  }
  return true;
}

function prepareRoomMaze(room, nextMaze) {
  room.maze = nextMaze;
  room.winner = "";
  room.complete = false;
  room.finishCount = 0;
  room.phase = "waiting";
  room.startAt = 0;
  room.powerUps = createConfiguredPowerUps(room.maze, room.powerUpCount);
  room.lastEvent = null;
  for (const player of room.players.values()) {
    player.x = room.maze.start.x;
    player.y = room.maze.start.y;
    player.lastMoveAt = 0;
    player.finishedAt = 0;
    player.timeMs = 0;
    player.rank = 0;
    player.speedUntil = 0;
    player.slowUntil = 0;
    player.confusedUntil = 0;
    player.frozenUntil = 0;
    player.shield = false;
  }
}

function resetRoom(room, nextMaze = null) {
  prepareRoomMaze(room, nextMaze || generateScaledMaze(room.mazeScale));
  room.round = (room.round || 0) + 1;
}

function createGameServer({
  webRoot = path.resolve(__dirname, "..", "web"),
  analyticsWebRoot = path.resolve(__dirname, "..", "analytics-dashboard"),
  discordConfig = {},
  analyticsConfig = {},
  fetchImpl = globalThis.fetch,
} = {}) {
  const rooms = new Map();

  const auth = {
    clientId: discordConfig.clientId ?? process.env.DISCORD_CLIENT_ID ?? "",
    clientSecret: discordConfig.clientSecret ?? process.env.DISCORD_CLIENT_SECRET ?? "",
    redirectUri: discordConfig.redirectUri ?? process.env.DISCORD_REDIRECT_URI ?? "",
    sessionSecret: discordConfig.sessionSecret ?? process.env.AUTH_SESSION_SECRET ?? process.env.DISCORD_CLIENT_SECRET ?? "",
  };
  auth.enabled = Boolean(auth.clientId && auth.clientSecret && auth.redirectUri && auth.sessionSecret);

  const analytics = {
    enabled: analyticsConfig.enabled ?? process.env.ANALYTICS_ENABLED !== "false",
    dashboardToken: analyticsConfig.dashboardToken ?? process.env.ANALYTICS_DASHBOARD_TOKEN ?? "",
    consentRequired: analyticsConfig.consentRequired ?? true,
  };
  analytics.store = createAnalyticsStore({
    storagePath: analyticsConfig.storagePath ?? path.resolve(__dirname, "data", "analytics.json"),
    retentionDays: analyticsConfig.retentionDays ?? Number(process.env.ANALYTICS_RETENTION_DAYS || 30),
    salt: analyticsConfig.salt ?? process.env.ANALYTICS_SALT ?? auth.sessionSecret ?? "maze-analytics-salt",
    supabaseUrl: analyticsConfig.supabaseUrl ?? process.env.SUPABASE_URL ?? "",
    serviceRoleKey: analyticsConfig.serviceRoleKey ?? process.env.SUPABASE_SERVICE_ROLE_KEY ?? "",
    table: analyticsConfig.table ?? process.env.SUPABASE_ANALYTICS_TABLE ?? "analytics_events",
    fetchImpl,
  });

  function securityHeaders(extra = {}) {
    return {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
      ...extra,
    };
  }

  function sendJson(response, status, payload, extraHeaders = {}) {
    response.writeHead(status, securityHeaders({
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders,
    }));
    response.end(JSON.stringify(payload));
  }

  function redirect(response, location, cookies = []) {
    const headers = securityHeaders({ Location: location, "Cache-Control": "no-store" });
    if (cookies.length) headers["Set-Cookie"] = cookies;
    response.writeHead(302, headers);
    response.end();
  }

  function secureCookie(request) {
    return request.headers["x-forwarded-proto"] === "https" || auth.redirectUri.startsWith("https://");
  }

  function authSessionCookie(request) {
    return parseCookies(request.headers.cookie)[AUTH_COOKIE] || "";
  }

  function authSessionToken(request, requestUrl = null) {
    const authorization = String(request.headers.authorization || "");
    if (authorization.toLowerCase().startsWith("bearer ")) {
      return authorization.slice(7).trim();
    }
    const explicitHeader = String(request.headers["x-maze-session"] || "").trim();
    if (explicitHeader) return explicitHeader;
    const resolvedUrl = requestUrl || new URL(request.url, sameOriginBaseUrl(request));
    return resolvedUrl.searchParams.get("session") || "";
  }

  function sessionUser(request, requestUrl = null) {
    const session = authSessionCookie(request) || authSessionToken(request, requestUrl);
    return readAuthSession(session, auth.sessionSecret);
  }

  function authSessionCookieHeader(request, session, sameSite = "Lax") {
    const secure = secureCookie(request) ? "; Secure" : "";
    return `${AUTH_COOKIE}=${cookieValue(session)}; Path=/; HttpOnly; SameSite=${sameSite}; Max-Age=${Math.floor(AUTH_SESSION_MAX_AGE_MS / 1000)}${secure}`;
  }

  async function fetchDiscordIdentityFromCode(code, includeRedirectUri = false) {
    if (!auth.enabled || !code || typeof fetchImpl !== "function") {
      throw new Error("Discord OAuth indisponible.");
    }
    const body = new URLSearchParams({
      client_id: auth.clientId,
      client_secret: auth.clientSecret,
      grant_type: "authorization_code",
      code,
    });
    if (includeRedirectUri) {
      body.set("redirect_uri", auth.redirectUri);
    }
    const tokenResponse = await fetchImpl("https://discord.com/api/v10/oauth2/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
    if (!tokenResponse.ok) throw new Error("Discord OAuth refused");
    const token = await tokenResponse.json();
    const userResponse = await fetchImpl("https://discord.com/api/v10/users/@me", {
      headers: { Authorization: `Bearer ${token.access_token}` },
    });
    if (!userResponse.ok) throw new Error("Profil Discord indisponible");
    const user = await userResponse.json();
    if (!/^\d+$/.test(String(user.id))) throw new Error("Profil Discord invalide");
    return { token, user };
  }

  function analyticsConsent(request) {
    const consent = parseCookies(request.headers.cookie)[ANALYTICS_CONSENT_COOKIE];
    if (consent === "granted" || consent === "denied") return consent;
    return "unknown";
  }

  function analyticsSessionId(request) {
    return parseCookies(request.headers.cookie)[ANALYTICS_ID_COOKIE] || "";
  }

  function analyticsCookies(request, consent, sessionId = "") {
    const secure = secureCookie(request) ? "; Secure" : "";
    const cookies = [
      `${ANALYTICS_CONSENT_COOKIE}=${cookieValue(consent)}; Path=/; SameSite=Lax; Max-Age=${ANALYTICS_COOKIE_MAX_AGE_S}${secure}`,
    ];
    if (consent === "granted" && sessionId) {
      cookies.push(
        `${ANALYTICS_ID_COOKIE}=${cookieValue(sessionId)}; Path=/; SameSite=Lax; Max-Age=${ANALYTICS_COOKIE_MAX_AGE_S}${secure}`,
      );
    } else {
      cookies.push(`${ANALYTICS_ID_COOKIE}=; Path=/; SameSite=Lax; Max-Age=0${secure}`);
    }
    return cookies;
  }

  function canTrackWebAnalytics(request) {
    if (!analytics.enabled) return false;
    if (isDoNotTrackEnabled(request)) return false;
    if (!analytics.consentRequired) return true;
    return analyticsConsent(request) === "granted";
  }

  function recordAnalytics(type, properties = {}, sessionId = "") {
    if (!analytics.enabled) return;
    Promise.resolve(analytics.store.record({ type, properties, sessionId })).catch(() => {});
  }

  function analyticsAuthorized(request) {
    if (!analytics.enabled) return false;
    if (analytics.dashboardToken) {
      return request.headers["x-analytics-token"] === analytics.dashboardToken;
    }
    return ["127.0.0.1", "::1", "::ffff:127.0.0.1"].includes(request.socket.remoteAddress);
  }

  function roomAnalyticsSession(room) {
    return `room:${room.code}:round:${room.round}`;
  }

  function serveStaticFile(root, relativePath, response, notFoundMessage) {
    const normalizedPath = path.normalize(relativePath).replace(/^(\.\.[/\\])+/, "");
    const filePath = path.resolve(root, normalizedPath);
    if (!filePath.startsWith(path.resolve(root))) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    fs.readFile(filePath, (error, data) => {
      if (error) {
        response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
        response.end(notFoundMessage);
        return;
      }
      const mime = {
        ".html": "text/html; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".js": "text/javascript; charset=utf-8",
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".png": "image/png",
        ".svg": "image/svg+xml",
        ".ico": "image/x-icon",
      }[path.extname(filePath)] || "application/octet-stream";
      response.writeHead(200, securityHeaders({ "Content-Type": mime }));
      response.end(data);
    });
  }

  let embeddedSdkModuleCache = "";

  async function serveEmbeddedSdkModule(response) {
    if (embeddedSdkModuleCache) {
      response.writeHead(200, securityHeaders({
        "Content-Type": "text/javascript; charset=utf-8",
        "Cache-Control": "public, max-age=3600",
      }));
      response.end(embeddedSdkModuleCache);
      return;
    }
    if (typeof fetchImpl !== "function") {
      response.writeHead(503).end("SDK Discord indisponible");
      return;
    }
    try {
      const sdkResponse = await fetchImpl("https://cdn.jsdelivr.net/npm/@discord/embedded-app-sdk/+esm", {
        headers: { "User-Agent": "A-Maze-Inc/1.0" },
      });
      if (!sdkResponse.ok) {
        response.writeHead(502).end("SDK Discord indisponible");
        return;
      }
      embeddedSdkModuleCache = await sdkResponse.text();
      response.writeHead(200, securityHeaders({
        "Content-Type": "text/javascript; charset=utf-8",
        "Cache-Control": "public, max-age=3600",
      }));
      response.end(embeddedSdkModuleCache);
    } catch {
      response.writeHead(502).end("SDK Discord indisponible");
    }
  }

  async function proxyDiscordAvatar(requestUrl, response) {
    const guildCustom = requestUrl.pathname.match(/^\/api\/discord\/avatar\/guild\/(\d+)\/user\/(\d+)\/([a-zA-Z0-9_]+)\.png$/);
    const custom = requestUrl.pathname.match(/^\/api\/discord\/avatar\/(\d+)\/([a-zA-Z0-9_]+)\.png$/);
    const fallback = requestUrl.pathname.match(/^\/api\/discord\/avatar\/default\/([0-5])\.png$/);
    if (!guildCustom && !custom && !fallback) return false;
    if (typeof fetchImpl !== "function") {
      response.writeHead(503).end("Avatar indisponible");
      return true;
    }
    let cdnUrl = "";
    if (guildCustom) {
      cdnUrl = `https://cdn.discordapp.com/guilds/${guildCustom[1]}/users/${guildCustom[2]}/avatars/${guildCustom[3]}.png?size=128`;
    } else if (custom) {
      cdnUrl = `https://cdn.discordapp.com/avatars/${custom[1]}/${custom[2]}.png?size=128`;
    } else {
      cdnUrl = `https://cdn.discordapp.com/embed/avatars/${fallback[1]}.png`;
    }
    try {
      const avatarResponse = await fetchImpl(cdnUrl, { headers: { "User-Agent": "A-Maze-Inc/1.0" } });
      if (!avatarResponse.ok) {
        response.writeHead(avatarResponse.status === 404 ? 404 : 502).end("Avatar indisponible");
        return true;
      }
      response.writeHead(200, securityHeaders({
        "Content-Type": "image/png",
        "Cache-Control": "public, max-age=86400, immutable",
        "Cross-Origin-Resource-Policy": "same-origin",
      }));
      response.end(Buffer.from(await avatarResponse.arrayBuffer()));
    } catch {
      response.writeHead(502).end("Avatar indisponible");
    }
    return true;
  }

  async function handleHttpRequest(request, response) {
    const requestUrl = new URL(request.url, "http://localhost");
    if (requestUrl.pathname === "/.proxy") {
      requestUrl.pathname = "/";
    } else if (requestUrl.pathname.startsWith("/.proxy/")) {
      requestUrl.pathname = requestUrl.pathname.slice("/.proxy".length);
    }

    if (requestUrl.pathname === "/api/analytics/consent" && request.method === "GET") {
      sendJson(response, 200, {
        enabled: analytics.enabled,
        consentRequired: analytics.consentRequired,
        consent: analyticsConsent(request),
        doNotTrack: isDoNotTrackEnabled(request),
      });
      return;
    }

    if (requestUrl.pathname === "/api/analytics/consent" && request.method === "POST") {
      const payload = await readJsonBody(request);
      const consent = isDoNotTrackEnabled(request)
        ? "denied"
        : (payload.consent === "granted" ? "granted" : "denied");
      const sessionId = consent === "granted" ? (analyticsSessionId(request) || crypto.randomUUID()) : "";
      const headers = { "Set-Cookie": analyticsCookies(request, consent, sessionId) };
      recordAnalytics("consent_updated", { choice: consent }, consent === "granted" ? sessionId : "");
      sendJson(response, 200, {
        enabled: analytics.enabled,
        consentRequired: analytics.consentRequired,
        consent,
        doNotTrack: isDoNotTrackEnabled(request),
      }, headers);
      return;
    }

    if (requestUrl.pathname === "/api/analytics/event" && request.method === "POST") {
      if (!canTrackWebAnalytics(request)) {
        sendJson(response, 202, { accepted: false, reason: "tracking-disabled" });
        return;
      }
      const payload = await readJsonBody(request);
      const allowedTypes = new Set(["web_session_started", "web_page_view"]);
      const type = allowedTypes.has(payload.type) ? payload.type : "";
      if (!type) {
        sendJson(response, 400, { error: "Type d'événement analytics invalide." });
        return;
      }
      const sessionId = analyticsSessionId(request);
      recordAnalytics(type, {
        path: requestPathForAnalytics(payload.path || "/"),
      }, sessionId);
      sendJson(response, 202, { accepted: true });
      return;
    }

    if (requestUrl.pathname === "/api/analytics/summary" && request.method === "GET") {
      if (!analyticsAuthorized(request)) {
        sendJson(response, 401, { error: "Accès analytics non autorisé." });
        return;
      }
      sendJson(response, 200, await analytics.store.summary({
        days: Number(requestUrl.searchParams.get("days") || 14),
      }));
      return;
    }

    if (requestUrl.pathname === "/api/auth/me") {
      const user = sessionUser(request, requestUrl);
      sendJson(response, 200, user ? {
        authenticated: true,
        enabled: auth.enabled,
        clientId: auth.clientId,
        user: {
          id: user.id,
          username: user.username,
          displayName: user.displayName,
          avatarUrl: discordAvatarUrl(user),
        },
      } : { authenticated: false, enabled: auth.enabled, clientId: auth.clientId });
      return;
    }

    if (requestUrl.pathname === "/api/auth/logout" && request.method === "POST") {
      const secure = secureCookie(request) ? "; Secure" : "";
      sendJson(response, 200, { authenticated: false, enabled: auth.enabled, clientId: auth.clientId }, {
        "Set-Cookie": `${AUTH_COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure}`,
      });
      return;
    }

    if (requestUrl.pathname === "/api/auth/discord/config" && request.method === "GET") {
      sendJson(response, 200, {
        enabled: auth.enabled,
        clientId: auth.clientId,
      });
      return;
    }

    if (requestUrl.pathname === "/api/auth/discord/activity" && request.method === "POST") {
      if (!auth.enabled) {
        sendJson(response, 503, { error: "La connexion Discord n'est pas configurée sur ce serveur." });
        return;
      }
      try {
        const payload = await readJsonBody(request);
        const code = typeof payload.code === "string" ? payload.code.trim() : "";
        const { token, user } = await fetchDiscordIdentityFromCode(code, false);
        const session = createAuthSession(user, auth.sessionSecret);
        recordAnalytics("discord_login_success", { provider: "discord_activity" });
        sendJson(response, 200, {
          authenticated: true,
          access_token: token.access_token,
          session,
          user: {
            id: String(user.id),
            username: String(user.username || "Joueur Discord"),
            displayName: String(user.global_name || user.displayName || user.username || "Joueur Discord"),
            avatarUrl: discordAvatarUrl(user),
          },
        }, {
          "Set-Cookie": authSessionCookieHeader(request, session, secureCookie(request) ? "None" : "Lax"),
        });
      } catch (error) {
        sendJson(response, 400, {
          error: error instanceof Error ? error.message : "Connexion Discord impossible.",
        });
      }
      return;
    }

    if (requestUrl.pathname === "/vendor/discord-embedded-app-sdk.mjs" && request.method === "GET") {
      await serveEmbeddedSdkModule(response);
      return;
    }

    if (requestUrl.pathname === "/auth/discord") {
      if (!auth.enabled) {
        sendJson(response, 503, { error: "La connexion Discord n'est pas configurée sur ce serveur." });
        return;
      }
      const state = crypto.randomBytes(24).toString("base64url");
      const secure = secureCookie(request) ? "; Secure" : "";
      const authorizeUrl = new URL("https://discord.com/oauth2/authorize");
      authorizeUrl.search = new URLSearchParams({
        client_id: auth.clientId,
        response_type: "code",
        redirect_uri: auth.redirectUri,
        scope: "identify",
        state,
      }).toString();
      redirect(response, authorizeUrl.toString(), [
        `${OAUTH_STATE_COOKIE}=${state}; Path=/auth/discord/callback; HttpOnly; SameSite=Lax; Max-Age=600${secure}`,
      ]);
      return;
    }

    if (requestUrl.pathname === "/auth/discord/callback") {
      const cookies = parseCookies(request.headers.cookie);
      const state = requestUrl.searchParams.get("state") || "";
      const expectedState = cookies[OAUTH_STATE_COOKIE] || "";
      const code = requestUrl.searchParams.get("code") || "";
      const stateMatches = state.length === expectedState.length
        && state.length > 0
        && crypto.timingSafeEqual(Buffer.from(state), Buffer.from(expectedState));
      const secure = secureCookie(request) ? "; Secure" : "";
      const clearState = `${OAUTH_STATE_COOKIE}=; Path=/auth/discord/callback; HttpOnly; SameSite=Lax; Max-Age=0${secure}`;
      if (!auth.enabled || !code || !stateMatches || typeof fetchImpl !== "function") {
        redirect(response, "/?discord=error", [clearState]);
        return;
      }
      try {
        const { user } = await fetchDiscordIdentityFromCode(code, true);
        const session = createAuthSession(user, auth.sessionSecret);
        recordAnalytics("discord_login_success", { provider: "discord" });
        redirect(response, "/?discord=connected", [
          clearState,
          authSessionCookieHeader(request, session),
        ]);
      } catch {
        redirect(response, "/?discord=error", [clearState]);
      }
      return;
    }

    if (await proxyDiscordAvatar(requestUrl, response)) return;

    if (requestUrl.pathname === "/analytics" || requestUrl.pathname === "/analytics/") {
      serveStaticFile(
        analyticsWebRoot,
        "index.html",
        response,
        "Dashboard analytics absent. Ajoutez les fichiers dans analytics-dashboard/.",
      );
      return;
    }

    if (requestUrl.pathname.startsWith("/analytics/")) {
      serveStaticFile(
        analyticsWebRoot,
        requestUrl.pathname.slice("/analytics/".length),
        response,
        "Fichier analytics introuvable.",
      );
      return;
    }

    const publicPages = {
      "/privacy": "privacy.html",
      "/privacy/": "privacy.html",
      "/terms": "terms.html",
      "/terms/": "terms.html",
    };
    const relativePath = requestUrl.pathname === "/"
      ? "index.html"
      : (publicPages[requestUrl.pathname] || requestUrl.pathname.slice(1));
    serveStaticFile(
      webRoot,
      relativePath,
      response,
      "Export Godot absent. Placez les fichiers HTML5 dans le dossier web/.",
    );
  }

  const httpServer = http.createServer((request, response) => {
    handleHttpRequest(request, response).catch(() => {
      if (!response.headersSent) sendJson(response, 500, { error: "Erreur interne du serveur." });
      else response.end();
    });
  });

  const sockets = new Map();
  const webSocketServer = new WebSocketServer({ server: httpServer, path: "/ws" });

  function send(socket, payload) {
    if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(payload));
  }

  function broadcast(room, payload) {
    for (const player of room.players.values()) send(player.socket, payload);
  }

  function leaveRoom(socket) {
    if (!socket.roomCode) return;
    const room = rooms.get(socket.roomCode);
    socket.roomCode = null;
    if (!room) return;
    room.players.delete(socket.id);
    if (!room.players.size) {
      rooms.delete(room.code);
      return;
    }
    if (room.hostId === socket.id) room.hostId = room.players.keys().next().value;
    updateRoomCompletion(room);
    broadcast(room, stateMessage(room));
  }

  function addPlayer(room, socket, requestedName, activityUser = null) {
    const start = room.maze.start;
    const discordUser = socket.discordUser;
    const displayUser = discordUser || activityUser;
    const player = {
      id: socket.id,
      socket,
      name: displayUser
        ? sanitizeName(displayUser.displayName || displayUser.username, room.players.size + 1)
        : sanitizeName(requestedName, room.players.size + 1),
      color: COLORS[room.players.size % COLORS.length],
      discordUserId: discordUser?.id || "",
      discordActivityUserId: discordUser ? "" : (activityUser?.id || ""),
      avatarUrl: discordAvatarUrl(displayUser),
      x: start.x,
      y: start.y,
      lastMoveAt: 0,
      finishedAt: 0,
      timeMs: 0,
      rank: 0,
      speedUntil: 0,
      slowUntil: 0,
      confusedUntil: 0,
      frozenUntil: 0,
      shield: false,
    };
    room.players.set(socket.id, player);
    socket.roomCode = room.code;
    return player;
  }

  function handleMessage(socket, raw) {
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch {
      send(socket, { type: "error", message: "Message JSON invalide." });
      return;
    }

    if (message.type === "create") {
      leaveRoom(socket);
      const code = createRoomCode(rooms);
      const maze = generateScaledMaze(DEFAULT_MAZE_SCALE);
      const room = {
        code,
        hostId: socket.id,
        maze,
        players: new Map(),
        winner: "",
        complete: false,
        finishCount: 0,
        phase: "waiting",
        startAt: 0,
        round: 1,
        mazeScale: DEFAULT_MAZE_SCALE,
        powerUpCount: DEFAULT_POWER_UP_COUNT,
        powerUps: createConfiguredPowerUps(maze, DEFAULT_POWER_UP_COUNT),
        lastEvent: null,
        standings: new Map(),
        history: [],
        podium: [],
      };
      rooms.set(code, room);
      addPlayer(room, socket, message.name, discordActivityUserFromMessage(message));
      recordAnalytics("room_created", {
        players: room.players.size,
        mazeScale: room.mazeScale,
      }, roomAnalyticsSession(room));
      broadcast(room, roomMessage(room));
      return;
    }

    if (message.type === "join") {
      const code = String(message.room || "").trim().toUpperCase();
      const room = rooms.get(code);
      if (!room) {
        send(socket, { type: "error", message: "Ce salon n’existe pas ou a expiré." });
        return;
      }
      if (room.players.size >= MAX_PLAYERS) {
        send(socket, { type: "error", message: "Ce salon est complet." });
        return;
      }
      if (room.phase !== "waiting") {
        send(socket, { type: "error", message: "Cette course a déjà démarré." });
        return;
      }
      leaveRoom(socket);
      addPlayer(room, socket, message.name, discordActivityUserFromMessage(message));
      recordAnalytics("room_joined", {
        players: room.players.size,
        mazeScale: room.mazeScale,
      }, roomAnalyticsSession(room));
      broadcast(room, roomMessage(room));
      return;
    }

    const room = rooms.get(socket.roomCode);
    const player = room?.players.get(socket.id);
    if (!room || !player) {
      send(socket, { type: "error", message: "Rejoignez d’abord un salon." });
      return;
    }

    if (message.type === "move") {
      const wasComplete = room.complete;
      if (applyMove(room, player, String(message.direction || ""))) {
        if (!wasComplete && room.complete) {
          const slowestTimeMs = Math.max(...[...room.players.values()].map((entry) => entry.timeMs || 0));
          recordAnalytics("race_completed", {
            players: room.players.size,
            mazeScale: room.mazeScale,
            durationMs: slowestTimeMs,
            round: room.round,
          }, roomAnalyticsSession(room));
        }
        broadcast(room, stateMessage(room));
      }
      return;
    }

    if (message.type === "chat") {
      const now = Date.now();
      const text = sanitizeChatText(message.text);
      if (!text || now - player.lastChatAt < CHAT_COOLDOWN_MS) return;
      player.lastChatAt = now;
      const chatMessage = {
        type: "chat",
        id: crypto.randomUUID(),
        playerId: player.id,
        name: player.name,
        color: player.color,
        text,
        sentAt: now,
      };
      room.chat.push(chatMessage);
      room.chat = room.chat.slice(-CHAT_HISTORY_LIMIT);
      recordAnalytics("chat_sent", {
        players: room.players.size,
        mazeScale: room.mazeScale,
      }, roomAnalyticsSession(room));
      broadcast(room, chatMessage);
      return;
    }

    if (message.type === "start") {
      if (room.hostId !== socket.id) {
        send(socket, { type: "error", message: "Seul l’hôte peut lancer le départ." });
        return;
      }
      if (room.phase !== "waiting") return;
      room.phase = "countdown";
      room.startAt = Date.now() + COUNTDOWN_MS;
      room.lastEvent = null;
      recordAnalytics("race_started", {
        players: room.players.size,
        mazeScale: room.mazeScale,
        round: room.round,
      }, roomAnalyticsSession(room));
      broadcast(room, stateMessage(room));
      return;
    }

    if (message.type === "maze_size") {
      if (room.hostId !== socket.id || room.phase !== "waiting") return;
      const nextScale = normalizeMazeScale(message.scale);
      if (nextScale === room.mazeScale) return;
      room.mazeScale = nextScale;
      prepareRoomMaze(room, generateScaledMaze(nextScale));
      recordAnalytics("maze_resized", {
        players: room.players.size,
        mazeScale: room.mazeScale,
      }, roomAnalyticsSession(room));
      broadcast(room, roomMessage(room));
      return;
    }

    if (message.type === "power_up_count") {
      if (room.hostId !== socket.id || room.phase !== "waiting") return;
      const nextCount = normalizePowerUpCount(message.count);
      if (nextCount === room.powerUpCount) return;
      room.powerUpCount = nextCount;
      room.powerUps = createConfiguredPowerUps(room.maze, room.powerUpCount);
      room.lastEvent = null;
      recordAnalytics("power_up_count_changed", {
        players: room.players.size,
        mazeScale: room.mazeScale,
        powerUpCount: room.powerUpCount,
      }, roomAnalyticsSession(room));
      broadcast(room, roomMessage(room));
      return;
    }

    if (message.type === "restart") {
      if (room.hostId !== socket.id) {
        send(socket, { type: "error", message: "Seul le créateur du salon peut relancer." });
        return;
      }
      resetRoom(room);
      recordAnalytics("race_restarted", {
        players: room.players.size,
        mazeScale: room.mazeScale,
        round: room.round,
      }, roomAnalyticsSession(room));
      broadcast(room, roomMessage(room));
    }
  }

  webSocketServer.on("connection", (socket, request) => {
    socket.id = crypto.randomUUID();
    socket.roomCode = null;
    socket.discordUser = sessionUser(request, new URL(request.url, sameOriginBaseUrl(request)));
    sockets.set(socket.id, socket);
    recordAnalytics("socket_connected", { discord: Boolean(socket.discordUser) });
    send(socket, { type: "hello", playerId: socket.id });
    socket.on("message", (raw) => handleMessage(socket, raw));
    socket.on("close", () => {
      leaveRoom(socket);
      sockets.delete(socket.id);
    });
    socket.on("error", () => {});
  });

  return {
    rooms,
    analyticsStore: analytics.store,
    async start(port = 8080, host = "0.0.0.0") {
      await new Promise((resolve, reject) => {
        httpServer.once("error", reject);
        httpServer.listen(port, host, resolve);
      });
      return httpServer.address();
    },
    async close() {
      for (const socket of sockets.values()) socket.terminate();
      await new Promise((resolve) => webSocketServer.close(resolve));
      if (httpServer.listening) await new Promise((resolve) => httpServer.close(resolve));
    },
  };
}

if (require.main === module) {
  const port = Number(process.env.PORT || 8080);
  const gameServer = createGameServer();
  gameServer.start(port).then(() => {
    console.log(`A Maze Inc. écoute sur http://localhost:${port}`);
  });
}

module.exports = {
  Wall,
  MAX_PLAYERS,
  DEFAULT_POWER_UP_COUNT,
  MAX_POWER_UP_COUNT,
  generateMaze,
  createPowerUps,
  createConfiguredPowerUps,
  powerUpCountForMaze,
  canMove,
  applyPowerUp,
  applyMove,
  resetRoom,
  createAuthSession,
  readAuthSession,
  discordAvatarUrl,
  createGameServer,
};
