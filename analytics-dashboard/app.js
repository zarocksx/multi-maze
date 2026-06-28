const tokenForm = document.getElementById("token-form");
const tokenInput = document.getElementById("token-input");
const overviewGrid = document.getElementById("overview-grid");
const dailyChart = document.getElementById("daily-chart");
const concurrentChart = document.getElementById("concurrent-chart");
const joinFailureList = document.getElementById("join-failure-list");
const roomClosureList = document.getElementById("room-closure-list");
const mazeScaleChart = document.getElementById("maze-scale-chart");
const powerUpCountChart = document.getElementById("power-up-count-chart");
const roomSizeChart = document.getElementById("room-size-chart");
const parameterList = document.getElementById("parameter-list");
const consentList = document.getElementById("consent-list");
const pageList = document.getElementById("page-list");
const generatedAt = document.getElementById("generated-at");
const metricTemplate = document.getElementById("metric-template");

const STORAGE_KEY = "maze.analytics.dashboard.token";

function formatNumber(value) {
  return new Intl.NumberFormat("fr-FR").format(Number(value || 0));
}

function formatDuration(ms) {
  if (!ms) return "0 s";
  if (ms < 60_000) return `${Math.round(ms / 1000)} s`;
  const minutes = Math.floor(ms / 60_000);
  const seconds = Math.round((ms % 60_000) / 1000);
  return `${minutes} min ${seconds}s`;
}

function formatPercent(value) {
  return new Intl.NumberFormat("fr-FR", {
    style: "percent",
    maximumFractionDigits: 1,
  }).format(Number(value || 0));
}

