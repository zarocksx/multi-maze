# Campagne de communication web - A Maze Inc.

Date de préparation : 30 juin 2026  
Statut : v2, centrée web game  
Sources internes auditées : `README.md`, `project.godot`, `scripts/`, `server/`, `web/`, `docs/analytics-tracking-plan-v1.md`, `assets/`

## Résumé Exécutif

A Maze Inc. doit être communiqué comme un **web game multijoueur instantané** : on ouvre un lien, on crée un salon, on partage un code à quatre caractères, puis on court dans un labyrinthe avec ses amis. La force du jeu n’est pas une promesse de “gros lancement PC”, mais une boucle sociale courte, partageable et mesurable.

La campagne recommandée vise donc :

- **Le jeu immédiat** : aucune boutique, aucun téléchargement mis en avant.
- **Les groupes Discord** : le jeu est naturellement fait pour les amis déjà en vocal.
- **Les formats courts** : clips de sabotage, power-ups, revanche, podium.
- **Les playtests publics réguliers** : transformer chaque soirée en contenu et en données produit.
- **L’analytics de funnel** : vérifier si les joueurs créent, rejoignent, lancent, terminent et relancent.

Hors périmètre : boutiques PC/mobile, campagne payante lourde, promesse console/PC installable.

## Diagnostic Produit

### Promesse Actuelle

A Maze Inc. est une course multijoueur en labyrinthe jouable sur le web, avec salons à code court, serveur WebSocket autoritaire, intégration Discord, avatars, Rich Presence, power-ups, podium persistant et relance de manches.

Ce qui est immédiatement vendable :

- Un lien web à partager.
- Un salon créé en quelques secondes.
- Un code à quatre caractères facile à dire en vocal.
- Des manches courtes et lisibles.
- Une carte entièrement visible par tous.
- Des power-ups simples : turbo, bouclier, ralentissement, inversion, gel.
- Une boucle “encore une manche” grâce au podium et à la relance.
- Une base analytics RGPD déjà pensée pour apprendre vite.

### Points à Verrouiller Avant Communication

- **Nombre de joueurs** : le README annonce jusqu’à 8 joueurs, mais `server/server.js` et `scripts/main.gd` utilisent `MAX_PLAYERS = 20`. Il faut choisir une promesse officielle avant tout contenu public.
- **Hébergement** : une campagne web game ne pardonne pas le cold start. Si le premier chargement prend trop longtemps, la promesse “instantané” s’effondre.
- **Identité visuelle** : les assets `launcher_image.jpg` et `launcher_splash.png` ne montrent pas le gameplay. Ils ne doivent pas être les visuels principaux de campagne, sauf choix volontaire d’un ton mème très assumé.
- **Page d’entrée** : le joueur doit comprendre le jeu avant ou pendant le chargement Godot, avec un CTA simple : jouer.
- **Partage** : le bouton copier le code existe, mais la communication doit pousser le réflexe “partage ton lien + ton code”.

## Positionnement

### Positionnement Principal

**A Maze Inc. est une course de labyrinthe web multijoueur à lancer entre amis : un lien, un code de salon, une sortie dorée, et des power-ups qui ruinent les meilleurs plans.**

### Territoire

Web party game, mini-jeu social, arcade multijoueur, Discord-friendly.

### Piliers de Message

1. **Instantané**  
   Ouvre le lien, crée un salon, partage le code.

2. **Social**  
   Le jeu est meilleur en vocal, avec des amis qui se chambrent pendant la course.

3. **Lisible**  
   Toute la carte est visible. Le fun vient des décisions rapides et des erreurs.

4. **Chaotique**  
   Les power-ups créent des retournements faciles à comprendre en clip.

5. **Rejouable**  
   Le podium et la relance poussent à prendre sa revanche.

### Taglines de Travail

- **Un lien. Un code. Une sortie. Beaucoup de trahisons.**
- **Crée le salon. Trouve la sortie. Sabote tes amis.**
- **La course de labyrinthe qui commence dans ton navigateur.**
- **Atteins la sortie dorée avant que le vocal ne devienne personnel.**

### Pitch 1 Phrase

A Maze Inc. est une course de labyrinthe multijoueur jouable dans le navigateur, où tu invites tes amis avec un code de salon et fonces vers la sortie pendant que les power-ups renversent la partie.

### Pitch Court

A Maze Inc. est un web party game multijoueur. Crée un salon, partage un code à quatre caractères, puis affronte tes amis dans des manches courtes où tout le monde voit la carte, mais personne ne contrôle vraiment le chaos : turbo, bouclier, gel, ralentissement et commandes inversées peuvent tout changer.

