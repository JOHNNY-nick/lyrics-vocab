# Schéma de la base (DOC-03)

Généré depuis la migration `0001` (`backend/migrations/versions/0001_schema_initial.py`). Les tables marquées « sync » portent `created_at`, `updated_at`, `deleted_at` et `server_seq`, posés par le déclencheur `fn_sync_stamp` à partir de la séquence `seq_sync`.

```mermaid
erDiagram
    mot ||--o{ extrait : "a"
    mot ||--o{ revision : "a"
    artiste ||--o{ morceau : "a"
    morceau ||--o{ extrait : "source de"

    mot {
        uuid id PK
        text terme
        text terme_normalise "unique si non supprimé"
        text traduction_fr
        text explication
        text source_explication "ia | traduction_seule"
        text statut_enrichissement "en_attente | en_cours | ok | partiel | echec"
        text niveau "nouveau | en_cours | acquis"
        int nb_echecs
    }
    artiste {
        uuid id PK
        text nom
        int genius_id "unique"
        int musixmatch_id
        bool est_prefere
        int rang
    }
    morceau {
        uuid id PK
        uuid artiste_id FK
        text titre
        int musixmatch_track_id "unique avec artiste_id"
    }
    extrait {
        uuid id PK
        uuid mot_id FK
        uuid morceau_id FK
        text texte "240 caractères au plus"
        int surbrillance_debut
        int surbrillance_fin
        bool hors_liste
    }
    revision {
        uuid id PK
        uuid mot_id FK
        date date_prevue
        int repetitions
        real facilite
        int intervalle_jours
        text statut "planifiee (une par mot) | faite | ignoree | doublon"
        text mode "rappel | production"
        int qualite
        uuid op_id "unique"
    }
    reglage {
        uuid id PK "00000000-0000-0000-0000-000000000001"
        text frequence_rappels
        time heure_rappel
        int mots_par_session
        text mode_revision
        time heure_changement_jour
        bool sync_wifi_seulement
    }
    sync_op {
        uuid op_id PK
        text appareil_id
        text type
        jsonb resultat
    }
    quota_api {
        text api PK
        date jour PK
        int nb
        int caracteres
    }
```

Tables synchronisées : `mot`, `artiste`, `extrait`, `revision`, `reglage`. Tables locales au serveur : `morceau`, `sync_op`, `quota_api`.
