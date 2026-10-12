"""Routes de synchronisation (G.4, SYN-16 à SYN-23)."""

import time

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.core.database import obtenir_session
from app.core.logging import journaliser
from app.routers.deps import gestionnaire
from app.schemas.sync import PullReponse, PushDemande, PushReponse
from app.services.calendrier import fuseau_valide
from app.services.enrichissement import GestionnaireEnrichissement
from app.services.sync_service import ContexteSync, traiter_pull, traiter_push

routeur = APIRouter(prefix="/api/sync", tags=["synchronisation"])


@routeur.post("/push", response_model=PushReponse)
def push(
    entree: PushDemande,
    request: Request,
    session: Session = Depends(obtenir_session),
    gestion: GestionnaireEnrichissement = Depends(gestionnaire),
) -> dict:
    """Applique chaque opération dans sa propre transaction ; rejeu sans double effet."""
    debut = time.perf_counter()
    parametres = request.app.state.parametres
    contexte = ContexteSync(
        fuseau=fuseau_valide(request.headers.get("x-fuseau"), parametres.fuseau_pc),
        intervalle_max=parametres.intervalle_max_jours,
        seuil_acquis=parametres.niveau_acquis_jours,
    )
    resultats, a_enrichir = traiter_push(session, entree.appareil_id, entree.operations, contexte)
    for mot_id in a_enrichir:
        gestion.soumettre(mot_id)  # SYN-23
    gestion.reprendre()  # ENR-03 : reprise à chaque synchronisation
    compte = {
        s: sum(1 for r in resultats if r["statut"] == s)
        for s in ("applique", "deja_applique", "rejete")
    }
    journaliser(
        "sync_push",
        appareil_id=entree.appareil_id,
        nb_ops=len(resultats),
        appliquees=compte["applique"],
        deja_appliquees=compte["deja_applique"],
        rejetees=compte["rejete"],
        duree_ms=round((time.perf_counter() - debut) * 1000),
    )
    return {"resultats": resultats}


@routeur.get("/pull", response_model=PullReponse)
def pull(
    request: Request,
    since: int = Query(0, ge=0),
    limite: int | None = Query(None, ge=1),
    session: Session = Depends(obtenir_session),
) -> dict:
    """Changements depuis le curseur, par pages (SYN-19 à SYN-21)."""
    taille = min(
        limite or request.app.state.parametres.sync_page, request.app.state.parametres.sync_page
    )
    reponse = traiter_pull(session, since, taille)
    journaliser(
        "sync_pull",
        appareil_id=request.headers.get("x-appareil-id"),
        since=since,
        curseur=reponse["curseur"],
        nb_changements=sum(len(v) for v in reponse["changements"].values()),
        a_suite=reponse["a_suite"],
    )
    return reponse