### Pitch Créateur

A Maze Inc. est un jeu web parfait pour une petite session en vocal : un lien, des salons privés, des courses courtes, des power-ups injustes juste ce qu’il faut et une revanche immédiate. Le format se comprend vite en stream et produit naturellement des clips.

## Publics Cibles

### Primaire

Groupes d’amis sur Discord, communautés Twitch, serveurs étudiants, groupes de joueurs qui cherchent un mini-jeu rapide à tester sans installation.

Motivations :

- Jouer maintenant sans compte obligatoire.
- Remplir 10 minutes entre deux activités.
- Rire avec un groupe déjà présent en vocal.
- Faire une revanche immédiate.

### Secondaire

Fans de jeux web, communautés Godot, communautés itch.io/web games, devlogs, joueurs curieux de prototypes multijoueurs.

Motivations :

- Découvrir un projet indépendant en développement.
- Donner du feedback.
- Suivre l’évolution d’un jeu social léger.

### Créateurs à Cibler

Priorité aux micro-créateurs qui peuvent jouer avec leur communauté :

- Streamers Twitch/YouTube FR et EN de party games.
- Créateurs TikTok/Reels/Shorts orientés “jeux gratuits à tester avec tes amis”.
- Animateurs de serveurs Discord.
- Créateurs devlog/Godot pour l’angle fabrication.
- Newsletters ou blogs qui couvrent les jeux web indés.

## Objectifs

### Objectif Principal

Prouver que le jeu donne envie de relancer une manche.

### Objectifs 30 Jours

- Organiser 5 à 10 sessions de playtest avec au moins 4 joueurs.
- Capturer 20 clips courts montrant un moment compréhensible en moins de 3 secondes.
- Obtenir 100 salons créés sur la période de test.
- Mesurer le taux `race_started / room_created`.
- Mesurer le taux `race_restarted / race_completed`.
- Identifier les 3 frictions principales : chargement, création, join, départ, compréhension, relance.

### Objectifs 90 Jours

- Avoir une landing page web claire avec URL courte.
- Avoir une boucle communautaire Discord active.
- Publier 30 à 40 contenus courts.
- Construire une liste de 100 contacts qualifiés : créateurs, serveurs Discord, communautés web games.
- Avoir une version “open playtest” stable.
- Atteindre un niveau de relance suffisant pour valider le coeur social du jeu.

## Stratégie de Campagne

### Phase 1 - Rendre le Jeu Partageable

Période recommandée : 30 juin au 14 juillet 2026

Objectif : faire en sorte qu’un joueur comprenne, lance et invite sans explication extérieure.

Actions :

- Choisir le nombre de joueurs officiellement communiqué : 8, 12, 16 ou 20.
- Stabiliser une URL publique courte.
- Réduire ou masquer le cold start avec un écran de chargement clair et vivant.
- Créer une landing légère avant le canvas ou autour du jeu : promesse, bouton jouer, bouton Discord, politique de confidentialité.
- Ajouter des liens partageables : `https://.../?room=CODE` si faisable, ou au minimum un bouton copier “lien + code”.
- Remplacer les visuels launcher publics par des captures gameplay.

Livrables :

- URL publique stable.
- 1 logo lisible.
- 6 screenshots gameplay.
- 3 clips verticaux.
- 1 page “à propos / press kit”.
- 1 message Discord de recrutement playtest.

### Phase 2 - Playtests Récurrents

Période recommandée : 15 juillet au 11 août 2026

Objectif : transformer les sessions en preuves de fun.

Actions :

- Organiser 2 soirées playtest par semaine.
- Inviter des groupes de 4 à 8 joueurs.
- Enregistrer les moments clés : départ, power-up, sortie dorée, podium, revanche.
- Publier 3 contenus courts par semaine.
- Demander un feedback très ciblé après session.

Questions feedback :

- Est-ce que tu as compris quoi faire en moins de 20 secondes ?
- Est-ce que tu as réussi à rejoindre un salon sans aide ?
- Quel moment t’a fait rire ou râler ?
- As-tu eu envie de relancer ?
- Quel power-up t’a semblé le plus injuste ?

### Phase 3 - Lancement Web Public

Période recommandée : 12 août au 15 septembre 2026

Objectif : passer de “playtest fermé” à “jouable publiquement”.

Actions :

