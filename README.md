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

Commandes : flèches, ZQSD, WASD, croix directionnelle ou stick gauche d’une manette.
La secousse de l’écran lors d’une collision avec un mur peut être désactivée en bas à gauche et le choix est mémorisé.
Entre deux courses, l’hôte choisit parmi dix tailles avec le slider près du bouton de départ. Le nombre de power-ups s’adapte à la surface du labyrinthe.

## Exporter pour le Web

1. Installez les modèles d’export Web depuis Godot si nécessaire.
2. Dans **Projet > Exporter**, choisissez le preset **Web**.
3. Exportez vers `web/index.html` (le chemin est déjà configuré).
4. Lancez `npm start` dans `server/`, puis ouvrez `http://localhost:8080`.

En version Web, le client déduit automatiquement l’adresse WebSocket depuis le domaine courant (`wss://votre-domaine/ws`). Le même service Node sert le jeu et les salons.

## Configurer la connexion Discord

La connexion Discord fonctionne dans l’export Web. Le secret OAuth reste uniquement sur le serveur et les sessions sont stockées dans un cookie `HttpOnly` signé.

1. Créez une application dans le [Discord Developer Portal](https://discord.com/developers/applications).
2. Dans **OAuth2**, ajoutez l’URL de redirection exacte :
   - local : `http://localhost:8080/auth/discord/callback`
   - Render : `https://VOTRE-SERVICE.onrender.com/auth/discord/callback`
3. Configurez les variables d’environnement suivantes sur le serveur :

```text
DISCORD_CLIENT_ID=identifiant_de_l_application
DISCORD_CLIENT_SECRET=secret_de_l_application
DISCORD_REDIRECT_URI=https://VOTRE-SERVICE.onrender.com/auth/discord/callback
AUTH_SESSION_SECRET=une_longue_valeur_aleatoire
```

Pour un essai local dans PowerShell, définissez ces quatre variables avec `$env:NOM="valeur"` avant `npm start`, puis ouvrez `http://localhost:8080`. N’ajoutez jamais `DISCORD_CLIENT_SECRET` ou `AUTH_SESSION_SECRET` au dépôt Git.

Une fois connecté, le pseudo Discord remplace le pseudo libre et la photo de profil est affichée sur le personnage. Si le compte n’est pas connecté ou si l’image ne peut pas être chargée, la couleur du joueur reste utilisée.

## Déployer gratuitement sur Render

Le dépôt contient un Blueprint `render.yaml` et un `Dockerfile`. L’export Godot présent dans `web/` est servi par le même service que les salons WebSocket.

1. Poussez le projet sur GitHub.
2. Dans Render, choisissez **New > Blueprint**.
3. Connectez le dépôt GitHub `zarocksx/multi-maze`.
4. Validez le service gratuit `multi-maze` dans la région de Francfort.

Render fournit automatiquement la variable `PORT`, HTTPS et une adresse publique. Le jeu transforme automatiquement cette adresse en connexion sécurisée `wss://.../ws`. Les joueurs ouvrent donc tous l’URL Render et ne partagent ensuite que leur code de salon.

Le Blueprint demande les identifiants Discord lors de sa création et génère automatiquement `AUTH_SESSION_SECRET`. Renseignez `DISCORD_REDIRECT_URI` avec l’URL publique exacte du service suivie de `/auth/discord/callback`.

Sur l’offre gratuite, Render met le service en veille après une période sans trafic. La première ouverture suivante peut donc prendre environ une minute.

## Protocole et règles

- Le serveur génère un labyrinthe de 19 × 13 cases.
- Jusqu’à 8 joueurs par salon.
- Tous commencent en haut à gauche ; la sortie dorée est en bas à droite.
- L’hôte lance un compte à rebours synchronisé ; tous les chronomètres partent au même instant.
- Des objets mystère donnent un turbo ou un bouclier, ou infligent ralentissement, inversion et gel.
- Tous les joueurs peuvent terminer ; le classement apparaît lorsque le dernier atteint la sortie.
- Le podium cumule les points et victoires des manches précédentes tant que le salon existe.
- Le créateur du salon peut lancer une nouvelle manche depuis le tableau des scores.

Tests du serveur : `cd server && npm test`.
