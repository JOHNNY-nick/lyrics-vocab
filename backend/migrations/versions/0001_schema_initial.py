"""Schéma initial : tables, index, séquence seq_sync, déclencheurs, ligne de réglages (BDD-16).

Révision : 0001
Précédente :
Créée le : 2026-10-12
"""

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

TABLES_SYNCHRONISEES = ("mot", "artiste", "extrait", "revision", "reglage")
ID_REGLAGE = "00000000-0000-0000-0000-000000000001"

SQL_CREATION = """
CREATE SEQUENCE seq_sync AS bigint START 1;

CREATE OR REPLACE FUNCTION fn_sync_stamp() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  NEW.server_seq := nextval('seq_sync');
  IF TG_OP = 'INSERT' AND NEW.created_at IS NULL THEN
    NEW.created_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE mot (
  id                    uuid PRIMARY KEY,
  terme                 text NOT NULL CONSTRAINT ck_mot_terme
                        CHECK (char_length(terme) BETWEEN 1 AND 100),
  terme_normalise       text NOT NULL CONSTRAINT ck_mot_terme_normalise
                        CHECK (char_length(terme_normalise) BETWEEN 1 AND 100),
  traduction_fr         text CONSTRAINT ck_mot_traduction CHECK (char_length(traduction_fr) <= 200),
  explication           text CONSTRAINT ck_mot_explication CHECK (char_length(explication) <= 400),
  source_explication    text CONSTRAINT ck_mot_source_explication
                        CHECK (source_explication IN ('ia','traduction_seule')),
  statut_enrichissement text NOT NULL DEFAULT 'en_attente' CONSTRAINT ck_mot_statut_enrichissement
                        CHECK (statut_enrichissement IN ('en_attente','en_cours','ok','partiel','echec')),
  erreur_enrichissement text,
  enrichi_le            timestamptz,
  niveau                text NOT NULL DEFAULT 'nouveau' CONSTRAINT ck_mot_niveau
                        CHECK (niveau IN ('nouveau','en_cours','acquis')),
  nb_echecs             integer NOT NULL DEFAULT 0 CONSTRAINT ck_mot_nb_echecs CHECK (nb_echecs >= 0),
  derniere_revision_le  timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz,
  server_seq            bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX uq_mot_terme ON mot (terme_normalise) WHERE deleted_at IS NULL;
CREATE INDEX ix_mot_seq ON mot (server_seq);
CREATE INDEX ix_mot_niveau ON mot (niveau);
CREATE INDEX ix_mot_created ON mot (created_at);

CREATE TABLE artiste (
  id uuid PRIMARY KEY,
  nom text NOT NULL,
  genius_id integer UNIQUE,
  musixmatch_id integer,
  image_url text,
  est_prefere boolean NOT NULL DEFAULT false,
  rang integer CONSTRAINT ck_artiste_rang CHECK (rang IS NULL OR rang >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  server_seq bigint NOT NULL DEFAULT 0
);
CREATE INDEX ix_artiste_pref ON artiste (est_prefere, rang);
CREATE INDEX ix_artiste_seq ON artiste (server_seq);

CREATE TABLE morceau (
  id uuid PRIMARY KEY,
  artiste_id uuid NOT NULL REFERENCES artiste(id) ON DELETE RESTRICT,
  titre text NOT NULL,
  musixmatch_track_id integer,
  genius_song_id integer,
  url_genius text,
  pochette_url text,
  UNIQUE (artiste_id, musixmatch_track_id)
);

CREATE TABLE extrait (
  id uuid PRIMARY KEY,
  mot_id uuid NOT NULL REFERENCES mot(id) ON DELETE RESTRICT,
  morceau_id uuid NOT NULL REFERENCES morceau(id) ON DELETE RESTRICT,
  texte text NOT NULL CONSTRAINT ck_extrait_texte CHECK (char_length(texte) <= 240),
  surbrillance_debut integer NOT NULL CONSTRAINT ck_extrait_debut CHECK (surbrillance_debut >= 0),
  surbrillance_fin integer NOT NULL,
  hors_liste boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  server_seq bigint NOT NULL DEFAULT 0,
  CONSTRAINT ck_extrait_fin
    CHECK (surbrillance_fin > surbrillance_debut AND surbrillance_fin <= char_length(texte))
);
CREATE UNIQUE INDEX uq_extrait ON extrait (mot_id, morceau_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_extrait_mot ON extrait (mot_id);
CREATE INDEX ix_extrait_seq ON extrait (server_seq);

CREATE TABLE revision (
  id uuid PRIMARY KEY,
  mot_id uuid NOT NULL REFERENCES mot(id) ON DELETE RESTRICT,
  date_prevue date NOT NULL,
  repetitions integer NOT NULL DEFAULT 0 CONSTRAINT ck_revision_repetitions CHECK (repetitions >= 0),
  facilite real NOT NULL DEFAULT 2.5 CONSTRAINT ck_revision_facilite CHECK (facilite >= 1.3),
  intervalle_jours integer NOT NULL DEFAULT 0 CONSTRAINT ck_revision_intervalle
                   CHECK (intervalle_jours >= 0),
  statut text NOT NULL CONSTRAINT ck_revision_statut
         CHECK (statut IN ('planifiee','faite','ignoree','doublon')),
  mode text NOT NULL CONSTRAINT ck_revision_mode CHECK (mode IN ('rappel','production')),
  phrase_source text,
  reference_en text,
  reponse_utilisateur text CONSTRAINT ck_revision_reponse
                      CHECK (char_length(reponse_utilisateur) <= 300),
  verdict text CONSTRAINT ck_revision_verdict CHECK (verdict IN ('correct','proche','incorrect')),
  verdict_repli boolean NOT NULL DEFAULT false,
  explication_verdict text CONSTRAINT ck_revision_explication_verdict
                      CHECK (char_length(explication_verdict) <= 200),
  qualite integer CONSTRAINT ck_revision_qualite CHECK (qualite BETWEEN 0 AND 5),
  repondu_le timestamptz,
  op_id uuid UNIQUE,
  appareil_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  server_seq bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX uq_revision_planifiee ON revision (mot_id)
  WHERE statut = 'planifiee' AND deleted_at IS NULL;
CREATE INDEX ix_revision_due ON revision (statut, date_prevue);
CREATE INDEX ix_revision_seq ON revision (server_seq);

CREATE TABLE reglage (
  id uuid PRIMARY KEY,
  frequence_rappels text NOT NULL DEFAULT 'quotidien' CONSTRAINT ck_reglage_frequence
    CHECK (frequence_rappels IN ('quotidien','tous_les_2_jours','desactive')),
  heure_rappel time NOT NULL DEFAULT '19:00',
  mots_par_session integer NOT NULL DEFAULT 20 CONSTRAINT ck_reglage_mots_session
    CHECK (mots_par_session BETWEEN 5 AND 100),
  mode_revision text NOT NULL DEFAULT 'rappel' CONSTRAINT ck_reglage_mode
    CHECK (mode_revision IN ('rappel','melange')),
  heure_changement_jour time NOT NULL DEFAULT '04:00',
  sync_wifi_seulement boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  server_seq bigint NOT NULL DEFAULT 0
);

CREATE TABLE sync_op (
  op_id uuid PRIMARY KEY,
  appareil_id text NOT NULL,
  type text NOT NULL,
  applique_le timestamptz NOT NULL DEFAULT now(),
  resultat jsonb NOT NULL
);

CREATE TABLE quota_api (
  api text NOT NULL CONSTRAINT ck_quota_api CHECK (api IN ('musixmatch','genius','deepl','ollama')),
  jour date NOT NULL,
  nb integer NOT NULL DEFAULT 0,
  caracteres integer NOT NULL DEFAULT 0,
  PRIMARY KEY (api, jour)
);
"""


def upgrade() -> None:
    """Crée le schéma complet."""
    op.execute(SQL_CREATION)
    for table in TABLES_SYNCHRONISEES:
        op.execute(
            f"CREATE TRIGGER tg_{table}_sync BEFORE INSERT OR UPDATE ON {table} "
            "FOR EACH ROW EXECUTE FUNCTION fn_sync_stamp();"
        )
    op.execute(f"INSERT INTO reglage (id) VALUES ('{ID_REGLAGE}');")


def downgrade() -> None:
    """Supprime tout ce que upgrade a créé."""
    op.execute(
        "DROP TABLE IF EXISTS quota_api, sync_op, reglage, revision, extrait, morceau, "
        "artiste, mot CASCADE;"
    )
    op.execute("DROP FUNCTION IF EXISTS fn_sync_stamp();")
    op.execute("DROP SEQUENCE IF EXISTS seq_sync;")