- Publier la page web officielle.
- Lancer un week-end “Open Maze”.
- Organiser deux créneaux avec les devs en vocal.
- Envoyer le jeu à 30 à 50 créateurs/serveurs qualifiés.
- Publier un trailer web de 30 à 45 secondes.
- Mettre en avant un CTA unique : “Jouer maintenant”.

Angle :

**A Maze Inc. est ouvert : envoyez le lien à 3 amis, créez un salon et voyez si vous arrivez à relancer une deuxième manche.**

### Phase 4 - Croissance Communautaire

Période recommandée : 16 septembre au 31 octobre 2026

Objectif : installer un rendez-vous régulier.

Actions :

- Créer un événement hebdomadaire “Maze Night”.
- Publier un défi de la semaine : taille de labyrinthe, nombre de power-ups, meilleur temps.
- Mettre en avant les meilleurs clips de joueurs.
- Créer un tableau de scores communautaire si les données le permettent.
- Tester un format “devs vs joueurs”.
- Approcher de nouveaux serveurs Discord avec un message court et un créneau clé en main.

### Phase 5 - Itérations Publiques

Période recommandée : novembre 2026 et après

Objectif : montrer que le jeu évolue grâce aux joueurs.

Actions :

- Publier un bilan mensuel : salons créés, courses terminées, power-up le plus détesté, changements à venir.
- Sortir une amélioration visible par mois.
- Donner un nom aux updates : “Revanche Update”, “Power-Up Update”, “Lobby Update”.
- Mettre les métriques utiles en avant sans exposer de données personnelles.

## Calendrier Actionnable

| Date | Action | Responsable | Sortie attendue |
| --- | --- | --- | --- |
| 30 juin - 3 juillet | Verrouiller promesse, public cible, nombre de joueurs officiel | Studio | Message house validé |
| 4 - 10 juillet | Produire screenshots, logo, capsule web, clips tests | Art/Com | Kit visuel v1 |
| 11 - 14 juillet | Stabiliser URL publique et chargement | Tech | Lien partageable |
| 15 juillet | Lancer playtests privés | Com/QA | 1ère session enregistrée |
| 16 - 31 juillet | Publier 3 clips/semaine et recruter groupes Discord | Com | 9 à 12 contenus |
| 1 - 11 août | Synthèse playtests + trailer web rough cut | Studio | Trailer v0 |
| 12 août | Préparer lancement web public | Studio | Landing + press kit |
| 16 - 18 août | Vague créateurs/serveurs Discord 1 | Com | 30 contacts |
| 22 - 24 août | Week-end Open Maze | Tous | Sessions publiques |
| 25 - 31 août | Bilan Open Maze et corrections rapides | Studio | Patch visible |
| Septembre | Maze Night hebdomadaire | Com | Rendez-vous communautaire |
| Octobre | Défis communautaires et créateurs vague 2 | Com | Croissance organique |
| Novembre | Bilan public + update nommée | Studio | Post de roadmap |

## Plateformes et Rythme

### Site Web

Rôle : point d’entrée principal.

Structure recommandée :

- Canvas/jeu ou CTA “Jouer maintenant” visible immédiatement.
- Une phrase de promesse.
- Bouton “Créer une partie”.
- Bouton “Rejoindre Discord”.
- Lien confidentialité/conditions.
- Section courte “Comment jouer” en 3 étapes si elle reste hors du canvas.

CTA principal :

- “Jouer maintenant”

CTA secondaire :

- “Rejoindre les playtests”

### Discord

Rôle : communauté, playtests, vocal, support rapide.

Salons recommandés :

- `annonces`
- `playtests`
- `cherche-groupe`
- `clips`
- `feedback`
- `bugs`

Cadence :

- 2 annonces playtest par semaine au début.
- 1 recap après chaque session.
- 1 défi hebdomadaire après lancement public.

### TikTok, Reels, YouTube Shorts

Rôle : acquisition froide.

Cadence :

- 3 vidéos courtes par semaine.
- Format 9:16.
- Jeu visible dès la première seconde.
- Texte incrusté très court.

Formats :

- “Jeu web à tester avec 3 amis.”
- “Le power-up le plus injuste.”
- “On relance ou pas ?”
- “Ton ami dit qu’il connaît le chemin.”

### YouTube Long / Devlog

Rôle : crédibilité et histoire du projet.

Cadence :

- 1 vidéo toutes les 3 à 4 semaines.

Angles :

- “Créer un party game web avec Godot.”
- “Pourquoi on mesure les relances plutôt que les clics.”
- “Comment un code de salon change tout pour un jeu entre amis.”

