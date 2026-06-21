"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { WebSocketServer, WebSocket } = require("ws");

const WALL_TOP = 1;
const WALL_RIGHT = 2;
const WALL_BOTTOM = 4;
const WALL_LEFT = 8;
const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const COLORS = ["#45d9ff", "#ff5c8a", "#ffd166", "#79e36a", "#b58cff", "#ff914d", "#55efc4", "#f7aef8"];
const MAX_PLAYERS = 8;
const MOVE_COOLDOWN_MS = 55;
const COUNTDOWN_MS = 3500;
const POWER_UP_COUNT = 10;
const POWER_UP_RESPAWN_MS = 8000;
const RANK_POINTS = [10, 7, 5, 3, 2, 1, 1, 1];
const POWER_UP_KINDS = ["speed", "shield", "slow_all", "confuse_all", "freeze_all"];
const CHAT_MAX_LENGTH = 240;
const CHAT_HISTORY_LIMIT = 50;
const CHAT_COOLDOWN_MS = 350;
const MAZE_WIDTH = 38;
const MAZE_HEIGHT = 26;

const DIRECTIONS = {
  up: { dx: 0, dy: -1, wall: WALL_TOP },
  right: { dx: 1, dy: 0, wall: WALL_RIGHT },
  down: { dx: 0, dy: 1, wall: WALL_BOTTOM },
  left: { dx: -1, dy: 0, wall: WALL_LEFT },
};

