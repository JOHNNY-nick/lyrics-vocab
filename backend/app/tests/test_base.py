"""Recette de la partie B : migrations, déclencheurs, contraintes (BDD-T01 à BDD-T08)."""

import time
import uuid
from datetime import date, timedelta

import pytest
from alembic import command
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError

from app.models import Mot, Revision
from app.services import mots, revisions
from app.tests.conftest import config_alembic


def test_migrations_aller_retour(url_base):
    """BDD-T01 : toutes les migrations s'annulent puis se réappliquent sans erreur."""
    config = config_alembic(url_base)
    command.downgrade(config, "base")
    moteur = create_engine(url_base)
    tables = set(inspect(moteur).get_table_names()) - {"alembic_version"}
    assert tables == set()
    command.upgrade(config, "head")
    tables = set(inspect(moteur).get_table_names())
    assert {
        "mot",
        "artiste",
        "morceau",
        "extrait",
        "revision",
        "reglage",
        "sync_op",
        "quota_api",
    } <= tables
    with moteur.connect() as connexion:
        assert connexion.execute(text("SELECT count(*) FROM reglage")).scalar() == 1
    moteur.dispose()


def test_doublon_casse(fabrique):
    """BDD-T02 : deux créations du même terme avec des casses différentes : un seul mot."""
    with fabrique() as session:
        premier, cree1 = mots.creer_mot(session, uuid.uuid4(), "Lowkey", date(2026, 10, 12))
        second, cree2 = mots.creer_mot(session, uuid.uuid4(), "lowkey", date(2026, 10, 12))
        session.commit()
        assert cree1 and not cree2 and premier.id == second.id
        assert session.query(Mot).count() == 1


def test_declencheur_server_seq(fabrique, base_vide):
    """BDD-T03 : updated_at et server_seq changent ; une valeur imposée est écrasée."""
    mot_id = uuid.uuid4()
    with base_vide.begin() as connexion:
        connexion.execute(
            text(
                "INSERT INTO mot (id, terme, terme_normalise, server_seq, updated_at) "
                "VALUES (:id, 'x', 'x', 999999, '2000-01-01')"
            ),
            {"id": mot_id},
        )
        seq1, maj1 = connexion.execute(
            text("SELECT server_seq, updated_at FROM mot WHERE id=:id"), {"id": mot_id}
        ).one()
    assert seq1 != 999999 and maj1.year != 2000
    time.sleep(0.01)
    with base_vide.begin() as connexion:
        connexion.execute(
            text("UPDATE mot SET niveau='en_cours', server_seq=5 WHERE id=:id"), {"id": mot_id}
        )
        seq2, maj2 = connexion.execute(
            text("SELECT server_seq, updated_at FROM mot WHERE id=:id"), {"id": mot_id}
        ).one()
    assert seq2 > seq1 and maj2 > maj1


def test_suppression_logique(fabrique):
    """BDD-T04 : le mot, ses extraits et sa révision planifiée portent deleted_at."""
    with fabrique() as session:
        mot, _ = mots.creer_mot(session, uuid.uuid4(), "vibe", date(2026, 10, 12))
        session.execute(
            text("INSERT INTO artiste (id, nom) VALUES (:a, 'A')"), {"a": (a := uuid.uuid4())}
        )
        session.execute(
            text("INSERT INTO morceau (id, artiste_id, titre) VALUES (:m, :a, 'T')"),
            {"m": (m := uuid.uuid4()), "a": a},
        )
        session.execute(
            text(
                "INSERT INTO extrait (id, mot_id, morceau_id, texte, surbrillance_debut, "
                "surbrillance_fin) VALUES (:e, :mot, :m, 'good vibe', 5, 9)"
            ),
            {"e": uuid.uuid4(), "mot": mot.id, "m": m},
        )
        session.commit()
        mots.supprimer_mot(session, mot.id)
        session.commit()
        lignes = session.execute(
            text(
                "SELECT (SELECT count(*) FROM mot WHERE deleted_at IS NOT NULL), "
                "(SELECT count(*) FROM extrait WHERE deleted_at IS NOT NULL), "
                "(SELECT count(*) FROM revision WHERE deleted_at IS NOT NULL), "
                "(SELECT count(*) FROM mot) + (SELECT count(*) FROM extrait)"
            )
        ).one()
        assert tuple(lignes) == (1, 1, 1, 2)


