"""Fixtures : PostgreSQL de test (pgserver), migrations, application avec doubles (DT-01)."""

import os
import shutil
import tempfile
import uuid
from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from app.core.config import DOSSIER_BACKEND, Parametres
from app.core.database import creer_fabrique
from app.main import creer_app
from app.services.enrichissement import Services
from app.tests.doubles import CompteurMemoire, FauxDeepl, FauxGenius, FauxMusixmatch, FauxOllama

TABLES = "quota_api, sync_op, revision, extrait, morceau, artiste, mot, reglage"
ID_REGLAGE = "00000000-0000-0000-0000-000000000001"


def _url_serveur() -> tuple[str, object | None]:
    """URL d'une base de test : TEST_DATABASE_URL, sinon un PostgreSQL éphémère (pgserver)."""
    url = os.environ.get("TEST_DATABASE_URL")
    if url:
        return url, None
    import pgserver

    dossier = tempfile.mkdtemp(prefix="lv_pg_")
    serveur = pgserver.get_server(dossier, cleanup_mode="stop")
    serveur.psql("CREATE DATABASE lyrics_vocab_test;")
    base = serveur.get_uri().rsplit("/", 1)[0]
    return f"{base}/lyrics_vocab_test", (serveur, dossier)


def config_alembic(url: str) -> Config:
    """Configuration Alembic pointant vers la base de test."""
    config = Config(str(DOSSIER_BACKEND / "alembic.ini"))
    config.set_main_option("script_location", str(DOSSIER_BACKEND / "migrations"))
    config.set_main_option("sqlalchemy.url", url)
    return config


@pytest.fixture(scope="session")
def url_base() -> Iterator[str]:
    url, ressources = _url_serveur()
    url = url.replace("postgresql://", "postgresql+psycopg://", 1)
    command.upgrade(config_alembic(url), "head")
    yield url
    if ressources:
        serveur, dossier = ressources
        try:
            serveur.cleanup()
        except Exception:
            pass
        shutil.rmtree(dossier, ignore_errors=True)


@pytest.fixture(scope="session")
def moteur(url_base):
    moteur = create_engine(url_base, future=True)
    yield moteur
    moteur.dispose()


@pytest.fixture
def base_vide(moteur):
    """Vide les tables et remet la ligne de réglages (une base propre par test)."""
    with moteur.begin() as connexion:
        connexion.execute(text(f"TRUNCATE {TABLES} CASCADE"))
        connexion.execute(text(f"INSERT INTO reglage (id) VALUES ('{ID_REGLAGE}')"))
    return moteur


@pytest.fixture
def fabrique(base_vide):
    return creer_fabrique(base_vide)


@pytest.fixture
def parametres(url_base, tmp_path) -> Parametres:
    statique = tmp_path / "web"
    statique.mkdir()
    (statique / "index.html").write_text("<html>PWA</html>", encoding="utf-8")
    (statique / "main.dart.js").write_text("console.log('x');" * 200, encoding="utf-8")
    (statique / "flutter_service_worker.js").write_text("// sw", encoding="utf-8")
    return Parametres(
        database_url=url_base,
        log_dir=str(tmp_path / "logs"),
        static_dir=str(statique),
        fuseau_pc="Europe/Paris",
        musixmatch_api_key="cle-musixmatch-secrete",
        deepl_api_key="cle-deepl:fx",
        genius_token="jeton-genius",
        limite_requetes_min=1000,
        pause_entre_appels_ms=0,
    )


@pytest.fixture
def compteur() -> CompteurMemoire:
    return CompteurMemoire()


@pytest.fixture
def services(parametres, fabrique, compteur) -> Services:
    async def sans_pause(_: float) -> None:
        return None

    return Services(
        parametres=parametres,
        fabrique=fabrique,
        compteur=compteur,
        paroles=FauxMusixmatch(compteur),
        genius=FauxGenius(compteur),
        deepl=FauxDeepl(compteur),
        ollama=FauxOllama(compteur),
        dormir=sans_pause,
    )


@pytest.fixture
def client(parametres, services, base_vide) -> Iterator[TestClient]:
    app = creer_app(parametres, services, demarrer_taches=False)
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client


def nouvel_id() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def creer_mot(client):
    def _creer(terme: str, **entetes) -> dict:
        reponse = client.post(
            "/api/mots", json={"id": nouvel_id(), "terme": terme}, headers=entetes
        )
        assert reponse.status_code in (200, 201), reponse.text
        return reponse.json()

    return _creer


def chemin_tests() -> Path:
    return Path(__file__).parent