### Reddit / Communautés Web Games

Rôle : feedback qualifié.

Approche :

- Ne pas poster comme une publicité brute.
- Montrer un clip et demander un retour précis.
- Privilégier les communautés qui acceptent les prototypes jouables.

Message type :

“On teste un web game multijoueur de course en labyrinthe. Notre question principale : est-ce que la boucle donne envie de relancer ? Si vous avez 3 amis sous la main, vos retours nous aideraient beaucoup.”

### Itch.io ou Portails Web

Rôle : annuaire et découvrabilité web.

Approche :

- Utiliser itch.io comme page miroir ou page de communauté si pertinent.
- Garder le CTA vers la version web officielle si le serveur centralisé est nécessaire.
- Mettre en avant “play in browser”, “multiplayer”, “party game”, “maze”, “Discord”.

## Idées de Contenus

1. **“Tu as 4 caractères pour inviter tes amis.”**  
   Capture : création de salon, code copié, joueurs qui arrivent.

2. **“Tout le monde voit la sortie. Personne ne l’atteint proprement.”**  
   Capture : carte complète, joueurs qui prennent des routes différentes.

3. **“Le turbo est juste. Le gel l’est moins.”**  
   Capture : power-up turbo puis adversaires gelés.

4. **“Le moment où ton ami inverse tes commandes.”**  
   Capture : joueur qui part dans le mauvais sens.

5. **“Une manche, puis une revanche, puis encore une.”**  
   Capture : podium puis bouton relancer.

6. **“On cherche des groupes pour casser notre labyrinthe.”**  
   Capture : chaos à 4 joueurs ou plus.

7. **“Jusqu’où peut-on agrandir le labyrinthe avant que ça devienne une expédition ?”**  
   Capture : slider de taille puis grande carte.

8. **“Le meilleur joueur n’est pas toujours celui qui court le plus vite.”**  
   Capture : bouclier, ralentissement, comeback.

9. **“Test Discord : avatars en course.”**  
   Capture : avatars Discord visibles sur les joueurs.

10. **“Notre métrique préférée : est-ce que les joueurs relancent ?”**  
    Capture : analytics ou podium + relance.

11. **“Le pire départ possible en 5 secondes.”**  
    Capture : collision mur, écran qui secoue, retard.

12. **“La sortie dorée est là. Le problème, c’est les autres.”**  
    Capture : dernier couloir + power-up adverse.

## Messages Prêts à Adapter

### Post Teaser

On prépare les premiers playtests de A Maze Inc. : un web game multijoueur où tu crées un salon, partages un code et essaies d’atteindre la sortie avant que tes amis ne ruinent ton plan avec un power-up.

On cherche des groupes de joueurs pour tester des manches courtes et nous dire une seule chose : est-ce que vous avez envie de relancer ?

### Post Lancement Web

A Maze Inc. est jouable dans le navigateur.

Crée un salon, partage le code à tes amis et fonce vers la sortie dorée. Les power-ups peuvent t’aider, te protéger ou transformer une avance tranquille en énorme erreur collective.

Jouer maintenant : [lien]

### Post Playtest Discord

Session A Maze Inc. ce soir.  
Objectif : 4 à 8 joueurs par salon, 10 minutes de jeu, feedback très court.

Créez un salon, partagez le code, lancez une course, puis dites-nous :

- où vous avez ri ;
- où vous avez bloqué ;
- si vous avez voulu relancer.

### Post Créateur

On cherche des créateurs qui veulent tester un web game multijoueur en live avec leur communauté.

A Maze Inc. se lance avec un simple lien : salons privés, codes courts, courses rapides, power-ups et revanche immédiate. Si vous avez 3 à 7 joueurs en vocal, vous avez assez pour une session.

Contact : [lien/contact]

### Message Court Créateur

Bonjour,

Je travaille sur A Maze Inc., un web game multijoueur de course en labyrinthe. Le format est pensé pour les streams et groupes Discord : un lien, un code de salon, des manches courtes, des power-ups qui provoquent des retournements et une revanche immédiate.

On organise des sessions de playtest public et je pense que le jeu peut bien fonctionner avec votre communauté. Je peux vous envoyer le lien jouable, un mini press kit et un créneau si vous voulez tester avec nous.

Merci,  
[Nom]

### Message Serveur Discord

Bonjour,