function formatBucket(value) {
  return new Date(value).toLocaleString("fr-FR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function setEmpty(container, text) {
  container.innerHTML = `<div class="empty">${text}</div>`;
}

function renderMetrics(summary) {
  overviewGrid.innerHTML = "";
  const metrics = [
    ["Sessions consenties", summary.overview.uniqueConsentedSessions, `${summary.retentionDays} jours de rétention`],
    ["Pages vues", summary.overview.pageViews, "Seulement après consentement"],
    ["Salons créés", summary.overview.roomsCreated, "Créations de rooms"],
    ["Courses terminées", summary.overview.raceCompletions, "Rounds complets"],
    ["Départs", summary.overview.raceStarts, "Courses lancées"],
    ["Messages chat", summary.overview.chatMessages, "Messages de salon"],
    ["Joueurs rejoints", summary.overview.roomJoins, "Entrées dans des salons"],
    ["Durée moyenne", formatDuration(summary.overview.averageRaceDurationMs), "Sur les courses complètes"],
    ["Pic concurrents", summary.overview.peakConcurrentPlayers10m, "Par tranche de 10 minutes"],
    ["Taux de depart", formatPercent(summary.funnel?.startRate), "Courses lancees / salons crees"],
    ["Taux completion", formatPercent(summary.funnel?.completionRate), "Courses terminees / departs"],
    ["Echecs join", formatPercent(summary.funnel?.joinFailureRate), "Tentatives de join ratees"],
    ["Lobby moyen", formatDuration(summary.overview.averageLobbyDurationMs), "Avant lancement"],
    ["Relances", summary.overview.raceRestarts, "Manches relancees"],
    ["Rounds / salon", summary.overview.averageRoundsPerClosedRoom, "Sur salons fermes"],
  ];
  for (const [label, value, meta] of metrics) {
    const node = metricTemplate.content.firstElementChild.cloneNode(true);
    node.querySelector(".metric-label").textContent = label;
    node.querySelector(".metric-value").textContent = typeof value === "number" ? formatNumber(value) : value;
    node.querySelector(".metric-meta").textContent = meta;
    overviewGrid.appendChild(node);
  }
}

function renderBars(container, rows, labelKey, valueKey, emptyMessage) {
  if (!rows.length) {
    setEmpty(container, emptyMessage);
    return;
  }
  const max = Math.max(...rows.map((row) => Number(row[valueKey] || 0)), 1);
  container.innerHTML = "";
  for (const row of rows) {
    const value = Number(row[valueKey] || 0);
    const article = document.createElement("article");
    article.className = "chart-row";
    article.innerHTML = `
      <div class="chart-meta">
        <span class="chart-label"></span>
        <div class="chart-bar"><div class="chart-fill"></div></div>
        <span class="chart-value"></span>
      </div>
    `;
    article.querySelector(".chart-label").textContent = row[labelKey];
    article.querySelector(".chart-value").textContent = formatNumber(value);
    article.querySelector(".chart-fill").style.width = `${(value / max) * 100}%`;
    container.appendChild(article);
  }
}

function renderList(container, rows, labelKey, valueKey, emptyMessage) {
  if (!rows.length) {
    setEmpty(container, emptyMessage);
    return;
  }
  container.innerHTML = "";
  for (const row of rows) {
    const article = document.createElement("article");
    article.className = "data-row";
    article.innerHTML = `
      <span class="data-label"></span>
      <span></span>
      <strong class="data-value"></strong>
    `;
    article.querySelector(".data-label").textContent = row[labelKey];
    article.querySelector(".data-value").textContent = formatNumber(row[valueKey]);
    container.appendChild(article);
  }
}

function parameterLabel(parameter) {
  if (parameter === "mazeScale") return "Taille labyrinthe";
  if (parameter === "powerUpCount") return "Power-ups";
  if (parameter === "players") return "Joueurs";
  return parameter;
}

function renderParameterUsage(container, rows) {
  if (!rows.length) {
    setEmpty(container, "Aucun parametre de partie enregistre.");
    return;
  }
  container.innerHTML = "";
  for (const row of rows) {
    const article = document.createElement("article");
    article.className = "data-row";
    article.innerHTML = `
      <span class="data-label"></span>
      <span class="data-note"></span>
      <strong class="data-value"></strong>
    `;
    article.querySelector(".data-label").textContent = `${parameterLabel(row.parameter)} = ${row.value}`;
    article.querySelector(".data-note").textContent = `${formatNumber(row.count)} partie${row.count > 1 ? "s" : ""}`;
    article.querySelector(".data-value").textContent = formatPercent(row.percent);
    container.appendChild(article);
  }
}

function renderJoinFailures(container, rows) {
  renderList(
    container,
    rows.map((row) => ({ label: row.reason, count: row.count })),
    "label",
    "count",
    "Aucun echec de join enregistre."
  );
}

function renderRoomClosures(container, rows) {
  renderList(
    container,
    rows.map((row) => ({ label: `${row.phase} / ${row.reason}`, count: row.count })),
    "label",
    "count",
    "Aucune fermeture de salon enregistree."
  );
}

async function loadSummary() {
  const token = localStorage.getItem(STORAGE_KEY) || "";
  tokenInput.value = token;
  const headers = token ? { "x-analytics-token": token } : {};
  const response = await fetch("/api/analytics/summary?days=14", { headers });
  if (!response.ok) {
    throw new Error(response.status === 401
      ? "Token invalide ou absent pour le dashboard analytics."
      : "Impossible de charger les statistiques.");
  }
  const summary = await response.json();
  generatedAt.textContent = `Mis à jour : ${new Date(summary.generatedAt).toLocaleString("fr-FR")} • ${formatNumber(summary.storedEvents)} événements stockés`;
  renderMetrics(summary);
  renderBars(
    dailyChart,
    summary.daily.map((row) => ({
      day: row.day.slice(5),
      count: row.webSessions + row.roomsCreated + row.raceCompletions,
    })),
    "day",
    "count",
    "Aucune activité récente."
  );
  renderBars(
    concurrentChart,
    summary.concurrentPlayers10m
      .filter((row) => Number(row.players || 0) > 0)
      .slice(-24)
      .map((row) => ({ label: formatBucket(row.bucketStart), count: row.players })),
    "label",
    "count",
    "Aucun joueur concurrent mesure sur les derniers creneaux."
  );
  renderJoinFailures(joinFailureList, summary.joinFailures || []);
  renderRoomClosures(roomClosureList, summary.roomClosures || []);
  renderBars(
    mazeScaleChart,
    summary.mazeScales.map((row) => ({ label: `Échelle ${row.scale}`, count: row.count })),
    "label",
    "count",
    "Aucune donnée de taille de labyrinthe."
  );
  renderBars(
    powerUpCountChart,
    (summary.powerUpCounts || []).map((row) => ({ label: `${row.powerUpCount} power-ups`, count: row.count })),
    "label",
    "count",
    "Aucune donnee de power-ups."
  );
  renderParameterUsage(parameterList, summary.parameterUsage || []);
  renderBars(
    roomSizeChart,
    summary.roomSizes.map((row) => ({ label: `${row.players} joueur${row.players > 1 ? "s" : ""}`, count: row.count })),
    "label",
    "count",
    "Aucune donnée de taille de salon."
  );
  renderList(consentList, summary.consent, "choice", "count", "Aucun choix de consentement enregistré.");
  renderList(pageList, summary.topPages, "path", "count", "Aucune page mesurée pour l'instant.");
}

tokenForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  localStorage.setItem(STORAGE_KEY, tokenInput.value.trim());
  try {
    await loadSummary();
  } catch (error) {
    setEmpty(overviewGrid, error.message);
  }
});

loadSummary().catch((error) => {
  setEmpty(overviewGrid, error.message);
  setEmpty(concurrentChart, "Aucune donnee de concurrence a afficher.");
  setEmpty(joinFailureList, "Aucune friction de join a afficher.");
  setEmpty(roomClosureList, "Aucune fermeture de salon a afficher.");
  setEmpty(powerUpCountChart, "Aucune donnee de power-ups a afficher.");
  setEmpty(parameterList, "Aucun parametre de partie disponible.");
  setEmpty(dailyChart, "Le dashboard attend un accès autorisé pour afficher les tendances.");
  setEmpty(mazeScaleChart, "Aucune donnée à afficher.");
  setEmpty(roomSizeChart, "Aucune donnée à afficher.");
  setEmpty(consentList, "Aucun état de consentement disponible.");
  setEmpty(pageList, "Aucune page disponible.");
  generatedAt.textContent = "Accès non autorisé.";
});
