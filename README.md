# A Maze Inc.

Prototype de course multijoueur en labyrinthe pour Godot 4 et le Web. Chaque joueur contrôle un point coloré, voit toute la carte et rejoint les autres avec un code de salon à quatre caractères. Le serveur WebSocket est autoritaire : aucune adresse IP de joueur n’est partagée.

## Lancer en local

Prérequis : Godot 4.3+ et Node.js 18+.

```powershell
cd server
npm install
npm start
```

Ouvrez ensuite `project.godot` dans Godot et lancez la scène avec F6/F5. Pour tester à deux, lancez deux instances du jeu, créez un salon dans la première, puis saisissez son code dans la seconde.

Commandes : flèches, ZQSD ou WASD.

## Exporter pour le Web

1. Installez les modèles d’export Web depuis Godot si nécessaire.
2. Dans **Projet > Exporter**, choisissez le preset **Web**.
3. Exportez vers `web/index.html` (le chemin est déjà configuré).
4. Lancez `npm start` dans `server/`, puis ouvrez `http://localhost:8080`.

En version Web, le client déduit automatiquement l’adresse WebSocket depuis le domaine courant (`wss://votre-domaine/ws`). Le même service Node sert le jeu et les salons.

## Déployer gratuitement sur Render

Le dépôt contient un Blueprint `render.yaml` et un `Dockerfile`. L’export Godot présent dans `web/` est servi par le même service que les salons WebSocket.

1. Poussez le projet sur GitHub.
2. Dans Render, choisissez **New > Blueprint**.
3. Connectez le dépôt GitHub `zarocksx/multi-maze`.
4. Validez le service gratuit `multi-maze` dans la région de Francfort.

Render fournit automatiquement la variable `PORT`, HTTPS et une adresse publique. Le jeu transforme automatiquement cette adresse en connexion sécurisée `wss://.../ws`. Les joueurs ouvrent donc tous l’URL Render et ne partagent ensuite que leur code de salon.

Sur l’offre gratuite, Render met le service en veille après une période sans trafic. La première ouverture suivante peut donc prendre environ une minute.

## Protocole et règles

- Le serveur génère un labyrinthe de 19 × 13 cases.
- Jusqu’à 8 joueurs par salon.
- Tous commencent en haut à gauche ; la sortie dorée est en bas à droite.
- Le premier joueur à atteindre la sortie gagne.
- Le créateur du salon peut générer une nouvelle manche.

Tests du serveur : `cd server && npm test`.
