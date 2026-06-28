# Analytics tracking plan v1

Objectif : mesurer ce qui aide a ameliorer l'experience et la viabilite du jeu, sans collecter de donnees personnelles inutiles.

Principes :

- Pas d'IP brute, pas d'email, pas d'identifiant Discord en clair.
- Sessions pseudonymisees cote serveur quand une session est necessaire.
- Pas d'analyse du contenu du chat.
- Pas de tracking inter-sites.
- Conservation courte, 30 jours par defaut.
- Les evenements web non essentiels restent soumis au consentement analytics.

## North star

`courses_terminees` et `manches_par_salon`.

Ces deux metriques disent si les joueurs arrivent a demarrer une partie, s'amusent assez pour finir, puis relancent.

## Evenements v1

| Event | Finalite produit/business | Propriétés autorisées | Risque RGPD | Decision rendue possible |
| --- | --- | --- | --- | --- |
| `web_session_started` | Mesurer l'arrivee consentie sur le site | `path` | Faible avec consentement | Comprendre le volume d'entree |
| `web_page_view` | Identifier les pages utiles | `path` | Faible avec consentement | Simplifier le parcours d'accueil |
| `consent_updated` | Prouver le choix analytics | `choice` | Faible | Controler la conformite |
| `room_created` | Mesurer le debut du funnel multijoueur | `players`, `mazeScale`, `powerUpCount` | Faible | Voir si les joueurs creent des salons |
| `room_joined` | Mesurer la capacite a rejoindre une room | `players`, `mazeScale`, `powerUpCount`, `roomAgeMs` | Faible | Evaluer la viralite et la friction invite |
| `room_join_failed` | Detecter la friction de join | `reason` | Faible | Ameliorer les messages, le partage de code et la duree de vie des rooms |
| `race_started` | Mesurer le passage lobby -> jeu | `players`, `mazeScale`, `powerUpCount`, `round`, `startAtMs`, `lobbyDurationMs` | Faible | Optimiser le lobby et les reglages |
| `race_completed` | Mesurer la qualite d'une partie | `players`, `mazeScale`, `powerUpCount`, `round`, `durationMs`, `completedAtMs` | Faible | Ajuster taille, power-ups et rythme |
| `race_restarted` | Mesurer la retention immediate | `players`, `mazeScale`, `powerUpCount`, `round`, `previousRounds`, `completedRounds` | Faible | Estimer l'envie de rejouer |
| `room_closed` | Mesurer abandon ou fin naturelle | `phase`, `players`, `maxPlayers`, `roundsStarted`, `completedRounds`, `roomAgeMs`, `lobbyDurationMs`, `reason` | Faible | Prioriser les problemes de lobby ou de course |
| `maze_resized` | Voir les reglages explores | `players`, `mazeScale`, `powerUpCount` | Faible | Ajuster le defaut et l'UI de reglages |
| `power_up_count_changed` | Voir les reglages explores | `players`, `mazeScale`, `powerUpCount` | Faible | Equilibrer le defaut des power-ups |
| `chat_sent` | Mesurer l'usage social sans contenu | `players`, `mazeScale`, `powerUpCount` | Moyen-faible | Decider si le chat merite plus d'UX |
| `discord_login_success` | Mesurer l'adoption de Discord | `provider` | Faible | Prioriser Discord Activity et auth |

## Metriques derivees

| Metrique | Formule | Usage |
| --- | --- | --- |
| Duree moyenne partie | Moyenne `race_completed.durationMs` | Ajuster rythme et taille par defaut |
| Joueurs concurrents 10 min | Somme des joueurs des courses actives par bucket de 10 min | Dimensionner serveur et detecter les pics |
| Usage parametres | Part des `race_started` par valeur | Comprendre les preferences reelles |
| Taux de depart | `race_started / room_created` | Mesurer friction lobby |
| Taux de completion | `race_completed / race_started` | Mesurer difficulte ou problemes de course |
| Taux de join fail | `room_join_failed / (room_joined + room_join_failed)` | Mesurer friction code salon |
| Relances par salon | `race_restarted` et `completedRounds` | Proxy de fun et retention courte |
| Lobby moyen avant depart | Moyenne `race_started.lobbyDurationMs` | Optimiser invitation, attente et CTA |
| Abandons lobby | `room_closed` avec `phase=waiting` et `roundsStarted=0` | Identifier un probleme de demarrage |

## Donnees exclues

- Contenu du chat.
- Nom, avatar, email ou identifiant Discord dans les exports analytics.
- Code exact du salon en clair.
- Adresse IP brute.
- Geolocalisation precise.
- Fingerprinting navigateur.
- Tracking publicitaire ou cross-site.

## Rythme d'analyse

Hebdomadaire :

- Regarder completion, lobby moyen, join fail, duree moyenne.
- Comparer les parametres utilises aux durees et completions.
- Reperer les pics horaires de concurrence.

Mensuel :

- Decider un seul changement produit mesurable : defaut de taille, defaut de power-ups, flow de join, ou proposition premium.
- Garder une trace de l'hypothese et du resultat.