On développe A Maze Inc., un petit jeu web multijoueur à lancer entre amis. Vous ouvrez le lien, créez un salon, partagez un code et vous faites une course de labyrinthe avec power-ups.

On cherche des serveurs qui veulent organiser une session courte de 20 à 30 minutes. Le but est simple : voir si les joueurs comprennent vite et s’ils ont envie de relancer une manche.

Lien : [lien]  
Contact : [contact]

## Landing Page

### Titre

A Maze Inc.

### Sous-Titre

Une course de labyrinthe multijoueur à lancer dans ton navigateur.

### Description Courte

Crée un salon, partage un code et affronte tes amis dans une course web où les power-ups peuvent tout renverser avant la sortie dorée.

### Comment Jouer

1. Ouvre le jeu.
2. Crée un salon ou rejoins avec un code.
3. Atteins la sortie dorée avant les autres.

### Fonctionnalités à Afficher

- Jeu web multijoueur.
- Salons privés avec code à quatre caractères.
- Labyrinthes générés et tailles réglables.
- Power-ups : turbo, bouclier, ralentissement, inversion, gel.
- Podium et relance de manche.
- Clavier, manette et tactile.
- Connexion Discord optionnelle.

### À Ne Pas Surpromettre

- “Sans attente” si l’hébergement peut avoir un cold start.
- “Jusqu’à 20 joueurs” tant que ce nombre n’est pas validé en campagne publique.
- “Discord Activity” tant que le flux final n’est pas testé en environnement réel.
- “Massivement multijoueur” : c’est une expérience de salon.

## Press Kit Web

À créer avant la première vague créateurs :

- Logo horizontal et carré.
- 6 à 10 screenshots gameplay, sans debug overlay.
- 3 clips verticaux de 10 à 20 secondes.
- 1 trailer web de 30 à 45 secondes.
- GIFs courts : création salon, départ, power-up, podium.
- Fiche factuelle : titre, genre, plateforme web, langues, studio, contact.
- Pitch court et pitch long.
- Lien jouable.
- Informations RGPD et Discord en langage simple.
- Autorisation claire de streamer/enregistrer/monétiser le contenu.

## Direction Créative Visuelle

### Ce Qui Doit Apparaître

- Le labyrinthe complet.
- Des joueurs colorés ou avatars visibles.
- La sortie dorée.
- Au moins un power-up actif.
- Le code de salon ou le moment d’invitation.
- Le podium ou le bouton de relance.

### Ce Qui Doit Être Évité

- Captures trop vides avec un seul joueur.
- Visuels abstraits qui ne montrent pas le gameplay.
- Launcher personnel/déformé utilisé comme key art public, sauf campagne mème volontaire.
- Trop de texte explicatif dans les assets.
- Promesses techniques non visibles à l’écran.

### Ton

Le ton doit être direct, social et un peu taquin. Le jeu doit donner l’impression d’être facile à lancer, mais dangereux pour les amitiés pendant cinq minutes.

## Plan Créateurs

### Ciblage

Priorité aux créateurs qui peuvent jouer avec 3 à 7 personnes rapidement.

Segments :

- Micro-streamers FR party games.
- Créateurs “jeux gratuits à tester entre amis”.
- Animateurs de serveurs Discord.
- Créateurs Godot/devlog.
- Pages qui recommandent des jeux navigateur multijoueurs.

### Proposition Créateur

Offrir une session courte, facile à organiser :

- Lien jouable.
- Salon privé.
- Créneau avec devs.
- Défi “battre les devs”.
- Autorisation de streamer et monétiser.
- Clip pack pour annoncer la session.

### Kit Créateur

- 1 phrase pour expliquer le jeu.
- 3 règles simples.
- 3 moments à chercher en live : premier gel, première inversion, revanche.
- Lien press kit.
- Contact Discord/email.

## Mesure et Analytics

Le tracking plan existant est un avantage. La campagne doit mesurer la qualité de la boucle web plutôt que seulement la visibilité.

### Métriques North Star

- `courses_terminees`
- `manches_par_salon`

### Funnel Web

1. Visite page web.
2. Clic “Jouer maintenant”.
3. Salon créé : `room_created`.
4. Joueurs qui rejoignent : `room_joined`.
5. Course lancée : `race_started`.
6. Course terminée : `race_completed`.
7. Manche relancée : `race_restarted`.

### KPIs à Suivre par Vague

- Taux de création de salon par visite.
- Taux de départ : `race_started / room_created`.
- Taux de completion : `race_completed / race_started`.
- Relances par salon.
- Durée lobby moyenne.
- Taux d’échec de join.
- Nombre moyen de joueurs par salon.
- Taux de retour à 24h ou 7 jours si mesurable sans tracking intrusif.

