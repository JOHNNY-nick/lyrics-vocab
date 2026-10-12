"""Routes des mots et des extraits (C.3, API-12 à API-23)."""

import uuid

from fastapi import APIRouter, Depends, Query, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.core.database import obtenir_session
from app.core.errors import QuotaDepasse, ServiceIndisponible
from app.routers.deps import ContexteTemps, contexte_temps, gestionnaire, services
from app.schemas.mots import ExtraitSortie, MotCreation, MotDetail, Page
from app.services import mots
from app.services.enrichissement import GestionnaireEnrichissement, Services

routeur = APIRouter(prefix="/api/mots", tags=["mots"])
TAILLE_DEFAUT = 50
TAILLE_MAX = 200


def _sortie(session: Session, mot) -> dict:
    return MotDetail.model_validate(mots.detail(session, mot)).model_dump(mode="json")


@routeur.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=MotDetail,
    responses={200: {"model": MotDetail}, 422: {}},
)
def creer(
    entree: MotCreation,
    session: Session = Depends(obtenir_session),
    temps: ContexteTemps = Depends(contexte_temps),
    gestion: GestionnaireEnrichissement = Depends(gestionnaire),
):
    """Crée le mot et sa révision planifiée ; l'enrichissement suit en tâche de fond."""
    mot, cree = mots.creer_mot(session, entree.id, entree.terme, temps.jour)
    corps = _sortie(session, mot)
    session.commit()
    if not cree:
        return JSONResponse(status_code=200, content=corps)
    gestion.soumettre(mot.id)
    return JSONResponse(status_code=201, content=corps)


@routeur.get("", response_model=Page)
def lister(
    niveau: str | None = Query(None),
    q: str | None = Query(None, max_length=100),
    tri: str = Query("created_desc"),
    page: int = Query(1, ge=1),
    taille: int = Query(TAILLE_DEFAUT, ge=1, le=TAILLE_MAX),
    session: Session = Depends(obtenir_session),
) -> dict:
    """Liste paginée, filtrée et triée des mots."""
    lignes, total = mots.lister_mots(session, niveau, q, tri, page, taille)
    return {
        "items": [mots.resume(m, p) for m, p in lignes],
        "total": total,
        "page": page,
        "taille": taille,
    }


@routeur.get("/{mot_id}", response_model=MotDetail)
def obtenir(
    mot_id: uuid.UUID,
    session: Session = Depends(obtenir_session),
    gestion: GestionnaireEnrichissement = Depends(gestionnaire),
) -> dict:
    """Fiche d'un mot avec ses extraits et sa prochaine révision."""
    mot = mots.obtenir_mot(session, mot_id)
    gestion.relancer_si_utile(mot)
    return mots.detail(session, mot)


@routeur.delete("/{mot_id}", status_code=status.HTTP_204_NO_CONTENT)
def supprimer(mot_id: uuid.UUID, session: Session = Depends(obtenir_session)) -> Response:
    """Suppression logique, idempotente."""
    mots.supprimer_mot(session, mot_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@routeur.get("/{mot_id}/extraits", response_model=list[ExtraitSortie])
def extraits(mot_id: uuid.UUID, session: Session = Depends(obtenir_session)) -> list[dict]:
    """Extraits d'un mot."""
    mots.obtenir_mot(session, mot_id)
    return mots.extraits_du_mot(session, mot_id)


@routeur.post(
    "/{mot_id}/rechercher-extraits",
    response_model=MotDetail,
    responses={202: {"model": MotDetail}, 429: {}, 503: {}},
)
def rechercher_extraits(
    mot_id: uuid.UUID,
    session: Session = Depends(obtenir_session),
    gestion: GestionnaireEnrichissement = Depends(gestionnaire),
    conteneur: Services = Depends(services),
):
    """Relance l'enrichissement d'un mot partiel ou en échec (API-22, API-23)."""
    mot = mots.obtenir_mot(session, mot_id)
    if mot.statut_enrichissement == "ok":
        return JSONResponse(status_code=200, content=_sortie(session, mot))
    besoin_externe = not mot.traduction_fr or not mots.extraits_du_mot(session, mot_id)
    if besoin_externe:
        source = conteneur.paroles.service
        if not conteneur.paroles.disjoncteur.autoriser() and mot.traduction_fr:
            raise ServiceIndisponible()
        for api in (source, "deepl"):
            if api == "deepl" and not conteneur.deepl.configure:
                continue
            try:
                conteneur.compteur.verifier(api)
            except QuotaDepasse:
                if api == "deepl" and mot.traduction_fr:
                    continue
                if api == source and mots.extraits_du_mot(session, mot_id):
                    continue
                raise
    if not gestion.occupe(mot_id):
        mot.statut_enrichissement = "en_attente"
        session.flush()
        gestion.soumettre(mot_id, forcer_extraits=True)
    corps = _sortie(session, mot)
    session.commit()
    return JSONResponse(status_code=202, content=corps)
