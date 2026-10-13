# Lyrics & Vocab

Application personnelle pour retenir le vocabulaire anglais des chansons : on saisit un mot, l'application trouve un court extrait chez ses artistes préférés, le traduit, l'explique et planifie des révisions espacées (SM-2). Deux clients partagent la même base : une PWA installée sur le PC et une application Android hors-ligne.

- **Guide d'utilisation (toutes les fonctionnalités) : [Docs/GUIDE_UTILISATION.md](Docs/GUIDE_UTILISATION.md)**
- Cahier des charges : [Docs/Cahier des charges — Lyrics & Vocab.md](Docs/Cahier%20des%20charges%20—%20Lyrics%20&%20Vocab.md) (fait foi)
- Décisions et écarts : [DECISIONS.md](DECISIONS.md)
- Recette à remplir : [Docs/RECETTE.md](Docs/RECETTE.md) · Notes de version : [Docs/NOTES_DE_VERSION.md](Docs/NOTES_DE_VERSION.md) · Secrets : [Docs/SECRETS.md](Docs/SECRETS.md)

```
Téléphone Android (APK) ─┐                      PC Windows
                         ├─ Tailscale ─ tailscale serve (HTTPS 443)
Fenêtre PWA sur le PC ───┘                 └─ FastAPI 127.0.0.1:8000 (API /api, PWA à la racine)
                                               ├─ PostgreSQL 127.0.0.1:5432
                                               ├─ Ollama 127.0.0.1:11434 (llama3.1:8b)
                                               └─ Musixmatch, Genius, DeepL (Internet)
```

## Installation en service sur ce PC

Le système est installé et tourne sur ce PC depuis le 2026-10-12 :

| Élément | État |
| --- | --- |
| Adresse (tailnet seulement) | https://desktop-jd3qf3s.tail971f32.ts.net |
| Backend | `C:/lyrics-vocab/depot` (clone de ce dépôt), tâche « Lyrics Vocab Backend » à l'ouverture de session, relancé s'il s'arrête |
| PostgreSQL 16 | binaires autonomes dans `C:/lyrics-vocab/postgresql`, données dans `C:/lyrics-vocab/pgdata`, démarré par la même tâche, écoute sur 127.0.0.1:5432 |
| IA | Ollama (démarrage avec Windows), modèle `llama3.1:8b` |
| Paroles, artistes, traduction | sans aucune clé : LRCLIB, Deezer, IA locale (les clés Musixmatch, Genius, DeepL restent possibles dans `.env`) |
| Sauvegardes | tâche « Lyrics Vocab Sauvegarde » chaque jour à 21:00, copie dans `OneDrive/lyrics-vocab-sauvegardes`, restauration testée |
| Secrets | `C:/lyrics-vocab/secrets` : mot de passe PostgreSQL, `pgpass.conf`, clé de signature de l'APK et son mot de passe. **À copier sur une clé USB ou dans un coffre** : sans la clé de signature, les mises à jour de l'APK seront refusées. |
| APK | `C:/lyrics-vocab/apk/lyrics-vocab.apk` (universel, 52 Mo, signé ; une copie dans `C:/Users/HP/Downloads`) |

**Installer l'application sur le téléphone (seule étape restante)** :
1. Sur le Galaxy A13, ouvrir l'application Tailscale et se connecter. **Sans Tailscale connecté sur le téléphone, l'application affiche « PC injoignable »** : le PC n'est pas accessible autrement. Activer « VPN toujours actif » et exclure Tailscale de l'optimisation de batterie.
2. Dans Chrome sur le téléphone : https://desktop-jd3qf3s.tail971f32.ts.net/apk/lyrics-vocab.apk
3. Ouvrir le fichier téléchargé, autoriser l'installation depuis Chrome, confirmer (l'avertissement d'Android est normal).
4. Au premier lancement : choisir ses artistes, autoriser les notifications.

**Installer la PWA sur le PC** : ouvrir https://desktop-jd3qf3s.tail971f32.ts.net dans Chrome ou Edge → menu → « Installer Lyrics & Vocab », puis épingler l'icône à la barre des tâches.

**Démarrage même sans ouvrir de session** (facultatif) : dans une console PowerShell administrateur, `powershell -File C:/lyrics-vocab/depot/scripts/installer_taches.ps1 -AuDemarrage` (demande le mot de passe Windows une fois).

Vérifier l'état à tout moment : `powershell -File C:/lyrics-vocab/depot/scripts/controle.ps1`.

## Contenu du dépôt

