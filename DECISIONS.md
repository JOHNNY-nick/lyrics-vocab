# Décisions et écarts au cahier des charges

Ce fichier liste les choix faits pendant le développement là où le cahier des charges laissait un doute, et chaque écart volontaire (AGT-02, AGT-15, DES-33, DES-38). Format : question, choix, raison.

## Organisation du dépôt

| Date | Question | Choix | Raison |
| --- | --- | --- | --- |
| 2026-10-12 | Emplacement du dépôt (ENV-04 : `C:/lyrics-vocab/depot`) | Le dépôt est développé dans le dossier courant ; il se clone ou se copie tel quel dans `C:/lyrics-vocab/depot`. Les scripts utilisent `C:/lyrics-vocab` par défaut (paramètre `-Racine`). | Ne pas imposer de déplacement pendant le développement. |
| 2026-10-12 | Dossier `docs` | Le dossier s'appelle `Docs` (il existait déjà ; Windows ne distingue pas la casse). Les planches sont copiées sans modification dans `Docs/design` (DES-31). | Conserver le dossier fourni. |
| 2026-10-12 | Tests du backend | Dans `backend/app/tests` (annexe 1). La base de test est un PostgreSQL éphémère lancé par `pgserver` (PostgreSQL 16 embarqué, installé par pip) ; `TEST_DATABASE_URL` permet d'utiliser une autre base (cas de l'intégration continue). | Les tests d'intégration exigent un vrai PostgreSQL (index partiels, déclencheurs, JSONB) ; aucun PostgreSQL n'était lancé sur le PC. |

## Dépendances ajoutées (AGT-12)

| Paquet | Où | Raison | Compatible web |
| --- | --- | --- | --- |
| `tzdata` | backend | `zoneinfo` n'a pas de base de fuseaux sur Windows. | — |
| `pgserver` | backend (tests) | PostgreSQL embarqué pour les tests d'intégration. | — |
| `black`, `ruff` | backend (qualité) | Formatage et analyse (34.2, QUAL-06). | — |
| `unorm_dart` | app | NFKC et NFD en Dart (normalisation identique au Python, ALG-01 ; recherche sans accents). | oui (Dart pur) |
| `flutter_timezone` | app | Nom IANA du fuseau pour l'en-tête `X-Fuseau` (ALG-15). | oui |
| `timezone` | app | Programmation des notifications à l'heure locale (dépendance de `flutter_local_notifications`). | oui |
| `uuid` | app | UUID créés par le client (BDD-04). | oui |
| `intl`, `flutter_localizations` | app | Dates en français (I18N-01). | oui |
| `web` | app | Rechargement de la PWA après mise à jour (PWA-07), isolé par import conditionnel. | oui |

## Données et API

