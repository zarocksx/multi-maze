const tokenForm = document.getElementById("token-form");
const tokenInput = document.getElementById("token-input");
const overviewGrid = document.getElementById("overview-grid");
const dailyChart = document.getElementById("daily-chart");
const mazeScaleChart = document.getElementById("maze-scale-chart");
const roomSizeChart = document.getElementById("room-size-chart");
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
    mazeScaleChart,
    summary.mazeScales.map((row) => ({ label: `Échelle ${row.scale}`, count: row.count })),
    "label",
    "count",
    "Aucune donnée de taille de labyrinthe."
  );
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
  setEmpty(dailyChart, "Le dashboard attend un accès autorisé pour afficher les tendances.");
  setEmpty(mazeScaleChart, "Aucune donnée à afficher.");
  setEmpty(roomSizeChart, "Aucune donnée à afficher.");
  setEmpty(consentList, "Aucun état de consentement disponible.");
  setEmpty(pageList, "Aucune page disponible.");
  generatedAt.textContent = "Accès non autorisé.";
});