def test_unique_planifiee(fabrique):
    """BDD-T05 : deux révisions planifiées pour le même mot sont refusées."""
    with fabrique() as session:
        mot, _ = mots.creer_mot(session, uuid.uuid4(), "gonna", date(2026, 10, 12))
        session.commit()
        session.add(
            Revision(
                id=uuid.uuid4(),
                mot_id=mot.id,
                date_prevue=date(2026, 10, 13),
                statut="planifiee",
                mode="rappel",
            )
        )
        with pytest.raises(IntegrityError):
            session.commit()


def test_check_extrait_trop_long(fabrique):
    """BDD-T07 : un extrait de 241 caractères est refusé."""
    with fabrique() as session:
        mot, _ = mots.creer_mot(session, uuid.uuid4(), "lowkey", date(2026, 10, 12))
        a, m = uuid.uuid4(), uuid.uuid4()
        session.execute(text("INSERT INTO artiste (id, nom) VALUES (:a, 'A')"), {"a": a})
        session.execute(
            text("INSERT INTO morceau (id, artiste_id, titre) VALUES (:m, :a, 'T')"),
            {"m": m, "a": a},
        )
        session.commit()
        with pytest.raises(IntegrityError):
            session.execute(
                text(
                    "INSERT INTO extrait (id, mot_id, morceau_id, texte, surbrillance_debut, "
                    "surbrillance_fin) VALUES (:e, :mot, :m, :t, 0, 6)"
                ),
                {"e": uuid.uuid4(), "mot": mot.id, "m": m, "t": "lowkey" + "x" * 235},
            )


def test_check_statut_inconnu(base_vide):
    """BDD-T08 : un statut_enrichissement inconnu est refusé."""
    with pytest.raises(IntegrityError), base_vide.begin() as connexion:
        connexion.execute(
            text(
                "INSERT INTO mot (id, terme, terme_normalise, statut_enrichissement) "
                "VALUES (:id, 'x', 'x', 'inconnu')"
            ),
            {"id": uuid.uuid4()},
        )


def test_volumetrie_revisions_du_jour(base_vide, fabrique):
    """BDD-T06 / BDD-20 : 100 000 révisions, requête des révisions du jour sous 50 ms."""
    with base_vide.begin() as connexion:
        connexion.execute(
            text(
                """
            INSERT INTO mot (id, terme, terme_normalise)
            SELECT gen_random_uuid(), 'm' || g, 'm' || g FROM generate_series(1, 5000) g;
            INSERT INTO revision (id, mot_id, date_prevue, statut, mode)
            SELECT gen_random_uuid(), m.id, DATE '2026-01-01' + (g % 300), 'faite', 'rappel'
            FROM mot m, generate_series(1, 19) g;
            INSERT INTO revision (id, mot_id, date_prevue, statut, mode)
            SELECT gen_random_uuid(), id, DATE '2026-10-01' + (random() * 30)::int, 'planifiee',
                   'rappel' FROM mot;
            ANALYZE;
        """
            )
        )
    with fabrique() as session:
        assert session.query(Revision).count() == 100000
        mesures = []
        for _ in range(3):  # REC-04 : trois mesures, la moins bonne est retenue
            debut = time.perf_counter()
            revisions.revisions_dues(session, date(2026, 10, 12), 20)
            mesures.append(time.perf_counter() - debut)
        assert max(mesures) < 0.05, mesures
        debut = time.perf_counter()
        lignes, total = mots.lister_mots(session, None, None, "created_desc", 1, 50)
        assert len(lignes) == 50 and total == 5000
        assert time.perf_counter() - debut < 0.5  # API-T06 / PERF-05
    _ = timedelta
