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

const DIRECTIONS = {
  up: { dx: 0, dy: -1, wall: WALL_TOP },
  right: { dx: 1, dy: 0, wall: WALL_RIGHT },
  down: { dx: 0, dy: 1, wall: WALL_BOTTOM },
  left: { dx: -1, dy: 0, wall: WALL_LEFT },
};

function generateMaze(width = 19, height = 13, random = Math.random) {
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

function publicPlayer(player) {
  return {
    id: player.id,
    name: player.name,
    color: player.color,
    x: player.x,
    y: player.y,
    finished: Boolean(player.finishedAt),
    timeMs: player.timeMs || 0,
    rank: player.rank || 0,
  };
}

function roomMessage(room) {
  return {
    type: "room",
    room: room.code,
    host: room.hostId,
    maze: room.maze,
    players: [...room.players.values()].map(publicPlayer),
    winner: room.winner || "",
    complete: Boolean(room.complete),
  };
}

function stateMessage(room) {
  return {
    type: "state",
    host: room.hostId,
    players: [...room.players.values()].map(publicPlayer),
    winner: room.winner || "",
    complete: Boolean(room.complete),
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

function updateRoomCompletion(room) {
  room.complete = room.players.size > 0 && [...room.players.values()].every((player) => player.finishedAt);
}

function applyMove(room, player, directionName, now = Date.now()) {
  if (player.finishedAt || now - player.lastMoveAt < MOVE_COOLDOWN_MS) return false;
  if (!canMove(room.maze, player.x, player.y, directionName)) return false;
  const direction = DIRECTIONS[directionName];
  if (!player.startedAt) player.startedAt = now;
  player.x += direction.dx;
  player.y += direction.dy;
  player.lastMoveAt = now;
  if (player.x === room.maze.exit.x && player.y === room.maze.exit.y) {
    player.finishedAt = now;
    player.timeMs = Math.max(0, player.finishedAt - player.startedAt);
    room.finishCount += 1;
    player.rank = room.finishCount;
    if (!room.winner) room.winner = player.id;
    updateRoomCompletion(room);
  }
  return true;
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
      startedAt: 0,
      finishedAt: 0,
      timeMs: 0,
      rank: 0,
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
      const room = {
        code,
        hostId: socket.id,
        maze: generateMaze(),
        players: new Map(),
        winner: "",
        complete: false,
        finishCount: 0,
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
      if (room.complete) {
        send(socket, { type: "error", message: "Cette course est déjà terminée." });
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

    if (message.type === "restart") {
      if (room.hostId !== socket.id) {
        send(socket, { type: "error", message: "Seul le créateur du salon peut relancer." });
        return;
      }
      room.maze = generateMaze();
      room.winner = "";
      room.complete = false;
      room.finishCount = 0;
      for (const currentPlayer of room.players.values()) {
        currentPlayer.x = room.maze.start.x;
        currentPlayer.y = room.maze.start.y;
        currentPlayer.lastMoveAt = 0;
        currentPlayer.startedAt = 0;
        currentPlayer.finishedAt = 0;
        currentPlayer.timeMs = 0;
        currentPlayer.rank = 0;
      }
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
  canMove,
  applyMove,
  createGameServer,
};
