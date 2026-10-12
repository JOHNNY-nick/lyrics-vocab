"""Erreurs, en-têtes, compression, limite de débit, journaux (41.3, K.6)."""

import json
import logging
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.core import errors
from app.core.config import Parametres
from app.core.logging import configurer_journaux, journaliser
from app.main import creer_app

CODES = [
    (errors.TermeInvalide, 422, "terme_invalide"),
    (errors.MotIntrouvable, 404, "mot_introuvable"),
    (errors.RevisionDejaRepondue, 409, "revision_deja_repondue"),
    (errors.QuotaDepasse, 429, "quota_depasse"),
    (errors.ServiceIndisponible, 503, "service_indisponible"),
    (errors.IaIndisponible, 503, "ia_indisponible"),
    (errors.OperationInconnue, 400, "operation_inconnue"),
    (errors.CurseurInvalide, 400, "curseur_invalide"),
]


@pytest.mark.parametrize(("classe", "statut", "code"), CODES)
def test_forme_des_erreurs(classe, statut, code):
    erreur = classe()
    assert erreur.statut_http == statut
    assert set(erreur.corps()) == {"code", "message", "details"} and erreur.corps()["code"] == code
    assert erreur.message


def test_erreur_interne_sans_trace(parametres, services, base_vide):
    """API-T05 : aucune trace de pile ; le journal porte l'identifiant de corrélation."""
    app = creer_app(parametres, services, demarrer_taches=False)

    @app.get("/api/test-panne")
    def panne():
        raise RuntimeError("détail technique secret")

    app.router.routes.insert(0, app.router.routes.pop())  # avant le montage de la PWA
    with TestClient(app, raise_server_exceptions=False) as client:
        reponse = client.get("/api/test-panne", headers={"X-Request-Id": "corr-123"})
    assert reponse.status_code == 500
    corps = reponse.json()
    assert corps["code"] == "erreur_interne" and "secret" not in reponse.text
    assert "Traceback" not in reponse.text
    journal = (Path(parametres.log_dir) / "backend.jsonl").read_text(encoding="utf-8")
    ligne = next(json.loads(x) for x in journal.splitlines() if '"erreur_interne"' in x)
    assert ligne["correlation_id"] == "corr-123"
    logging.getLogger("lyrics_vocab").handlers.clear()


def test_en_tetes_cache(client):
    index = client.get("/")
    assert index.status_code == 200 and index.headers["cache-control"] == "no-cache"
    assert client.get("/flutter_service_worker.js").headers["cache-control"] == "no-cache"
    script = client.get("/main.dart.js")
    assert "max-age=31536000" in script.headers["cache-control"]
    assert client.get("/un/chemin/de/la/pwa").text == "<html>PWA</html>"
    assert client.get("/api/inexistant").status_code == 404


def test_gzip(client):
    reponse = client.get("/main.dart.js", headers={"Accept-Encoding": "gzip"})
    assert reponse.headers.get("content-encoding") == "gzip"


def test_correlation_renvoyee(client):
    assert (
        client.get("/api/health", headers={"X-Request-Id": "abc"}).headers["x-request-id"] == "abc"
    )
    assert client.get("/api/health").headers["x-request-id"]


def test_limite_debit(parametres, services, base_vide):
    """SEC-T02 : 100 requêtes en une minute : 429 après 60."""
    parametres.limite_requetes_min = 60
    app = creer_app(parametres, services, demarrer_taches=False)
    with TestClient(app) as client:
        statuts = [
            client.get("/api/reglages", headers={"X-Appareil-Id": "pwa-1"}).status_code
            for _ in range(100)
        ]
        assert statuts[:60] == [200] * 60 and set(statuts[60:]) == {429}
        assert client.get("/api/health", headers={"X-Appareil-Id": "pwa-1"}).status_code == 200
        assert client.get("/api/reglages", headers={"X-Appareil-Id": "autre"}).status_code == 200


def test_journaux_sans_secret(tmp_path):
    """LOG-T02 / QUO-07 : aucune clé ni texte sensible dans les journaux."""
    configurer_journaux(tmp_path, 10, 14, ["cle-tres-secrete-123"])
    journaliser(
        "appel_externe",
        service="musixmatch",
        url="https://api/x?apikey=cle-tres-secrete-123",
        api_key="valeur",
        statut="ok",
    )
    contenu = (tmp_path / "backend.jsonl").read_text(encoding="utf-8")
    assert "cle-tres-secrete-123" not in contenu and "valeur" not in contenu
    ligne = json.loads(contenu.splitlines()[0])
    assert {"horodatage", "niveau", "composant", "correlation_id", "evenement"} <= set(ligne)
    logging.getLogger("lyrics_vocab").handlers.clear()


def test_rotation_journaux(tmp_path):
    """LOG-T03 : rotation au-delà de la taille maximale."""
    configurer_journaux(tmp_path, 1, 14)
    for _ in range(3000):
        journaliser("requete_http", chemin="/api/x" + "y" * 400, statut=200)
    assert (tmp_path / "backend.jsonl.1").exists()
    logging.getLogger("lyrics_vocab").handlers.clear()


def test_configuration_obligatoire(monkeypatch, tmp_path):
    """T-02 : démarrage refusé si DATABASE_URL manque."""
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.chdir(tmp_path)
    with pytest.raises(Exception, match="database_url"):
        Parametres(_env_file=None)


def test_configuration_publique_sans_secret():
    parametres = Parametres(
        database_url="postgresql://u:motdepasse@h/b", deepl_api_key="cle:fx", _env_file=None
    )
    publique = json.dumps(parametres.configuration_publique())
    assert "motdepasse" not in publique and "cle:fx" not in publique
    assert parametres.database_url.startswith("postgresql+psycopg://")
    assert "motdepasse" in parametres.valeurs_secretes()


def test_migration_non_appliquee_refuse_le_demarrage(parametres, services, base_vide):
    from sqlalchemy import text

    with base_vide.begin() as connexion:
        connexion.execute(text("UPDATE alembic_version SET version_num='0000'"))
    try:
        app = creer_app(parametres, services, demarrer_taches=False)
        with pytest.raises(RuntimeError, match="alembic upgrade head"), TestClient(app):
            pass
    finally:
        with base_vide.begin() as connexion:
            connexion.execute(text("UPDATE alembic_version SET version_num='0001'"))