| Dossier | Contenu |
| --- | --- |
| `backend/` | FastAPI, SQLAlchemy, Alembic : API, synchronisation, enrichissement, tests pytest |
| `app/` | Flutter : PWA (web) et APK (Android), tests `flutter test` |
| `scripts/` | Démarrage, sauvegarde, restauration, contrôle, tâches planifiées, icônes, données de démo |
| `Docs/` | Cahier des charges, roadmap, planches du design (`Docs/design`), recette, notes |

## Versions (vérifiées le 2026-10-12, DEP-01)

| Composant | Version |
| --- | --- |
| Python | 3.12.8 (3.11 minimum) |
| FastAPI / Uvicorn | 0.143.0 / 0.34.0 |
| SQLAlchemy / Alembic / psycopg | 2.0.36 / 1.14.0 / 3.3.6 |
| Pydantic / pydantic-settings | 2.9.2 / 2.6.1 |
| httpx / tenacity | 0.28.1 / 9.0.0 |
| PostgreSQL | 15 ou plus (tests : 16.2 via pgserver) |
| Flutter / Dart | 3.35.7 / 3.9.2 |
| flutter_riverpod / dio / hive | 2.6.1 / 5.9 / 2.2.3 |
| flutter_local_notifications / connectivity_plus | 19.5.0 / 6.1.5 |
| Android | minSdk 26 (Android 8.0), SDK 36, JDK 17 |
| Ollama | 0.40.3, modèle `llama3.1:8b` |
| Tailscale | client Windows et Android, MagicDNS et HTTPS activés |

Toutes les versions sont épinglées dans `backend/requirements.txt` et `app/pubspec.lock`.

## Démarrage rapide en développement

```powershell
# Backend (une base de test PostgreSQL est créée automatiquement par les tests)
cd backend
python -m venv .venv
.venv/Scripts/Activate.ps1
pip install -r requirements.txt
pytest                                   # 149 tests, base PostgreSQL éphémère (pgserver)

# Application
cd ../app
flutter pub get
flutter test                             # 70 tests
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Pour lancer le backend contre une vraie base : copier `backend/.env.example` en `backend/.env`, remplir `DATABASE_URL`, puis `alembic upgrade head` et `uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload`. Avec `MODE=dev`, CORS est autorisé pour `localhost` (API-11). `python ../scripts/charger_demo.py --fiches` charge 20 mots d'exemple.

## Mise en service sur le PC (annexe 6)

Les étapes marquées **(toi)** demandent une action que le développement ne peut pas faire à ta place : compte, clé, mot de passe ou appareil.

### 1. Arborescence et dépôt

```powershell
mkdir C:/lyrics-vocab, C:/lyrics-vocab/logs, C:/lyrics-vocab/sauvegardes, C:/lyrics-vocab/apk, C:/lyrics-vocab/tmp
git clone <adresse du dépôt> C:/lyrics-vocab/depot      # ou copier ce dossier
```

### 2. PostgreSQL **(toi)**

1. Installer PostgreSQL 15 ou plus (service Windows en démarrage automatique). Dans `postgresql.conf`, vérifier `listen_addresses = 'localhost'` (ENV-01) et garder `shared_buffers` sous 1 Go (RES-03).
2. Créer la base : `createdb -U postgres -E UTF8 lyrics_vocab` (résultat attendu : aucune sortie).
3. Pour les scripts sans mot de passe (CMD-02) : créer `%APPDATA%\postgresql\pgpass.conf` contenant `127.0.0.1:5432:*:postgres:MOT_DE_PASSE`, lisible par ton compte seulement.

### 3. Clés des API **(toi, phase 03)**

| Service | Où l'obtenir | Variable |
| --- | --- | --- |
| Musixmatch | developer.musixmatch.com (plan gratuit) | `MUSIXMATCH_API_KEY` |
| Genius | genius.com/api-clients → « Generate access token » | `GENIUS_TOKEN` |
| DeepL | deepl.com/pro-api (API Free, la clé finit par `:fx`) | `DEEPL_API_KEY` |

Noter les quotas réellement constatés dans `QUOTA_MUSIXMATCH_JOUR`, `QUOTA_GENIUS_JOUR`, `QUOTA_DEEPL_MOIS` (QUO-02).

### 4. Backend

```powershell
cd C:/lyrics-vocab/depot/backend
python -m venv .venv
.venv/Scripts/Activate.ps1
pip install -r requirements.txt
copy .env.example .env          # puis remplir les valeurs (toi)
icacls .env /inheritance:r /grant:r "$env:USERNAME:(R,W)"   # ENV-05 : lisible par ton compte seulement
alembic upgrade head            # attendu : « Running upgrade  -> 0001, Schéma initial »
python ../scripts/charger_demo.py   # facultatif : les 20 mots du jeu de test (enrichis par le backend)
```

Le backend refuse de démarrer si `DATABASE_URL` manque ou si la base n'est pas à la dernière migration (message explicite dans `C:/lyrics-vocab/logs/uvicorn.log`). Il attend PostgreSQL jusqu'à 60 s (ENV-03). Ollama est facultatif.

### 5. Ollama **(toi)**

```powershell
ollama pull llama3.1:8b         # le modèle n'est pas encore sur ce PC
ollama list                     # attendu : llama3.1:8b
```

Ollama écoute sur `127.0.0.1:11434` par défaut ; ne pas définir `OLLAMA_HOST=0.0.0.0` (ENV-01).

### 6. Construire la PWA

```powershell
cd C:/lyrics-vocab/depot/app
flutter pub get
flutter build web --release
```

`STATIC_DIR` (dans `.env`) pointe vers `C:/lyrics-vocab/depot/app/build/web`. La PWA appelle l'API sur sa propre origine : `API_BASE_URL` n'est pas nécessaire pour le web servi par le backend.

### 7. Tâches planifiées (ENV-02, ENV-11, SAV-01) **(toi, en administrateur)**

```powershell
powershell -ExecutionPolicy Bypass -File C:/lyrics-vocab/depot/scripts/installer_taches.ps1 -Compte "$env:COMPUTERNAME\$env:USERNAME" -HeureSauvegarde 21:00
```

Crée « Lyrics Vocab Backend » (au démarrage, sans session ouverte, 3 relances à une minute d'intervalle) et « Lyrics Vocab Sauvegarde » (quotidienne, rattrapée au démarrage si l'heure est manquée). Le mot de passe Windows est demandé une fois et confié au Planificateur de tâches. Dans les options d'alimentation : pas de mise en veille sur secteur (ENV-06).

### 8. Tailscale (A.4) **(toi)**

1. Installer Tailscale sur le PC et le téléphone avec le même compte.
2. Console d'administration : activer MagicDNS et HTTPS ; désactiver l'expiration de clé du PC ; ne jamais activer Funnel (SEC-05).
3. Exposer le backend dans le tailnet : `tailscale serve --bg 8000`, puis `tailscale serve status` (attendu : `https://<pc>.<tailnet>.ts.net (tailnet only)` → `http://127.0.0.1:8000`).
4. Sur Android : application Tailscale connectée, « VPN toujours actif », exclue de l'optimisation de batterie.

