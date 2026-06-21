"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { WebSocket } = require("ws");
const {
  WALL_TOP,
  WALL_RIGHT,
  WALL_BOTTOM,
  WALL_LEFT,
  generateMaze,
  canMove,
  applyMove,
  createGameServer,
} = require("../server");

function waitForMessage(socket, expectedType) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Message ${expectedType} non reçu`)), 1500);
    function onMessage(raw) {
      const message = JSON.parse(raw.toString());
      if (message.type !== expectedType) return;
      clearTimeout(timeout);
      socket.off("message", onMessage);
      resolve(message);
    }
    socket.on("message", onMessage);
  });
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    // Le serveur envoie `hello` immédiatement : on installe l’écouteur avant
    // l’événement open pour ne pas perdre ce premier paquet très rapide.
    const hello = waitForMessage(socket, "hello");
    socket.once("open", () => resolve({ socket, hello }));
    socket.once("error", reject);
  });
}

test("le générateur produit des murs cohérents et un labyrinthe entièrement accessible", () => {
  const maze = generateMaze(19, 13);
  const visited = new Set(["0,0"]);
  const queue = [{ x: 0, y: 0 }];
  const directions = [
    ["up", 0, -1, WALL_TOP, WALL_BOTTOM],
    ["right", 1, 0, WALL_RIGHT, WALL_LEFT],
    ["down", 0, 1, WALL_BOTTOM, WALL_TOP],
    ["left", -1, 0, WALL_LEFT, WALL_RIGHT],
  ];

  while (queue.length) {
    const current = queue.shift();
    for (const [name, dx, dy, wall, opposite] of directions) {
      const nx = current.x + dx;
      const ny = current.y + dy;
      if (nx < 0 || nx >= maze.width || ny < 0 || ny >= maze.height) continue;
      const isOpen = canMove(maze, current.x, current.y, name);
      const neighborHasWall = (maze.cells[ny * maze.width + nx] & opposite) !== 0;
      assert.equal(isOpen, !neighborHasWall, `mur asymétrique en ${current.x},${current.y}`);
      if (!isOpen || visited.has(`${nx},${ny}`)) continue;
      visited.add(`${nx},${ny}`);
      queue.push({ x: nx, y: ny });
    }
  }

  assert.equal(visited.size, maze.width * maze.height);
});

test("chaque joueur est chronométré jusqu’à ce que tout le salon termine", () => {
  const maze = {
    width: 3,
    height: 1,
    cells: [WALL_TOP | WALL_BOTTOM | WALL_LEFT, WALL_TOP | WALL_BOTTOM, WALL_TOP | WALL_RIGHT | WALL_BOTTOM],
    start: { x: 0, y: 0 },
    exit: { x: 2, y: 0 },
  };
  const first = { id: "first", x: 0, y: 0, lastMoveAt: 0, startedAt: 0, finishedAt: 0, timeMs: 0, rank: 0 };
  const second = { id: "second", x: 0, y: 0, lastMoveAt: 0, startedAt: 0, finishedAt: 0, timeMs: 0, rank: 0 };
  const room = {
    maze,
    players: new Map([[first.id, first], [second.id, second]]),
    winner: "",
    complete: false,
    finishCount: 0,
  };

  assert.equal(applyMove(room, first, "right", 100), true);
  assert.equal(applyMove(room, first, "right", 200), true);
  assert.equal(first.timeMs, 100);
  assert.equal(first.rank, 1);
  assert.equal(room.winner, first.id);
  assert.equal(room.complete, false);

  assert.equal(applyMove(room, second, "right", 150), true);
  assert.equal(applyMove(room, second, "right", 270), true);
  assert.equal(second.timeMs, 120);
  assert.equal(second.rank, 2);
  assert.equal(room.complete, true);
});

test("deux clients peuvent créer et rejoindre le même salon", async (context) => {
  const server = createGameServer();
  const address = await server.start(0, "127.0.0.1");
  context.after(() => server.close());
  const url = `ws://127.0.0.1:${address.port}/ws`;
  const firstConnection = await connect(url);
  const secondConnection = await connect(url);
  const first = firstConnection.socket;
  const second = secondConnection.socket;
  context.after(() => first.terminate());
  context.after(() => second.terminate());
  await Promise.all([firstConnection.hello, secondConnection.hello]);

  const firstRoom = waitForMessage(first, "room");
  first.send(JSON.stringify({ type: "create", name: "Bleu" }));
  const created = await firstRoom;
  assert.match(created.room, /^[A-Z2-9]{4}$/);
  assert.equal(created.players.length, 1);

  const firstUpdate = waitForMessage(first, "room");
  const secondRoom = waitForMessage(second, "room");
  second.send(JSON.stringify({ type: "join", room: created.room, name: "Rose" }));
  const [updated, joined] = await Promise.all([firstUpdate, secondRoom]);
  assert.equal(updated.players.length, 2);
  assert.equal(joined.room, created.room);
  assert.deepEqual(joined.maze, created.maze);
});