function generateMaze(width = MAZE_WIDTH, height = MAZE_HEIGHT, random = Math.random) {
  const cells = new Array(width * height).fill(15);
  const visited = new Array(width * height).fill(false);
  const stack = [{ x: 0, y: 0 }];
  visited[0] = true;

  const carvingDirections = [
    { dx: 0, dy: -1, wall: WALL_TOP, opposite: WALL_BOTTOM },
    { dx: 1, dy: 0, wall: WALL_RIGHT, opposite: WALL_LEFT },
    { dx: 0, dy: 1, wall: WALL_BOTTOM, opposite: WALL_TOP },
    { dx: -1, dy: 0, wall: WALL_LEFT, opposite: WALL_RIGHT },
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
    if (x + 1 < width && (cells[y * width + x] & WALL_RIGHT)) {
      options.push({ dx: 1, dy: 0, wall: WALL_RIGHT, opposite: WALL_LEFT });
    }
    if (y + 1 < height && (cells[y * width + x] & WALL_BOTTOM)) {
      options.push({ dx: 0, dy: 1, wall: WALL_BOTTOM, opposite: WALL_TOP });
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

function createPowerUps(maze, count = POWER_UP_COUNT, random = Math.random) {
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
  return candidates.slice(0, Math.min(count, candidates.length)).map((position, index) => ({
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
    podium: room.podium,
    ghost: room.bestRun,
    chat: room.chat.slice(),
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
    podium: room.podium,
    ghost: room.bestRun,
  };
}

function sanitizeName(value, fallbackNumber) {
  const cleaned = String(value || "").replace(/[<>\u0000-\u001f]/g, "").trim().slice(0, 16);
  return cleaned || `Joueur ${fallbackNumber}`;
}

function sanitizeChatText(value) {
  if (typeof value !== "string") return "";
  return value.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, CHAT_MAX_LENGTH);
}

function canMove(maze, x, y, directionName) {
  const direction = DIRECTIONS[directionName];
  if (!direction) return false;
  const nextX = x + direction.dx;
  const nextY = y + direction.dy;
  if (nextX < 0 || nextX >= maze.width || nextY < 0 || nextY >= maze.height) return false;
  return (maze.cells[y * maze.width + x] & direction.wall) === 0;
}

function remapGhostToMaze(maze, ghost) {
  if (!ghost) return null;
  const startKey = `${maze.start.x},${maze.start.y}`;
  const exitKey = `${maze.exit.x},${maze.exit.y}`;
  const queue = [{ ...maze.start }];
  const parents = new Map([[startKey, null]]);

  while (queue.length && !parents.has(exitKey)) {
    const current = queue.shift();
    for (const directionName of Object.keys(DIRECTIONS)) {
      if (!canMove(maze, current.x, current.y, directionName)) continue;
      const direction = DIRECTIONS[directionName];
      const next = { x: current.x + direction.dx, y: current.y + direction.dy };
      const nextKey = `${next.x},${next.y}`;
      if (parents.has(nextKey)) continue;
      parents.set(nextKey, current);
      queue.push(next);
    }
  }

  const positions = [];
  let cursor = { ...maze.exit };
  while (cursor) {
    positions.push(cursor);
    cursor = parents.get(`${cursor.x},${cursor.y}`) || null;
  }
  positions.reverse();
  const denominator = Math.max(1, positions.length - 1);
  const requestedTimeMs = Number(ghost.timeMs) || 0;
  const timeMs = requestedTimeMs > 0 ? requestedTimeMs : Math.max(4000, denominator * 90);
  return {
    name: ghost.name,
    color: ghost.color,
    timeMs,
    isDemo: Boolean(ghost.isDemo),
    path: positions.map(({ x, y }, index) => ({
      x,
      y,
      t: Math.round(timeMs * index / denominator),
    })),
  };
}

function createDemoGhost(maze) {
  return remapGhostToMaze(maze, {
    name: "Ghost Runner",
    color: "#c7d8ff",
    isDemo: true,
  });
}

function recordRoundResults(room) {
  const results = [...room.players.values()]
    .filter((player) => player.finishedAt)
    .sort((first, second) => first.rank - second.rank);
  const roundWinner = results[0];
  if (roundWinner && (!room.bestRun || room.bestRun.isDemo || roundWinner.timeMs < room.bestRun.timeMs)) {
    room.bestRun = {
      name: roundWinner.name,
      color: roundWinner.color,
      timeMs: roundWinner.timeMs,
      path: roundWinner.runPath,
    };
  }
  for (const player of results) {
    const standing = room.standings.get(player.id) || {
      id: player.id,
      name: player.name,
      color: player.color,
      points: 0,
      wins: 0,
      races: 0,
      totalTimeMs: 0,
    };
    standing.name = player.name;
    standing.color = player.color;
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
    .map(({ id, name, color, points, wins, races }) => ({ id, name, color, points, wins, races }));
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
  if (!Array.isArray(player.runPath)) player.runPath = [{ x: room.maze.start.x, y: room.maze.start.y, t: 0 }];
  player.runPath.push({ x: player.x, y: player.y, t: Math.max(0, now - room.startAt) });
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

function resetRoom(room, nextMaze = generateMaze()) {
  room.maze = nextMaze;
  room.bestRun = remapGhostToMaze(room.maze, room.bestRun);
  room.winner = "";
  room.complete = false;
  room.finishCount = 0;
  room.phase = "waiting";
  room.startAt = 0;
  room.round = (room.round || 0) + 1;
  room.powerUps = createPowerUps(room.maze);
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
    player.runPath = [{ x: room.maze.start.x, y: room.maze.start.y, t: 0 }];
  }
}

function createGameServer({ webRoot = path.resolve(__dirname, "..", "web") } = {}) {
  const rooms = new Map();

  const httpServer = http.createServer((request, response) => {
    const requestUrl = new URL(request.url, "http://localhost");
    const relativePath = requestUrl.pathname === "/" ? "index.html" : requestUrl.pathname.slice(1);
    const normalizedPath = path.normalize(relativePath).replace(/^(\.\.[/\\])+/, "");
    const filePath = path.resolve(webRoot, normalizedPath);
    if (!filePath.startsWith(path.resolve(webRoot))) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    fs.readFile(filePath, (error, data) => {
      if (error) {
        response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
        response.end("Export Godot absent. Placez les fichiers HTML5 dans le dossier web/.");
        return;
      }
      const mime = {
        ".html": "text/html; charset=utf-8",
        ".js": "text/javascript; charset=utf-8",
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".png": "image/png",
        ".svg": "image/svg+xml",
        ".ico": "image/x-icon",
      }[path.extname(filePath)] || "application/octet-stream";
      response.writeHead(200, {
        "Content-Type": mime,
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Embedder-Policy": "require-corp",
      });
      response.end(data);
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

  function addPlayer(room, socket, requestedName) {
    const start = room.maze.start;
    const player = {
      id: socket.id,
      socket,
      name: sanitizeName(requestedName, room.players.size + 1),
      color: COLORS[room.players.size % COLORS.length],
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
      lastChatAt: 0,
      runPath: [{ x: start.x, y: start.y, t: 0 }],
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
      const maze = generateMaze();
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
        powerUps: createPowerUps(maze),
        lastEvent: null,
        standings: new Map(),
        history: [],
        podium: [],
        bestRun: createDemoGhost(maze),
        chat: [],
      };
      rooms.set(code, room);
      addPlayer(room, socket, message.name);
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
      addPlayer(room, socket, message.name);
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
      if (applyMove(room, player, String(message.direction || ""))) {
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
      broadcast(room, stateMessage(room));
      return;
    }

    if (message.type === "restart") {
      if (room.hostId !== socket.id) {
        send(socket, { type: "error", message: "Seul le créateur du salon peut relancer." });
        return;
      }
      resetRoom(room);
      broadcast(room, roomMessage(room));
    }
  }

  webSocketServer.on("connection", (socket) => {
    socket.id = crypto.randomUUID();
    socket.roomCode = null;
    sockets.set(socket.id, socket);
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
  WALL_TOP,
  WALL_RIGHT,
  WALL_BOTTOM,
  WALL_LEFT,
  generateMaze,
  createPowerUps,
  canMove,
  applyPowerUp,
  sanitizeChatText,
  applyMove,
  resetRoom,
  createGameServer,
};
