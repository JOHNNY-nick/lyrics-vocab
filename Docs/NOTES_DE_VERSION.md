# Notes de version

## 1.0.0 — 2026-10-12

Première version complète du MVP.

**Backend**
- API REST sous `/api` : mots, extraits, révisions, exercices, artistes, réglages, synchronisation, santé, quotas, erreurs récentes.
- Enrichissement en tâche de fond : extraits Musixmatch (artistes préférés puis repli), traduction DeepL, explication Ollama ; cache, quotas, disjoncteur, réessais.
- SM-2 adapté (intervalles 1 et 3 jours), jour local avec heure de changement de jour.
- Synchronisation : push idempotent par `op_id`, pull par curseur `server_seq`, fusion des doublons.
- Sert la PWA avec les en-têtes de cache (`no-cache` pour l'amorce), compression gzip, limite de débit, journaux JSON avec rotation.

**Migrations**
- `0001` : schéma initial (tables, index partiels, séquence `seq_sync`, déclencheurs, ligne de réglages). Réversible.

**Application**
- PWA et APK Flutter : choix des artistes, révisions du jour (rappel et exercice), fiche, bibliothèque, ajout, réglages.
- Android : hors-ligne d'abord (Hive), file d'actions, liste « À examiner », notifications locales.

**Empreinte de l'APK publié** : à renseigner (`Get-FileHash`) à chaque publication.