Sur ce PC, Tailscale tourne déjà sous le nom `desktop-jd3qf3s.tail971f32.ts.net` et un `serve` existe : vérifier avec `tailscale serve status` qu'il pointe bien vers le port 8000 avant de le remplacer.

### 9. Installer la PWA (ENV-T05)

Ouvrir `https://<pc>.<tailnet>.ts.net/` dans Chrome ou Edge → menu → « Installer Lyrics & Vocab » → clic droit sur l'icône de la barre des tâches → « Épingler ». La fenêtre s'ouvre sans barre d'adresse.

### 10. APK Android (I.3) **(toi pour la clé et l'installation)**

Créer une fois la clé de signature, hors du dépôt, et la sauvegarder séparément (AND-14, SAV-08) :

```powershell
keytool -genkey -v -keystore C:/lyrics-vocab/secrets/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Créer `app/android/key.properties` (ignoré par Git) :

```
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=C:/lyrics-vocab/secrets/upload-keystore.jks
```

Construire, puis publier pour le téléphone :

```powershell
cd C:/lyrics-vocab/depot/app
# augmenter « version: 1.0.0+1 » dans pubspec.yaml à chaque build (AND-15)
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://<pc>.<tailnet>.ts.net --dart-define=APP_VERSION=1.0.0
copy build/app/outputs/flutter-apk/app-arm64-v8a-release.apk C:/lyrics-vocab/apk/lyrics-vocab.apk
Set-Content C:/lyrics-vocab/apk/version.json '{"version": "1.0.0", "fichier": "lyrics-vocab.apk"}'
Get-FileHash C:/lyrics-vocab/apk/lyrics-vocab.apk     # empreinte à noter dans les notes de version
```

`--split-per-abi` produit un APK par architecture : `app-arm64-v8a-release.apk` convient aux téléphones récents (l'APK universel fait 52,5 Mo, au-delà de l'objectif de 40 Mo de 29.2). Avec `APK_DIR=C:/lyrics-vocab/apk` dans `.env`, le téléphone télécharge l'APK sur `https://<pc>.<tailnet>.ts.net/apk/lyrics-vocab.apk` (AND-16), à travers le tailnet uniquement. Installation : autoriser l'installation depuis le navigateur ; l'avertissement d'Android est normal (AND-17). Au premier lancement, autoriser les notifications et exclure l'application de l'optimisation de batterie (NOT-07). L'adresse du serveur se change dans Réglages → Serveur, avec le bouton « Tester » (AND-05).

