"""Routes des révisions et des exercices (API-24 à API-30, 18.4, 18.5)."""

import uuid
from datetime import date

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.core.database import obtenir_session
from app.core.errors import IaIndisponible, MotIntrouvable, ReponseInvalide, RevisionIntrouvable
from app.models import Mot, Revision, SyncOp
from app.routers.deps import ContexteTemps, appareil, contexte_temps, services
from app.schemas.revisions import (
    EvaluationDemande,
    EvaluationSortie,
    ExerciceDemande,
    ExerciceSortie,
    ReponseRevision,
    ResultatReponse,
    RevisionsDues,
)
from app.services import ai_exercise, exercices_prets, mots, reglages, revisions, sm2
from app.services.calendrier import borner_instant, jour_local
from app.services.enrichissement import Services

routeur = APIRouter(prefix="/api", tags=["révisions"])


@routeur.get("/revisions/dues", response_model=RevisionsDues)
def dues(
    date_jour: date | None = Query(None, alias="date"),
    session: Session = Depends(obtenir_session),
    temps: ContexteTemps = Depends(contexte_temps),
) -> dict:
    """Révisions planifiées dues, limitées à mots_par_session (API-24, API-25)."""
    jour = date_jour or temps.jour
    limite = reglages.obtenir(session).mots_par_session
    lignes, total = revisions.revisions_dues(session, jour, limite)
    items = []
    for revision, mot in lignes:
        extraits = mots.extraits_du_mot(session, mot.id)
        premier = extraits[0] if extraits else None
        items.append(
            {
                "id": revision.id,
                "mot_id": mot.id,
                "mode": revision.mode,
                "date_prevue": revision.date_prevue,
                "terme": mot.terme,
                "traduction_fr": mot.traduction_fr,
                "indice": revisions.indice_depuis(premier),
                "explication": mot.explication,
                "source_explication": mot.source_explication,
                "exemples": mot.exemples or [],
                "extrait": premier,
            }
        )
    return {
        "total_dus": total,
        "jour": jour,
        "items": items,
        "prochaine_date": revisions.prochaine_echeance(session, jour),
        "serie": revisions.serie_jours(session, temps.jour, temps.fuseau, temps.heure_changement),
    }


@routeur.post("/revisions/{revision_id}/reponse", response_model=ResultatReponse)
def repondre(
    revision_id: uuid.UUID,
    entree: ReponseRevision,
    request: Request,
    session: Session = Depends(obtenir_session),
    temps: ContexteTemps = Depends(contexte_temps),
) -> dict:
    """Applique SM-2 ; idempotent par op_id (API-26 à API-28)."""
    deja = session.get(SyncOp, entree.op_id)
    if deja is not None and deja.resultat.get("statut") == "applique":
        return {**deja.resultat["donnees"], "statut": "deja_applique"}
    if entree.qualite is None and entree.verdict is None:
        raise ReponseInvalide()
    revision = session.get(Revision, revision_id)
    if revision is None:
        raise RevisionIntrouvable()
    note = sm2.note_depuis_reponse(revision.mode, None, entree.verdict, entree.qualite)
    instant, _ = borner_instant(entree.repondu_le, temps.maintenant, revision.created_at)
    jour = jour_local(instant, temps.fuseau, temps.heure_changement)
    parametres = request.app.state.parametres
    resultat = revisions.repondre(
        session,
        revision_id,
        entree.op_id,
        note,
        instant,
        appareil(request),
        jour,
        verdict=entree.verdict,
        reponse=entree.reponse,
        nouvelle_revision_id=entree.nouvelle_revision_id,
        intervalle_max=parametres.intervalle_max_jours,
        seuil_acquis=parametres.niveau_acquis_jours,
    )
    donnees = resultat.en_dict()
    if resultat.statut == "applique":
        session.add(
            SyncOp(
                op_id=entree.op_id,
                appareil_id=appareil(request) or "pwa",
                type="revision.repondre",
                resultat={"statut": "applique", "donnees": donnees},
            )
        )
    return donnees


@routeur.post("/exercices", response_model=ExerciceSortie)
async def creer_exercice(
    entree: ExerciceDemande,
    session: Session = Depends(obtenir_session),
    conteneur: Services = Depends(services),
) -> dict:
    """Phrase française générée ; l'identifiant est celui de la révision planifiée (API-29)."""
    mot = mots.obtenir_mot(session, entree.mot_id)
    revision = revisions.revision_planifiee(session, mot.id)
    if revision is None:
        raise MotIntrouvable("Aucune révision planifiée pour ce mot.")
    if not mot.traduction_fr:
        raise IaIndisponible()
    if exercices_prets.phrase_prete(revision) and not entree.nouvelle:
        # Phrase préparée à l'avance par la tâche de fond : réponse immédiate.
        revision.mode = "production"
        session.commit()
        return {"id": revision.id, "phrase_fr": revision.phrase_source, "generee": True}
    if not await conteneur.ollama.disponible():
        raise IaIndisponible()
    deja_vues = [e["en"] for e in (mot.exemples or [])]
    if revision.reference_en:
        deja_vues.append(revision.reference_en)  # « Nouvelle phrase » : pas la même
    phrase, reference = await ai_exercise.generer_exercice(
        conteneur.ollama, mot.terme, mot.traduction_fr, deja_vues
    )
    revision.mode = "production"
    revision.phrase_source = phrase
    revision.reference_en = reference
    revision.verdict = None
    revision.reponse_utilisateur = None
    session.commit()
    return {"id": revision.id, "phrase_fr": phrase, "generee": True}


@routeur.post("/exercices/{exercice_id}/evaluer", response_model=EvaluationSortie)
async def evaluer_exercice(
    exercice_id: uuid.UUID,
    entree: EvaluationDemande,
    session: Session = Depends(obtenir_session),
    conteneur: Services = Depends(services),
) -> dict:
    """Verdict de l'IA, ou repli par mots-clés ; ne modifie pas SM-2 (18.5)."""
    revision = session.get(Revision, exercice_id)
    if (
        revision is None
        or revision.deleted_at is not None
        or revision.mode != "production"
        or not revision.phrase_source
        or not revision.reference_en
    ):
        raise RevisionIntrouvable("Exercice introuvable.")
    mot = session.get(Mot, revision.mot_id)
    evaluation = await ai_exercise.evaluer(
        conteneur.ollama,
        revision.phrase_source,
        revision.reference_en,
        entree.reponse,
        terme=mot.terme if mot is not None else None,
    )
    if revision.statut == "planifiee":
        revision.reponse_utilisateur = entree.reponse
        revision.verdict = evaluation.verdict
        revision.verdict_repli = evaluation.verdict_repli
        revision.explication_verdict = evaluation.explication[:200]
        session.commit()
    return {
        "verdict": evaluation.verdict,
        "explication": evaluation.explication,
        "verdict_repli": evaluation.verdict_repli,
        "reference_en": revision.reference_en,
    }
