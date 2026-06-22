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
  createPowerUps,
  canMove,
  applyPowerUp,
  sanitizeChatText,
  applyMove,
  resetRoom,
  createAuthSession,
  readAuthSession,
  discordAvatarUrl,
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

function connect(url, options = {}) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url, options);
    // Le serveur envoie `hello` immédiatement : on installe l’écouteur avant
    // l’événement open pour ne pas perdre ce premier paquet très rapide.
    const hello = waitForMessage(socket, "hello");
    socket.once("open", () => resolve({ socket, hello }));
    socket.once("error", reject);
  });
}

test("les sessions Discord sont signées, expirent et produisent une URL d'avatar sûre", () => {
  const now = 1_000_000;
  const user = {
    id: "123456789012345678",
    username: "maze_user",
    global_name: "Maze Runner",
    avatar: "a_012345abcdef",
  };
  const session = createAuthSession(user, "test-secret", now);
  assert.equal(readAuthSession(session, "test-secret", now).displayName, "Maze Runner");
  assert.equal(readAuthSession(`${session}x`, "test-secret", now), null);
  assert.equal(readAuthSession(session, "test-secret", now + 8 * 24 * 60 * 60 * 1000), null);
  assert.equal(
    discordAvatarUrl(readAuthSession(session, "test-secret", now)),
    "/api/discord/avatar/123456789012345678/a_012345abcdef.png",
  );
});

test("un WebSocket authentifié utilise le nom et l'avatar Discord", async (context) => {
  const sessionSecret = "websocket-test-secret";
  const session = createAuthSession({
    id: "123456789012345678",
    username: "discord_name",
    global_name: "Profil Discord",
    avatar: "abcdef123456",
  }, sessionSecret);
  const server = createGameServer({ discordConfig: { sessionSecret } });
  const address = await server.start(0, "127.0.0.1");
  context.after(() => server.close());
  const connection = await connect(`ws://127.0.0.1:${address.port}/ws`, {
    headers: { Cookie: `maze_discord_session=${session}` },
  });
  context.after(() => connection.socket.terminate());
  await connection.hello;
  const roomMessage = waitForMessage(connection.socket, "room");
  connection.socket.send(JSON.stringify({ type: "create", name: "Nom usurpé" }));
  const room = await roomMessage;
  assert.equal(room.players[0].name, "Profil Discord");
  assert.equal(room.players[0].discord, true);
  assert.equal(
    room.players[0].avatarUrl,
    "/api/discord/avatar/123456789012345678/abcdef123456.png",
  );
});

