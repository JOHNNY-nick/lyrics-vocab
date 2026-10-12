"""Santé, quotas et dernières erreurs (API-34, OBS-01, OBS-03, LOG-05)."""

import json
import shutil
from datetime import UTC, datetime
from pathlib import Path

from fastapi import APIRouter, Query, Request
from sqlalchemy import text

from app.core.logging import FICHIER_JOURNAL, erreurs_recentes
from app.schemas.communs import format_utc
from app.services.sync_service import curseur_serveur
from app.version import VERSION

routeur = APIRouter(prefix="/api", tags=["santé"])
ESPACE_DISQUE_ALERTE_OCTETS = 1024**3
FICHIER_VERSION_APK = "version.json"
MARQUEUR_SAUVEGARDE = "derniere_reussie.txt"
AGE_MAX_SAUVEGARDE_JOURS = 2


def _version_apk(dossier: str | None) -> dict | None:
    if not dossier:
        return None
    fichier = Path(dossier) / FICHIER_VERSION_APK
    try:
        return json.loads(fichier.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _sauvegarde(dossier: str) -> tuple[str | None, bool]:
    """Date de la dernière sauvegarde réussie et alerte si elle date de plus de 2 jours (SAV-05)."""
    try:
        texte = (Path(dossier) / MARQUEUR_SAUVEGARDE).read_text(encoding="utf-8-sig").strip()
        jour = datetime.strptime(texte, "%Y-%m-%d").date()
    except (OSError, ValueError):
        return None, True
    return jour.isoformat(), (datetime.now(UTC).date() - jour).days > AGE_MAX_SAUVEGARDE_JOURS


@routeur.get("/health")
def sante(request: Request) -> dict:
    """État de la base (obligatoire) et d'Ollama (facultatif), sans appel externe."""
    try:
        with request.app.state.fabrique_sessions() as session:
            session.execute(text("SELECT 1"))
            base, curseur = "ok", curseur_serveur(session)
    except Exception:
        base, curseur = "indisponible", None
    etat_ollama = request.app.state.services.ollama.etat_en_cache()
    parametres = request.app.state.parametres
    derniere_sauvegarde, alerte_sauvegarde = _sauvegarde(parametres.backup_dir)
    disque = None
    try:
        disque = shutil.disk_usage(parametres.log_dir).free < ESPACE_DISQUE_ALERTE_OCTETS
    except OSError:
        pass
    return {
        "status": "ok" if base == "ok" else "degrade",
        "version": VERSION,
        "version_client_min": parametres.version_client_min,
        "base": base,
        "ollama": {True: "ok", False: "indisponible", None: "inconnu"}[etat_ollama],
        "curseur": curseur,
        "heure_serveur": format_utc(datetime.now(UTC)),
        "alerte_disque": bool(disque),
        "apk": _version_apk(parametres.apk_dir),
        "derniere_sauvegarde": derniere_sauvegarde,
        "alerte_sauvegarde": alerte_sauvegarde,
    }


@routeur.get("/quotas")
def quotas(request: Request) -> dict:
    """Compteurs du jour par API et seuils d'alerte."""
    return request.app.state.services.compteur.etat()


def _erreurs_fichier(dossier: str, limite: int) -> list[dict]:
    fichier = Path(dossier) / FICHIER_JOURNAL
    if not fichier.exists():
        return []
    erreurs = []
    with fichier.open(encoding="utf-8", errors="replace") as flux:
        for ligne in flux:
            if '"niveau": "erreur"' in ligne:
                try:
                    erreurs.append(json.loads(ligne))
                except ValueError:
                    continue
    return list(reversed(erreurs))[:limite]


@routeur.get("/logs/erreurs")
def dernieres_erreurs(request: Request, limite: int = Query(50, ge=1, le=200)) -> dict:
    """Dernières erreurs journalisées (S)."""
    erreurs = _erreurs_fichier(request.app.state.parametres.log_dir, limite)
    return {"items": erreurs or erreurs_recentes(limite)}