### Instrumentation à Ajouter Avant Grosse Vague

- Capturer `utm_source`, `utm_medium`, `utm_campaign` sur la landing page avec consentement adapté.
- Ajouter un paramètre `ref` non personnel pour créateurs et serveurs Discord.
- Créer des liens par campagne : `?ref=discord_server_x`, `?ref=creator_y`.
- Ajouter une vue dashboard “campagne” : visites, salons, départs, complétions, relances par source.
- Mesurer le temps entre chargement page et création de salon.
- Mesurer le taux d’abandon avant canvas si possible.

### Décisions Guidées par Données

- Si beaucoup de visites mais peu de salons : clarifier CTA et réduire friction de chargement.
- Si beaucoup de salons mais peu de départs : améliorer invitation, attente et bouton start.
- Si beaucoup de joins échouent : améliorer partage du code et durée de vie des salons.
- Si completion faible : réduire taille par défaut ou ajuster power-ups.
- Si relance faible malgré completion correcte : renforcer podium, revanche, variation de manches.
- Si Discord convertit mieux que les réseaux froids : prioriser serveurs et événements vocaux.

## Risques et Réponses

| Risque | Effet | Réponse |
| --- | --- | --- |
| Cold start ou chargement trop long | Abandon avant jeu | Hébergement plus réactif, loader clair, page légère |
| Visuels actuels peu lisibles | Confusion, baisse de confiance | Produire screenshots/capsules gameplay |
| Promesse joueurs incohérente 8 vs 20 | Méfiance | Verrouiller chiffre public |
| Jeu dépendant d’amis disponibles | Conversion solo faible | Organiser créneaux communautaires et salon Discord `cherche-groupe` |
| Liens non partageables avec code | Friction invitation | Ajouter partage lien + code |
| Chat/modération | Risque communautaire | Règles simples, bouton signalement ou modération minimale si public large |
| Analytics trop pauvres par source | Impossible de savoir ce qui marche | Ajouter `ref` et UTM sobres |

## Checklist Avant Lancement Web Public

- [ ] Nombre de joueurs officiel choisi et cohérent partout.
- [ ] URL publique stable et courte.
- [ ] Hébergement sans attente excessive.
- [ ] Build sans debug visible.
- [ ] Page d’entrée claire avec CTA “Jouer maintenant”.
- [ ] Au moins 6 screenshots gameplay propres.
- [ ] Logo et capsule web provisoires.
- [ ] 3 clips verticaux.
- [ ] Press kit web prêt.
- [ ] Discord ou canal feedback prêt.
- [ ] Règles de communauté et modération minimale.
- [ ] Analytics vérifiées sur création, join, départ, completion, relance.
- [ ] Tracking `ref` ou UTM ajouté pour les vagues créateurs.

## Backlog Communication

### Must

- Remplacer assets launcher publics.
- Choisir le nombre de joueurs à annoncer.
- Créer un dossier press kit web.
- Préparer 10 captures courtes de gameplay.
- Stabiliser une URL publique sans attente excessive.
- Écrire une landing page orientée “jouer maintenant”.

### Should

- Ajouter attribution campagne dans analytics.
- Ajouter un partage lien + code.
- Créer un trailer web 30 à 45 secondes.
- Ouvrir un formulaire feedback post-playtest.
- Mettre en place un calendrier de soirées playtest.
- Créer un salon Discord pour trouver un groupe.

### Could

- Créer un mode spectateur léger pour créateurs.
- Ajouter un bouton “copier invitation complète”.
- Ajouter un écran fin de manche avec CTA “revanche” et “partager”.
- Créer un challenge hebdomadaire : taille de labyrinthe imposée, meilleur temps studio à battre.
- Créer une page publique de statistiques globales anonymisées.

## Message House

### Ce Que Nous Disons

A Maze Inc. est un web game multijoueur instantané à jouer entre amis. Le coeur du jeu tient en trois gestes : ouvrir le lien, partager un code, courir vers la sortie dorée.

### Ce Que Nous Montrons

Des courses courtes, des amis qui se rejoignent vite, des power-ups qui changent le classement, un podium qui appelle une revanche.

### Ce Que Nous Mesurons

Pas seulement les vues. Nous mesurons surtout les salons créés, les courses terminées et les manches relancées, parce que le vrai signal de fun est “encore une”.
