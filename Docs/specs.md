# Lyrics & Vocab — specs d'une page

**But** : retenir le vocabulaire anglais des chansons. Je saisis un mot ; l'application trouve un extrait de 1 à 2 lignes chez mes artistes, le traduit, l'explique et me le fait réviser au bon moment.

**Écrans** : Choix des artistes (premier lancement) · Révisions du jour (accueil quand des mots sont dus) · Fiche d'un mot · Bibliothèque · Ajouter un mot · Réglages. Design : `Docs/design`.

**Périmètre v1** : un seul utilisateur, PC Windows (PWA) et téléphone Android (APK) sur la même base PostgreSQL du PC, accès par Tailscale ; hors-ligne complet sur le téléphone ; rappels locaux Android ; aucune parole complète stockée (extraits de 240 caractères au plus).

**Jeu de test** : les 20 mots de `scripts/charger_demo.py` (6 argots au moins, 3 polysémiques, 5 expressions, 2 contractions, 1 mot absent). À remplacer par mes propres mots difficiles, avec leur chanson d'origine (TEST-01), et mes 5 à 10 artistes préférés par ordre de priorité (TEST-02).

**Liste v2** : voir `Docs/JOURNAL_FRICTIONS.md`.