| Question | Choix | Raison |
| --- | --- | --- |
| Révisions faites hors-ligne enchaînées (répondre à A crée B sur le téléphone, puis répondre à B) | `revision.repondre` accepte en plus `mot_id` et `nouvelle_revision_id` ; `mot.creer` accepte `revision_id`. Le serveur crée la révision suivante avec l'identifiant fourni par l'appareil. `POST /api/revisions/{id}/reponse` accepte aussi `nouvelle_revision_id`. | Sans cela, la deuxième réponse hors-ligne vise une révision inconnue du serveur et serait rejetée (REV-T05, SYN-T01). |
| Réponse visant un mot fusionné (SYN-22, CLI-03) | Si `revision_id` est inconnu, le serveur utilise `mot_id`, résolu au besoin via le résultat de `mot.creer` stocké dans `sync_op` (`id_local` → `mot_id`), puis la révision planifiée du mot conservé. | ETA-03 : les réponses sont rattachées au mot conservé, même si elles arrivent dans le même lot que la fusion. |
| Identifiant de l'exercice (18.5) | L'identifiant renvoyé par `POST /api/exercices` est celui de la révision planifiée ; la phrase et la référence sont stockées dans `phrase_source` et `reference_en`, le verdict de `/evaluer` dans `verdict`, `verdict_repli`, `explication_verdict`. | Le schéma (17.4) n'a pas de table d'exercice ; le client envoie ensuite la réponse sur ce même identifiant. |
| Contenu de `GET /api/revisions/dues` | Ajout de `jour`, `prochaine_date`, `serie` et, par item, `explication`, `source_explication`, `extrait`. | L'écran a besoin de l'état vide (« Prochaine révision »), de la pastille « Série de N jours » et du contenu révélé sans requête supplémentaire. |
| Liste des artistes suggérés (H.3) | Nouvelle route `GET /api/artistes/suggestions` : les 15 artistes du design, avec photo Genius quand elle est disponible ; liste de secours embarquée dans l'application. | La liste doit être « fournie par le serveur » mais aucune route n'était au catalogue. |
| Codes d'erreur supplémentaires | `revision_introuvable` (404), `identifiant_deja_utilise` (409), `requete_trop_grande` (413), `limite_requetes` (429), `parametre_invalide` et `reponse_invalide` (422). | Cas prévus par le texte (API-38, API-06, SEC-12, 18.3, 18.4) sans code au tableau C.4. |
| `/api/health` | Champs ajoutés : `version_client_min` (CL-32), `alerte_disque` (CL-28), `apk` (AND-18, lu dans `APK_DIR/version.json`), `derniere_sauvegarde` et `alerte_sauvegarde` (SAV-05, lu dans `BACKUP_DIR/derniere_reussie.txt`). | Exigences qui demandent ces informations sans préciser leur transport. |
| Bornage de la date de réponse (G.6, SYN-31) | Vers le futur : au plus 24 h après l'heure du serveur. Vers le passé : la date proposée est gardée, mais jamais avant la création de la révision. Tout bornage est journalisé. | Un bornage strict à −24 h décalerait les échéances des révisions faites pendant plusieurs jours sans PC (E2E-03, SYN-T05). La protection contre une horloge en retard reste assurée par la date de création. |
| Réponse sur une révision déjà faite par un autre appareil | Rejet `revision_deja_repondue` (API-38), l'opération va dans « À examiner » ; le pull suivant remplace l'état local. | API-38 est explicite ; G.6 (« toutes les réponses sont conservées ») reste vrai pour les réponses enchaînées du même appareil. |
| Révision planifiée d'un mot supprimé | `deleted_at` renseigné et statut `ignoree`. | BDD-08 (deleted_at) et 19.2 (ignoree). |
| Idempotence de `POST /api/revisions/{id}/reponse` | Le résultat est aussi stocké dans `sync_op` : le rejeu renvoie exactement le même résultat avec `statut = deja_applique`. | API-26 « même résultat ». |
| Curseur de synchronisation | Le curseur serveur est le plus grand `server_seq` des cinq tables. Limite connue : une transaction longue validée après une plus récente pourrait être sautée ; sans conséquence en usage mono-utilisateur (transactions de quelques millisecondes). | 17.5 ; usage personnel. |
| Série de jours | Calculée en Python (fuseau `zoneinfo`) à partir des heures de réponse, pas en SQL. | Ne dépend pas de la base de fuseaux de PostgreSQL. |
| Pastille « Argot » (43.6) | Affichée si l'explication ou la traduction contient « argot » (sans négation). Aucune colonne ajoutée. | Le schéma n'a pas de champ argot ; le prompt demande d'indiquer l'argot. |
| Mot recréé après suppression (CAC-02) | Traduction, explication et extraits de l'ancien mot sont recopiés sur le nouveau. | Aucun appel externe pour un terme déjà enrichi. |
| Reprise des enrichissements (ENR-03) | Au démarrage : tous les mots `en_attente`/`en_cours` (aucun n'est réellement en cours après un redémarrage). À chaque synchronisation : ceux bloqués depuis plus de 10 minutes, plus jusqu'à 20 fiches incomplètes (échec, partiel hors « aucun extrait », « aucun extrait » de plus de 7 jours). | 19.1 et IA-22. |
| Fuseau du PC (ALG-15) | Paramètre `FUSEAU_PC` (défaut `Europe/Paris`) plutôt qu'une détection automatique du fuseau Windows. | La conversion Windows → IANA demanderait une dépendance de plus ; à régler une fois dans le `.env`. |
| Limitation de débit (SEC-12) | Par en-tête `X-Appareil-Id`, sinon par adresse ; `/api/health` et `/api/sync/*` sont exclus. | « hors synchronisation » ; la santé est interrogée souvent par les clients. |

## Services externes et IA

| Question | Choix | Raison |
| --- | --- | --- |
| Musixmatch (à confirmer, phase 03) | `artist.search` pour obtenir `musixmatch_id` (mémorisé), `track.search` (par artiste ou `q_lyrics`), `track.lyrics.get`. 402/429 = quota ; 401/403 = indisponible. | Points de départ de 38.1. Le texte partiel du plan gratuit et sa mention de licence sont nettoyés (MAT-15). |
| DeepL | Adresse gratuite si la clé finit par `:fx`, sinon l'adresse Pro ; cible `EN-US` pour la phrase de référence (FR → EN). | DeepL refuse `EN` comme langue cible. |
| Détection du français (IA-11) | Heuristique par mots outils français/anglais et accents. | « détection simple ». |
| Injection de consigne (IA-20, IA-T05) | En plus de la délimitation `<reponse>…</reponse>`, une réponse contenant des mots de consigne (« ignore », « instructions », « réponds correct », « verdict »…) est évaluée par le repli par mots-clés, sans appel à l'IA. | Un modèle de 8 milliards de paramètres peut suivre une consigne malgré la délimitation ; le repli garantit que le verdict n'est pas forcé. |
| Modèle Ollama | `llama3.1:8b` reste la valeur par défaut (IA-01). Ce modèle n'est pas encore téléchargé sur le PC (seuls `llama3.2:3b`, `qwen3-coder:30b`, `qwen3.8:27b` le sont) : `ollama pull llama3.1:8b` fait partie des tâches humaines. | IA-01. |

## Application Flutter

| Question | Choix | Raison |
| --- | --- | --- |
| Préférences locales sur le web | Une boîte Hive `prefs` (IndexedDB sur le web) garde `appareil_id` et l'indicateur de premier lancement sur les deux plateformes. | L'onboarding ne doit s'afficher qu'une fois (US-01), aussi sur PC. |
| Bouton « Annuler » d'une réponse (REV-15, 27.2 point 6) | La carte suivante s'affiche tout de suite ; un bandeau « Réponse enregistrée — Annuler » reste 5 s ; la réponse n'est envoyée qu'à la fin du délai. Annuler revient sur la carte. | REV-15 est respecté sans imposer 5 s d'attente entre chaque carte (sessions de 2 à 5 minutes, 1.4). |
| Bouton fermer de la session, retour et menu « … » de la fiche | Posés en surimpression dans le coin haut droit de l'en-tête coloré, sans décaler les éléments du design. Pendant une session, la pastille « Série de N jours » n'est pas affichée (elle l'est sur l'accueil des révisions et sur le récapitulatif de la planche) pour laisser la place au bouton fermer. | Le design ne montre pas ces boutons (exigés par 27.2 et 43.6 point 8) ; DES-38 : approcher au plus près sans simplifier l'écran. |
| Menu de tri de la bibliothèque (27.5) | Icône de tri à droite, dans le champ de recherche. | Placée dans la rangée des filtres, elle masquait la pastille « Acquis » à 390 px. |
| Interlignes des titres | `titreEcran` et `titreMot` utilisent l'interligne naturel de la police ; le titre de l'écran des artistes garde 1,1. | DES-33 : les fichiers HTML (pas de `line-height` sur ces titres) priment sur le tableau 43.3. |
| Champ de recherche | 52 px + 2 × 2 px de bordure. | Modèle de boîte CSS par défaut des planches (`content-box`). |
| Graisse 600 de Plus Jakarta Sans | Non embarquée (DES-07 ne liste que 500 et 700) : la légende des tuiles (12/600) est rendue avec la graisse embarquée la plus proche. | DES-07. |
| Zones tactiles des champs (ACC-01) | La ligne de saisie est entourée d'une zone sémantique de 48 px de haut. | Le test d'accessibilité `androidTapTargetGuideline` mesurait 22 px. |
| Lignes avec une étiquette IA | En-têtes « EXPLICATION » et verdict en `Wrap` (retour à la ligne si la place manque). | Évite un débordement avec une grande taille de texte système (ACC-02). |
| Thème sombre (43.11) | `violetFonce` devient `#B8A9FF` en sombre (liens et libellés sur fond sombre). | « Toute couleur non listée est dérivée en conservant les contrastes » ; `#4B2FD6` sur `#1F1B45` est illisible. |
| Exporter mes données (S) | Copie du JSON complet dans le presse-papiers. | Évite une dépendance de sélection de fichier ; fonctionne sur le web et Android. |
| Rappels pendant l'usage (NOT-08) | Pendant que l'application est au premier plan, le rappel du jour n'est pas programmé ; il l'est quand l'application passe en arrière-plan. | « Pas de notification pendant que l'application est ouverte ». |
| Fiche sur mobile pendant l'enrichissement | L'interrogation toutes les 3 s lance un cycle de synchronisation (90 s au plus). | Sur mobile la fiche vient du cache ; seul le pull apporte la fiche enrichie. |
| Signature de l'APK | Sans `android/key.properties`, le build `release` est signé avec la clé de débogage (pour vérifier la compilation seulement). L'APK à installer doit être signé avec la clé créée par l'utilisateur (AND-14, README). | La clé et son mot de passe sont des secrets que seul l'utilisateur crée. |
| Version minimale d'Android | `minSdk = 26` (Android 8.0). | AND-01 (à confirmer). |

## Mise en service sans compte ni droits administrateur (2026-10-12)

Demande de l'utilisateur : une version complètement fonctionnelle, en s'autorisant à sortir du cahier des charges pour le backend.

| Question | Choix | Raison |
| --- | --- | --- |
| Aucune clé Musixmatch, Genius ni DeepL | Sources gratuites sans clé : **LRCLIB** pour les paroles (recherche par artiste, paroles renvoyées avec la recherche, une seule requête par artiste), **Deezer** pour la recherche d'artistes et leurs photos, **Ollama** pour la traduction (prompt `traduction-v1`). Si une clé est renseignée dans `.env`, le service payant correspondant reprend la priorité. Seul l'extrait de 240 caractères est conservé (C1, MAT-16 inchangés). | Les comptes ne peuvent être créés que par l'utilisateur ; le système doit fonctionner sans. |
| Identifiants LRCLIB | Stockés dans `morceau.musixmatch_track_id` (identifiant du morceau chez la source). | Évite une migration ; une seule source est active à la fois. |
| Recherche « hors liste » avec LRCLIB | Recherche sur le titre, l'artiste et l'album (LRCLIB ne cherche pas dans les paroles), puis détection du mot dans les paroles reçues. | Limite de l'API gratuite. |
| Quotas | Migration `0002` : `lrclib` et `deezer` ajoutés au suivi `quota_api` (sans limite journalière). | QUO-01. |
| PostgreSQL | Binaires PostgreSQL 16.2 autonomes (ceux de `pgserver`) copiés dans `C:/lyrics-vocab/postgresql`, base dans `C:/lyrics-vocab/pgdata`, démarrés par `start_backend.ps1` avant le backend. Pas de base de fuseaux dans ce build : le serveur reste en `GMT`, tous les calculs de jour local sont faits en Python. | L'installateur officiel demande les droits administrateur ; ces binaires suffisent et incluent `pg_dump`, `pg_restore` et `psql`. |
| Démarrage automatique (ENV-02) | Tâches planifiées à l'ouverture de session de l'utilisateur, sans droits administrateur. Option `-AuDemarrage` (administrateur) pour démarrer avec Windows sans session. `start_backend.ps1` relance le backend une minute après tout arrêt. | La création de tâches « au démarrage du PC » exige un compte administrateur et le mot de passe Windows. |
| Copie des sauvegardes (SAV-02) | Dossier OneDrive de l'utilisateur (seul disque : C:). | Copie hors du PC sans matériel supplémentaire. |
| Clé de signature de l'APK | Générée avec un mot de passe aléatoire, stockée dans `C:/lyrics-vocab/secrets` (hors dépôt, droits limités au compte). | AND-14 ; à sauvegarder hors du PC par l'utilisateur. |
| `IA_TIMEOUT_S` | 60 s en production. | Le premier appel charge le modèle en mémoire ; 30 s se sont révélées justes sur ce PC. |
| Fuseau du PC | `Africa/Casablanca` (fuseau Windows « Morocco Standard Time »). | ALG-15. |
| Titres renvoyés par LRCLIB | Préfixe « Artiste - » et mentions « [Official Audio] », « (Official Video) »… retirés. | Affichage propre de la ligne « Titre — Artiste ». |

## Retours de l'utilisateur (2026-10-13)

| Demande | Choix | Raison |
| --- | --- | --- |
| Lien vers chaque chanson | Pendant l'enrichissement, le lien Deezer de la chanson (Genius si un jeton est configuré) est cherché et stocké dans `morceau.url_genius` ; l'application affiche « Écouter la chanson », avec une recherche YouTube si aucun lien n'a été trouvé. | Demande explicite ; le champ existait déjà dans le contrat (18.2). |
| Exercice d'utilisation visible | Écran d'exercice dédié ouvert depuis la fiche (« S'entraîner avec ce mot », entraînement libre sans effet sur SM-2) et « Session d'exercices » sur l'accueil des révisions (chaque mot traduit devient un exercice, le verdict alimente SM-2). Le mode Mélange (REV-12) reste disponible. | L'exercice n'apparaissait qu'en mode Mélange, désactivé par défaut. |
| Thème trop sombre | Thème clair par défaut, choix Clair, Sombre ou Système dans Réglages → Apparence (enregistré par appareil). | UI-06 suivait le système, réglé en sombre sur ce PC ; le design est clair. |
| « PC injoignable » sur le téléphone | Le téléphone n'était pas connecté à Tailscale (aucune requête reçue). Côté application : délai du test de joignabilité porté de 3 s à 10 s (SYN-06), et les fonctions qui exigent le PC tentent toujours l'appel au lieu de se fier à l'état de connexion. | Relais Tailscale sur réseau mobile ; état de connexion pas encore connu au premier écran. |
| Pas de photos d'artistes sur le téléphone | Les suggestions sont toujours demandées au serveur (photos Deezer) ; la liste sans photo ne sert qu'en cas d'échec. | Conséquence du point précédent. |
| APK « incompatible » | APK universel (arm64-v8a, armeabi-v7a, x86_64, 52 Mo) au lieu de l'APK arm64 seul. | Certains Galaxy A13 ont un Android 32 bits. |

## Exigences [S] non réalisées (reportées en v2, REC-03)

- NOT-09 : relance 3 heures après la notification.
- DES-08 : tests « golden » des quatre écrans (les écrans ont été comparés aux planches par captures à 390 px, voir ci-dessous).
- FLU-10 : synchronisation périodique en arrière-plan (hors v1 par défaut).
- SAV-07 : chiffrement des sauvegardes copiées dans un cloud (dépend du service choisi).
- MAT-10 et MAT-11 sont réalisés ; TRA-05 (traduction de l'extrait entier à la demande) ne l'est pas.

## Comparaison aux planches (DES-36)

Captures de la PWA à 390 × 844 comparées aux fichiers de `Docs/design` le 2026-10-12 :

- Choix des artistes : identique (en-tête, grille 3 colonnes, anneau et coche, panneau du bas).
- Révisions du jour : identique (en-tête 330, carte à 200, réponses à 540, aide à 620) ; écart justifié : bouton fermer en surimpression et série masquée pendant la session.
- Fiche d'un mot : identique (en-tête 250, cartes à 220, étiquette IA à droite, tuiles) ; écart justifié : boutons retour et « … » en surimpression.
- Bibliothèque : identique (titre, recherche, filtres, cartes, bouton « + » à 104 du bas) ; écart justifié : icône de tri dans le champ de recherche.
