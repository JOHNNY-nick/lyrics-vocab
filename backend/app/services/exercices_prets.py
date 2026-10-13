"""Phrases d'exercice préparées à l'avance pour les révisions proches (voir DECISIONS.md).

L'IA du PC met 5 à 10 s pour écrire une phrase : la tâche de fond les prépare pour les mots
dus aujourd'hui et demain, et POST /api/exercices sert directement la phrase préparée.
"""

import asyncio
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from sqlalchemy import or_, select

from app.core.errors import ErreurApi
from app.core.logging import journaliser
from app.models import Mot, Revision
from app.services import ai_exercise
from app.services.enrichissement import Services

INTERVALLE_S = 600
HORIZON_JOURS = 1
MAXIMUM_PAR_PASSAGE = 30
ATTENTE_DEMARRAGE_S = 30


def phrase_prete(revision: Revision) -> bool:
    """Phrase générée et pas encore utilisée (aucune réponse évaluée)."""
    return bool(
        revision.phrase_source
        and revision.reference_en
        and revision.verdict is None
        and revision.reponse_utilisateur is None
    )


def a_preparer(session, maximum: int = MAXIMUM_PAR_PASSAGE) -> list[tuple[Revision, Mot]]:
    """Révisions planifiées d'ici demain, dont le mot est traduit, sans phrase prête."""
    limite = (datetime.now(UTC) + timedelta(days=HORIZON_JOURS)).date()
    lignes = session.execute(
        select(Revision, Mot)
        .join(Mot, Mot.id == Revision.mot_id)
        .where(
            Revision.statut == "planifiee",
            Revision.deleted_at.is_(None),
            Revision.date_prevue <= limite,
            Mot.deleted_at.is_(None),
            Mot.traduction_fr.is_not(None),
            or_(
                Revision.phrase_source.is_(None),
                Revision.verdict.is_not(None),
                Revision.reponse_utilisateur.is_not(None),
            ),
        )
        .order_by(Revision.date_prevue, Revision.created_at)
        .limit(maximum)
    ).all()
    return [(r, m) for r, m in lignes]


async def preparer(services: Services) -> int:
    """Un passage : prépare les phrases manquantes ; retourne le nombre préparé."""
    if not await services.ollama.disponible():
        return 0
    with services.fabrique() as session:
        cibles = [
            (r.id, m.terme, m.traduction_fr, [e["en"] for e in (m.exemples or [])])
            for r, m in a_preparer(session)
        ]
    prets = 0
    for revision_id, terme, traduction, deja_vues in cibles:
        try:
            phrase, reference = await ai_exercise.generer_exercice(
                services.ollama, terme, traduction, deja_vues
            )
        except ErreurApi:
            continue
        with services.fabrique() as session:
            revision = session.get(Revision, revision_id)
            # La révision a pu être répondue ou servie pendant la génération.
            if revision is None or revision.statut != "planifiee" or phrase_prete(revision):
                continue
            revision.phrase_source = phrase
            revision.reference_en = reference
            revision.verdict = None
            revision.reponse_utilisateur = None
            session.commit()
            prets += 1
    if prets:
        journaliser("exercices_prepares", nombre=prets)
    return prets


async def boucle(liste_services: Callable[[], list[Services]]) -> None:
    """Passage au démarrage puis toutes les 10 minutes, pour chaque utilisateur ; une erreur
    ne l'arrête jamais."""
    await asyncio.sleep(ATTENTE_DEMARRAGE_S)
    while True:
        for services in await asyncio.to_thread(liste_services):
            try:
                await preparer(services)
            except Exception as exc:
                journaliser("exercices_prepares_echec", "avertissement", erreur=type(exc).__name__)
        await asyncio.sleep(INTERVALLE_S)