test("le callback OAuth Discord crée une session HTTP utilisable par le jeu", async (context) => {
  const discordConfig = {
    clientId: "client-id",
    clientSecret: "client-secret",
    redirectUri: "http://127.0.0.1/auth/discord/callback",
    sessionSecret: "oauth-test-secret",
  };
  const fetchImpl = async (url) => {
    if (String(url).endsWith("/oauth2/token")) {
      return new Response(JSON.stringify({ access_token: "discord-access-token" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({
      id: "987654321098765432",
      username: "oauth_user",
      global_name: "OAuth Runner",
      avatar: null,
      default_avatar: "3",
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  const server = createGameServer({ discordConfig, fetchImpl });
  const address = await server.start(0, "127.0.0.1");
  context.after(() => server.close());
  const origin = `http://127.0.0.1:${address.port}`;

  const login = await fetch(`${origin}/auth/discord`, { redirect: "manual" });
  assert.equal(login.status, 302);
  const authorizeUrl = new URL(login.headers.get("location"));
  const state = authorizeUrl.searchParams.get("state");
  const stateCookie = login.headers.get("set-cookie").split(";")[0];
  const callback = await fetch(`${origin}/auth/discord/callback?code=test-code&state=${state}`, {
    redirect: "manual",
    headers: { Cookie: stateCookie },
  });
  assert.equal(callback.status, 302);
  assert.equal(callback.headers.get("location"), "/?discord=connected");
  const sessionMatch = callback.headers.get("set-cookie").match(/maze_discord_session=([^;,]+)/);
  assert.ok(sessionMatch);

  const profile = await fetch(`${origin}/api/auth/me`, {
    headers: { Cookie: `maze_discord_session=${sessionMatch[1]}` },
  });
  const payload = await profile.json();
  assert.equal(payload.authenticated, true);
  assert.equal(payload.user.displayName, "OAuth Runner");
  assert.equal(payload.user.avatarUrl, "/api/discord/avatar/default/3.png");
});

test("le labyrinthe par défaut mesure 38 par 26 cellules", () => {
  const maze = generateMaze();
  assert.equal(maze.width, 38);
  assert.equal(maze.height, 26);
  assert.equal(maze.cells.length, 38 * 26);
});

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
  const first = { id: "first", name: "Bleu", color: "#45d9ff", x: 0, y: 0, lastMoveAt: 0, finishedAt: 0, timeMs: 0, rank: 0 };
  const second = { id: "second", name: "Rose", color: "#ff5c8a", x: 0, y: 0, lastMoveAt: 0, finishedAt: 0, timeMs: 0, rank: 0 };
  const room = {
    maze,
    players: new Map([[first.id, first], [second.id, second]]),
    winner: "",
    complete: false,
    finishCount: 0,
    phase: "running",
    startAt: 100,
    powerUps: [],
    round: 1,
    standings: new Map(),
    history: [],
    podium: [],
    bestRun: null,
  };

  assert.equal(applyMove(room, first, "right", 100), true);
  assert.equal(applyMove(room, first, "right", 200), true);
  assert.equal(first.timeMs, 100);
  assert.equal(first.rank, 1);
  assert.equal(room.winner, first.id);
  assert.equal(room.complete, false);

  assert.equal(applyMove(room, second, "right", 150), true);
  assert.equal(applyMove(room, second, "right", 270), true);
  assert.equal(second.timeMs, 170);
  assert.equal(second.rank, 2);
  assert.equal(room.complete, true);
  assert.equal(room.phase, "complete");
  assert.deepEqual(room.podium.map(({ name, points }) => ({ name, points })), [
    { name: "Bleu", points: 10 },
    { name: "Rose", points: 7 },
  ]);
  assert.equal(room.bestRun.name, "Bleu");
  assert.equal(room.bestRun.timeMs, 100);
  assert.deepEqual(room.bestRun.path.map(({ x, y, t }) => ({ x, y, t })), [
    { x: 0, y: 0, t: 0 },
    { x: 1, y: 0, t: 0 },
    { x: 2, y: 0, t: 100 },
  ]);

  resetRoom(room, maze);
  room.phase = "running";
  room.startAt = 1000;
  assert.equal(applyMove(room, second, "right", 1000), true);
  assert.equal(applyMove(room, second, "right", 1100), true);
  assert.equal(applyMove(room, first, "right", 1050), true);
  assert.equal(applyMove(room, first, "right", 1200), true);
  assert.equal(room.history.length, 2);
  assert.deepEqual(room.podium.map(({ name, points }) => ({ name, points })), [
    { name: "Rose", points: 17 },
    { name: "Bleu", points: 17 },
  ]);
  assert.equal(room.bestRun.name, "Bleu");
});

test("les objets mystère sont uniques et appliquent bonus ou malus", () => {
  const maze = generateMaze(9, 7, () => 0.42);
  const powerUps = createPowerUps(maze, 8, () => 0.42);
  assert.equal(powerUps.length, 8);
  assert.equal(new Set(powerUps.map(({ x, y }) => `${x},${y}`)).size, 8);
  assert.equal(powerUps.some(({ x, y }) => x === maze.start.x && y === maze.start.y), false);

  const actor = { id: "actor", name: "Bleu", x: 4, y: 3, finishedAt: 0, speedUntil: 0, shield: false };
  const target = { id: "target", name: "Rose", finishedAt: 0, slowUntil: 0, shield: false };
  const room = {
    players: new Map([[actor.id, actor], [target.id, target]]),
    powerUps: [{ id: "power-1", x: 4, y: 3, active: true, respawnAt: 0 }],
    lastEvent: null,
  };
  const event = applyPowerUp(room, actor, 1000, () => 0.41);
  assert.equal(event.kind, "slow_all");
  assert.equal(target.slowUntil, 5500);
  assert.equal(room.powerUps[0].active, false);
});

test("le nombre de power-ups suit la surface du labyrinthe", () => {
  const random = () => 0.42;
  assert.equal(createPowerUps(generateMaze(19, 13), null, random).length, 3);
  assert.equal(createPowerUps(generateMaze(38, 26), null, random).length, 10);
  assert.equal(createPowerUps(generateMaze(62, 42), null, random).length, 26);
});

test("le serveur bloque tout mouvement avant le départ synchronisé", () => {
  const maze = {
    width: 3,
    height: 1,
    cells: [WALL_TOP | WALL_BOTTOM | WALL_LEFT, WALL_TOP | WALL_BOTTOM, WALL_TOP | WALL_RIGHT | WALL_BOTTOM],
    start: { x: 0, y: 0 },
    exit: { x: 2, y: 0 },
  };
  const player = { id: "host", x: 0, y: 0, lastMoveAt: 0, finishedAt: 0, frozenUntil: 0 };
  const room = {
    maze,
    players: new Map([[player.id, player]]),
    phase: "countdown",
    startAt: 1000,
    powerUps: [],
  };
  assert.equal(applyMove(room, player, "right", 999), false);
  assert.equal(player.x, 0);
  assert.equal(applyMove(room, player, "right", 1000), true);
  assert.equal(player.x, 1);
  assert.equal(room.phase, "running");
});

test("les messages du chat sont nettoyés et limités", () => {
  assert.equal(sanitizeChatText("  Salut\nà tous\u0000  "), "Salut à tous");
  assert.equal(sanitizeChatText({ text: "non" }), "");
  assert.equal(sanitizeChatText("a".repeat(300)).length, 240);
});

test("l’hôte relance tous les joueurs sans remplacer leurs connexions", () => {
  const originalSocket = {};
  const player = {
    id: "host",
    socket: originalSocket,
    x: 2,
    y: 0,
    lastMoveAt: 270,
    startedAt: 100,
    finishedAt: 270,
    timeMs: 170,
    rank: 1,
  };
  const room = {
    players: new Map([[player.id, player]]),
    winner: player.id,
    complete: true,
    finishCount: 1,
    round: 1,
  };
  const nextMaze = {
    width: 2,
    height: 1,
    cells: [WALL_TOP | WALL_BOTTOM | WALL_LEFT, WALL_TOP | WALL_RIGHT | WALL_BOTTOM],
    start: { x: 0, y: 0 },
    exit: { x: 1, y: 0 },
  };

  resetRoom(room, nextMaze);

  assert.equal(room.maze, nextMaze);
  assert.equal(room.complete, false);
  assert.equal(room.winner, "");
  assert.equal(room.finishCount, 0);
  assert.equal(player.socket, originalSocket);
  assert.deepEqual(
    { x: player.x, y: player.y, finishedAt: player.finishedAt, timeMs: player.timeMs, rank: player.rank },
    { x: 0, y: 0, finishedAt: 0, timeMs: 0, rank: 0 },
  );
  assert.equal(room.phase, "waiting");
  assert.equal(room.round, 2);
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
  assert.equal(created.phase, "waiting");
  assert.equal(created.mazeScale, 5);
  assert.equal(created.powerUps.length, 10);
  assert.equal(created.ghost.isDemo, true);
  assert.deepEqual(created.ghost.path[0], { x: 0, y: 0, t: 0 });
  assert.deepEqual(created.ghost.path.at(-1), {
    x: created.maze.exit.x,
    y: created.maze.exit.y,
    t: created.ghost.timeMs,
  });

  const firstUpdate = waitForMessage(first, "room");
  const secondRoom = waitForMessage(second, "room");
  second.send(JSON.stringify({ type: "join", room: created.room, name: "Rose" }));
  const [updated, joined] = await Promise.all([firstUpdate, secondRoom]);
  assert.equal(updated.players.length, 2);
  assert.equal(joined.room, created.room);
  assert.deepEqual(joined.maze, created.maze);

  const resizedForHost = waitForMessage(first, "room");
  const resizedForGuest = waitForMessage(second, "room");
  first.send(JSON.stringify({ type: "maze_size", scale: 10 }));
  const [hostResize, guestResize] = await Promise.all([resizedForHost, resizedForGuest]);
  assert.equal(hostResize.mazeScale, 10);
  assert.equal(hostResize.maze.width, 62);
  assert.equal(hostResize.maze.height, 42);
  assert.equal(hostResize.powerUps.length, 26);
  assert.deepEqual(guestResize.maze, hostResize.maze);
  second.send(JSON.stringify({ type: "maze_size", scale: 1 }));
  await new Promise((resolve) => setTimeout(resolve, 25));
  assert.equal(server.rooms.get(created.room).mazeScale, 10);

  const firstChat = waitForMessage(first, "chat");
  const secondChat = waitForMessage(second, "chat");
  second.send(JSON.stringify({ type: "chat", text: "  Salut\nà tous  " }));
  const [receivedByHost, receivedBySender] = await Promise.all([firstChat, secondChat]);
  assert.equal(receivedByHost.text, "Salut à tous");
  assert.equal(receivedByHost.name, "Rose");
  assert.equal(receivedBySender.id, receivedByHost.id);

  const thirdConnection = await connect(url);
  const third = thirdConnection.socket;
  context.after(() => third.terminate());
  await thirdConnection.hello;
  const thirdRoom = waitForMessage(third, "room");
  third.send(JSON.stringify({ type: "join", room: created.room, name: "Or" }));
  const joinedWithHistory = await thirdRoom;
  assert.equal(joinedWithHistory.players.length, 3);
  assert.deepEqual(joinedWithHistory.chat.map(({ text }) => text), ["Salut à tous"]);

  const countdownState = waitForMessage(first, "state");
  first.send(JSON.stringify({ type: "start" }));
  const countdown = await countdownState;
  assert.equal(countdown.phase, "countdown");
  assert.ok(countdown.startAt > countdown.serverNow);
});
