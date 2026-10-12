# Liste des secrets

Noms et emplacements uniquement : aucune valeur ici ni dans Git (SEC-02, 33). Chaque secret est sauvegardé séparément, hors du dépôt (SAV-08).

| Secret | Emplacement | Utilisé par | Sauvegarde |
| --- | --- | --- | --- |
| `DATABASE_URL` (mot de passe PostgreSQL) | `C:/lyrics-vocab/depot/backend/.env` | backend | copie du `.env` sur un support séparé |
| Mot de passe PostgreSQL pour les scripts | `%APPDATA%\postgresql\pgpass.conf` | sauvegarde, contrôle, restauration | idem |
| `MUSIXMATCH_API_KEY` | `backend/.env` | backend | régénérable chez Musixmatch |
| `GENIUS_TOKEN` | `backend/.env` | backend | régénérable chez Genius |
| `DEEPL_API_KEY` | `backend/.env` | backend | régénérable chez DeepL |
| Clé de signature `upload-keystore.jks` | `C:/lyrics-vocab/secrets/` | build de l'APK | **indispensable** : sans elle, les mises à jour de l'APK sont refusées (CL-31) |
| Mots de passe de la clé de signature | `app/android/key.properties` | build de l'APK | gestionnaire de mots de passe |
| Mot de passe Windows du compte du backend | Planificateur de tâches | tâches planifiées | — |
| Compte Tailscale | console Tailscale | réseau privé | gestionnaire de mots de passe, double authentification conseillée |

Rotation d'une clé d'API : voir README, « Changer de modèle Ollama ou d'une clé d'API ».
