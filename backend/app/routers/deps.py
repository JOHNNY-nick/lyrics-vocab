"""Dépendances communes des routes : services, fuseau et jour local."""

from dataclasses import dataclass
from datetime import UTC, date, datetime, time
from zoneinfo import ZoneInfo

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.core.database import obtenir_session
from app.services import reglages
from app.services.calendrier import fuseau_valide, jour_local
from app.services.enrichissement import GestionnaireEnrichissement, Services


@dataclass
class ContexteTemps:
    """Fuseau de l'appareil (X-Fuseau), heure de changement de jour et jour local courant."""

    fuseau: ZoneInfo
    heure_changement: time
    jour: date
    maintenant: datetime


def services(request: Request) -> Services:
    """Conteneur des services externes."""
    return request.app.state.services


def gestionnaire(request: Request) -> GestionnaireEnrichissement:
    """Gestionnaire des tâches d'enrichissement."""
    return request.app.state.gestionnaire


def contexte_temps(request: Request, session: Session = Depends(obtenir_session)) -> ContexteTemps:
    """Jour local courant selon le fuseau de l'appareil, à défaut celui du PC (ALG-15)."""
    parametres = request.app.state.parametres
    fuseau = fuseau_valide(request.headers.get("x-fuseau"), parametres.fuseau_pc)
    heure = reglages.obtenir(session).heure_changement_jour
    maintenant = datetime.now(UTC)
    return ContexteTemps(fuseau, heure, jour_local(maintenant, fuseau, heure), maintenant)


def appareil(request: Request) -> str | None:
    """Identifiant de l'appareil (X-Appareil-Id), facultatif."""
    valeur = request.headers.get("x-appareil-id")
    return valeur[:64] if valeur else None