Sans `key.properties`, le build est signé avec la clé de débogage : il compile mais ne doit pas être installé, car les mises à jour suivantes seraient refusées (CL-31).

### 11. Contrôle final

```powershell
powershell -File C:/lyrics-vocab/depot/scripts/controle.ps1
```

Attendu : PostgreSQL, Ollama, Backend, Tailscale, Serve, Sauvegarde et Intégrité en « [ OK ] ». Puis redémarrer le PC sans ouvrir de session et vérifier `/api/health` depuis le téléphone en données mobiles (ENV-T01). Remplir ensuite [Docs/RECETTE.md](Docs/RECETTE.md).

## Procédures courantes (25.1)

### Mise à jour du backend et de la PWA (ENV-13)

```powershell
powershell -File C:/lyrics-vocab/depot/scripts/sauvegarde_quotidienne.ps1   # 1. sauvegarde (SAV-03)
cd C:/lyrics-vocab/depot; git pull                                            # 2.
cd backend; .venv/Scripts/Activate.ps1; pip install -r requirements.txt
alembic upgrade head                                                          # 3. migrations
cd ../app; flutter pub get; flutter build web --release                       # 4. PWA
Stop-ScheduledTask "Lyrics Vocab Backend"; Start-ScheduledTask "Lyrics Vocab Backend"   # 5.
Invoke-RestMethod http://127.0.0.1:8000/api/health                            # 6. contrôle
```

Dans la PWA ouverte, le message « Une nouvelle version est disponible. » propose d'actualiser (PWA-07).

**Retour arrière** si une migration échoue : `git checkout <commit précédent>`, `alembic downgrade -1` si la migration est partiellement appliquée, sinon restaurer la sauvegarde de l'étape 1 (ci-dessous), puis redémarrer la tâche.

### Sauvegarde et restauration (K.2)

- Quotidienne et automatique ; copie sur `D:/copie-lyrics-vocab` (paramètre `-Copie` à adapter : autre disque ou dossier synchronisé). Journal : `C:/lyrics-vocab/logs/sauvegarde.log`. Un échec est signalé dans Réglages → Informations (SAV-05).
- Restauration testée sur une base vide (SAV-04, chaque trimestre) :

```powershell
powershell -File C:/lyrics-vocab/depot/scripts/restaurer.ps1 -Fichier C:/lyrics-vocab/sauvegardes/lyrics_vocab_2026-10-12.dump
```

Le script crée `lyrics_vocab_restauree`, restaure, affiche le nombre de lignes par table et la durée. Pour basculer : arrêter la tâche du backend, renommer les bases (`ALTER DATABASE … RENAME TO …`), `alembic upgrade head`, redémarrer, contrôler `/api/health`.

### Mise à jour de l'APK

Augmenter la version dans `pubspec.yaml`, reconstruire avec la même clé, copier dans `C:/lyrics-vocab/apk` et mettre à jour `version.json` : l'application affiche « Une nouvelle version est disponible » dans Réglages (AND-18). Installer par-dessus : les données locales sont conservées.

### Changer de modèle Ollama ou d'une clé d'API

Modifier `OLLAMA_MODEL` ou la clé dans `.env`, redémarrer la tâche du backend, vérifier un enrichissement, puis révoquer l'ancienne clé chez le fournisseur.

### Téléphone perdu ou changé

1. Retirer l'appareil dans la console Tailscale (SEC-10).
2. Vérifier les appareils restants ; changer le mot de passe du compte Tailscale si besoin.
3. Installer l'APK sur le nouveau téléphone : une synchronisation complète restaure les données.

## Faire tester l'application à des amis

