"""Instancie FastAPI, monte l'API sous /api et sert la PWA à la racine (39.3, ENV-09, ENV-10)."""

import asyncio
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from alembic.config import Config
from alembic.script import ScriptDirectory
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.engine import make_url
from starlette.requests import Request
from starlette.types import Scope

from app.core.config import DOSSIER_BACKEND, Parametres, obtenir_parametres
from app.core.database import attendre_base, creer_fabrique, creer_moteur
from app.core.errors import installer_gestionnaires
from app.core.locataires import Locataire, Locataires
from app.core.logging import configurer_journaux, journaliser
from app.core.middleware import CorrelationMiddleware, LimiteDebitMiddleware, TailleCorpsMiddleware
from app.core.resilience import Disjoncteur
from app.routers import artistes, mots, revisions, sante, sync
from app.services import exercices_prets, notifications_mots, reglages
from app.services.deepl_client import DeeplClient
from app.services.deezer_client import DeezerClient
from app.services.enrichissement import GestionnaireEnrichissement, Services
from app.services.genius_client import GeniusClient
from app.services.lrclib_client import LrclibClient
from app.services.musixmatch_client import MusixmatchClient
from app.services.ollama_client import OllamaClient
from app.services.quotas import CompteurQuotas
from app.version import VERSION

# Flutter ne met pas d'empreinte dans le nom de ses fichiers (main.dart.js…) : un cache long
# garderait l'ancienne version de l'application. Tout est revalidé (ETag, réponse 304).
CACHE_REVALIDE = "no-cache"
COOKIE_VERSION = "lv_version_pwa"
TAILLE_MIN_GZIP = 1000


class FichiersPwa(StaticFiles):
    """Fichiers de la PWA : no-cache pour l'amorce, cache long pour le reste (ENV-09)."""

    async def get_response(self, path: str, scope: Scope):
        path = path.replace("\\", "/")
        try:
            reponse = await super().get_response(path, scope)
        except Exception:
            reponse = None
        if reponse is None or reponse.status_code == 404:
            if path.startswith("api/"):
                return JSONResponse(
                    status_code=404,
                    content={
                        "code": "introuvable",
                        "message": "Ressource introuvable.",
                        "details": {},
                    },
                )
            reponse = FileResponse(Path(str(self.directory)) / "index.html")
            path = "index.html"
        reponse.headers["Cache-Control"] = CACHE_REVALIDE
        if Path(path).name in ("", ".", "index.html"):
            reponse = self._vider_cache_si_nouvelle_version(reponse, scope)
        return reponse

    def _vider_cache_si_nouvelle_version(self, reponse, scope: Scope):
        """Première visite d'une nouvelle version : le navigateur vide son cache HTTP, pour ne
        pas garder les fichiers d'une version précédente servis avec l'ancien cache long."""
        index = Path(str(self.directory)) / "index.html"
        try:
            infos = (Path(str(self.directory)) / "main.dart.js").stat()
        except OSError:
            return reponse
        version = f"{int(infos.st_mtime)}-{infos.st_size}"
        if Request(scope).cookies.get(COOKIE_VERSION) == version:
            return reponse
        reponse = FileResponse(index, headers={"Cache-Control": CACHE_REVALIDE})  # jamais 304
        reponse.headers["Clear-Site-Data"] = '"cache"'
        reponse.set_cookie(
            COOKIE_VERSION, version, max_age=31536000, secure=True, samesite="strict"
        )
        return reponse


def construire_services(parametres: Parametres, fabrique, http: httpx.AsyncClient) -> Services:
    """Clients externes avec disjoncteurs et compteurs de quota."""
    compteur = CompteurQuotas(fabrique, parametres)

    def disjoncteur(service: str) -> Disjoncteur:
        return Disjoncteur(service, parametres.disjoncteur_echecs, parametres.disjoncteur_pause_min)

    return Services(
        parametres=parametres,
        fabrique=fabrique,
        compteur=compteur,
        # Sans clé, les services gratuits LRCLIB et Deezer prennent le relais (DECISIONS.md).
        paroles=(
            MusixmatchClient(
                parametres.musixmatch_api_key, http, compteur, disjoncteur("musixmatch")
            )
            if parametres.musixmatch_api_key
            else LrclibClient(http, compteur, disjoncteur("lrclib"))
        ),
        genius=(
            GeniusClient(parametres.genius_token, http, compteur, disjoncteur("genius"))
            if parametres.genius_token
            else DeezerClient(http, compteur, disjoncteur("deezer"))
        ),
        deepl=DeeplClient(parametres.deepl_api_key, http, compteur, disjoncteur("deepl")),
        ollama=OllamaClient(
            http,
            parametres.ollama_url,
            parametres.ollama_model,
            compteur,
            parametres.ia_timeout_s,
            parametres.enrichissement_parallele,
        ),
    )


def verifier_migrations(moteur) -> None:
    """Refuse de démarrer si la base n'est pas à la dernière migration (39.3, étape 3)."""
    script = ScriptDirectory.from_config(Config(str(DOSSIER_BACKEND / "alembic.ini")))
    attendue = script.get_current_head()
    with moteur.connect() as connexion:
        try:
            actuelle = connexion.execute(text("SELECT version_num FROM alembic_version")).scalar()
        except Exception:
            actuelle = None
    if actuelle != attendue:
        journaliser("migration", "erreur", revision_actuelle=actuelle, revision_attendue=attendue)
        raise RuntimeError(
            f"La base est à la révision {actuelle}, la dernière est {attendue} : "
            "lance « alembic upgrade head »."
        )


def creer_app(
    parametres: Parametres | None = None,
    services: Services | None = None,
    demarrer_taches: bool = True,
) -> FastAPI:
    """Fabrique de l'application (les tests injectent paramètres et services)."""
    parametres = parametres or obtenir_parametres()

    @asynccontextmanager
    async def cycle_de_vie(app: FastAPI) -> AsyncIterator[None]:
        debut = time.perf_counter()
        dossier = Path(parametres.log_dir) if parametres.log_dir else None
        configurer_journaux(
            dossier,
            parametres.journal_taille_mo,
            parametres.journal_fichiers,
            parametres.valeurs_secretes(),
        )
        moteur = creer_moteur(parametres.database_url)
        await asyncio.to_thread(attendre_base, moteur, parametres.attente_base_s)
        if parametres.verifier_migrations:
            verifier_migrations(moteur)
        fabrique = creer_fabrique(moteur)
        with fabrique() as session:
            reglages.obtenir(session)
            session.commit()
        http = httpx.AsyncClient(timeout=parametres.http_timeout_s)
        conteneur = services or construire_services(parametres, fabrique, http)
        gestion = GestionnaireEnrichissement(conteneur)
        app.state.parametres = parametres
        app.state.moteur = moteur
        app.state.fabrique_sessions = fabrique
        app.state.services = conteneur
        app.state.gestionnaire = gestion
        principal = Locataire(
            make_url(parametres.database_url).database, fabrique, conteneur, gestion
        )
        locataires = Locataires(parametres, principal, demarrer_taches, asyncio.get_running_loop())
        app.state.locataires = locataires
        if locataires.actif:
            await asyncio.to_thread(locataires.migrer_tous)
        journaliser(
            "demarrage",
            version=VERSION,
            configuration=parametres.configuration_publique(),
            duree_connexion_base_ms=round((time.perf_counter() - debut) * 1000),
        )
        if demarrer_taches:
            gestion.demarrer()
            gestion.reprendre(au_demarrage=True)
            asyncio.create_task(conteneur.ollama.disponible())
            preparation = asyncio.create_task(
                exercices_prets.boucle(lambda: [loc.services for loc in locataires.tous()])
            )
            # Bases des utilisateurs existantes : reprise de leurs enrichissements.
            await asyncio.to_thread(locataires.tous)
            notifications = asyncio.create_task(notifications_mots.boucle(conteneur))
        try:
            yield
        finally:
            if demarrer_taches:
                preparation.cancel()
                notifications.cancel()
            for locataire in app.state.locataires.tous():
                await locataire.gestionnaire.arreter()
            await http.aclose()
            moteur.dispose()

    app = FastAPI(
        title="Lyrics & Vocab",
        version=VERSION,
        lifespan=cycle_de_vie,
        docs_url="/docs",
        redoc_url=None,
        openapi_url="/openapi.json",
    )
    installer_gestionnaires(app)
    for routeur in (sante.routeur, mots.routeur, revisions.routeur, artistes.routeur, sync.routeur):
        app.include_router(routeur)

    app.add_middleware(GZipMiddleware, minimum_size=TAILLE_MIN_GZIP)
    app.add_middleware(LimiteDebitMiddleware, limite_par_minute=parametres.limite_requetes_min)
    app.add_middleware(
        TailleCorpsMiddleware,
        max_ko=parametres.corps_max_ko,
        max_push_ko=parametres.corps_max_push_ko,
    )
    if parametres.en_developpement:
        app.add_middleware(
            CORSMiddleware,
            allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
            allow_methods=["*"],
            allow_headers=["*"],
        )
    app.add_middleware(CorrelationMiddleware)

    if parametres.apk_dir and Path(parametres.apk_dir).is_dir():
        app.mount("/apk", StaticFiles(directory=parametres.apk_dir), name="apk")
    if parametres.static_dir and Path(parametres.static_dir).is_dir():
        app.mount("/", FichiersPwa(directory=parametres.static_dir, html=True), name="pwa")
    return app


def __getattr__(nom: str):
    """`uvicorn app.main:app` crée l'application à la demande."""
    if nom == "app":
        application = creer_app()
        globals()["app"] = application
        return application
    raise AttributeError(nom)