1. Dans `backend/.env`, renseigner `PROPRIETAIRE_LOGIN=<ton compte Tailscale>` puis redémarrer le backend : chaque autre compte Tailscale aura sa propre base, créée à sa première connexion.
2. Console Tailscale (https://login.tailscale.com/admin/machines) → appareil **desktop-jd3qf3s** → **⋯ → Share** → inviter l'ami par e-mail ou par lien (gratuit).
3. Lui envoyer `lyrics-vocab.apk` et le guide `Docs/GUIDE_AMIS.md`.

**Sans Tailscale (tunnel Cloudflare gratuit, déjà en service)** : la tâche planifiée « Lyrics Vocab Tunnel » lance `scripts/tunnel.ps1` à l'ouverture de session ; l'adresse `https://….trycloudflare.com` change à chaque démarrage et est publiée sur la branche `adresse` du dépôt, où l'application la retrouve seule. Chaque ami a besoin d'un code d'invitation :

```powershell
cd C:\lyrics-vocab\depotackend
.\.venv\Scripts\python.exe ..\scripts\inviter.py Prénom      # crée un code LV-XXXX-XXXX (sa bibliothèque)
.\.venv\Scripts\python.exe ..\scripts\inviter.py --liste
.\.venv\Scripts\python.exe ..\scripts\inviter.py --retirer Prénom
```

Les codes sont stockés hachés dans `C:/lyrics-vocab/secrets/codes_acces.json` (`CODES_ACCES_FICHIER`). Sans code valide, le tunnel ne donne accès qu'à `/api/health`.

Pour retirer un ami : console Tailscale → Machines → desktop-jd3qf3s → Share → révoquer. Sa base (`lyrics_vocab_u_…`) reste sur le PC ; la supprimer avec `DROP DATABASE` si besoin.

## Dépannage

| Symptôme | Vérifications |
| --- | --- |
| Téléphone : « PC injoignable » | PC allumé ? Tailscale connecté sur le téléphone ? `tailscale status`, `tailscale serve status`, `scripts/controle.ps1`, `C:/lyrics-vocab/logs/uvicorn.log` |
| La PWA affiche une ancienne version | Ctrl+Maj+R ; `curl -I https://<pc>/index.html` doit montrer `cache-control: no-cache` |
| Aucun extrait trouvé | Réglages → Informations (quotas) ; `C:/lyrics-vocab/logs/backend.jsonl` (événements `appel_externe` : statut et code) |
| Explications absentes | `ollama list`, mémoire libre, `IA_TIMEOUT_S` ; la fiche se complète à la prochaine ouverture |
| Le backend ne démarre pas | `uvicorn.log` : PostgreSQL arrêté, `.env` manquant, base pas à jour (`alembic upgrade head`), port 8000 occupé (`netstat -ano | findstr 8000`) |
| Doublons après une synchronisation | `scripts/controle.ps1` (contrôle d'intégrité) ; Réglages → « À examiner » |
| Notifications absentes | Permission Android, optimisation de batterie, mots dus le jour du rappel |

Les journaux sont au format JSON, un événement par ligne (`C:/lyrics-vocab/logs/backend.jsonl`, rotation 10 Mo × 14). Ils ne contiennent ni clé, ni texte de mot, ni paroles (LOG-04). Les 50 dernières erreurs sont aussi visibles sur `GET /api/logs/erreurs` et dans Réglages (PC).

## Calendrier d'entretien (25.3)

Hebdomadaire : erreurs récentes et quotas. Mensuel : `pip list --outdated`, `flutter pub outdated` (mises à jour de sécurité sur une branche, tests verts avant fusion, DEP-02), espace disque, copie des sauvegardes. Trimestriel : restauration chronométrée, revue des appareils Tailscale, liste v2. Annuel : clé de signature et sauvegarde des secrets.

## Design et polices (DES-07, DES-12, DES-15)

- Les jetons (couleurs, styles, espacements, rayons, ombres) sont dans `app/lib/theme/jetons.dart` ; aucun écran n'utilise de valeur visuelle en dur.
- Polices embarquées dans `app/assets/fonts` (licence SIL OFL 1.1, fichiers `OFL-*.txt`) et déclarées dans `app/pubspec.yaml` :
  `BricolageGrotesque-SemiBold.ttf` (600), `BricolageGrotesque-ExtraBold.ttf` (800), `PlusJakartaSans-Medium.ttf` (500), `PlusJakartaSans-Bold.ttf` (700).
- Icônes PWA, favicons et icônes Android (adaptative et monochrome) générées depuis le tracé vectoriel du logo : `python scripts/generer_icones.py` (Chrome ou Edge requis).

## Tests et intégration continue

- `cd backend; pytest` : SM-2, normalisation, découpe d'extrait, routes, déclencheurs, contraintes, volumétrie (100 000 révisions), enrichissement avec doubles, clients externes simulés, quotas, synchronisation, journaux. Aucun appel à une vraie API (QUAL-03).
- `cd app; flutter test` : SM-2 et normalisation (mêmes cas que Python), modèles (exemples du chapitre 18), cache, file d'actions, synchronisation, écrans (ajout, fiche, révisions, bandeaux, 360/768/1 280 px, zones tactiles).
- `.github/workflows/ci.yml` lance les deux à chaque push (QUAL-04), avec ruff, black, `dart format` et `flutter analyze`.
