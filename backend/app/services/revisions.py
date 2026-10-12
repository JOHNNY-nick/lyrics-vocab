"""Révisions : création, réponse SM-2, révisions dues (36.3, ETA-01, ETA-02, REV-01 à REV-11)."""

import uuid
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.core.errors import RevisionDejaRepondue, RevisionIntrouvable
from app.models import Mot, Revision
from app.services import sm2
from app.services.calendrier import date_prevue, jour_local
from app.services.extraction import masquer_mot

SERIE_JOURS_MAX = 400


@dataclass
class ResultatReponse:
    """Résultat d'une réponse de révision."""

    statut: str
    prochaine_date: date
    intervalle_jours: int
    facilite: float
    repetitions: int
    niveau: str
    nouvelle_revision_id: uuid.UUID | None

    def en_dict(self) -> dict:
        """Forme JSON (pour la réponse HTTP et sync_op.resultat)."""
        return {
            "statut": self.statut,
            "prochaine_date": self.prochaine_date.isoformat(),
            "intervalle_jours": self.intervalle_jours,
            "facilite": self.facilite,
            "repetitions": self.repetitions,
            "niveau": self.niveau,
            "nouvelle_revision_id": (
                str(self.nouvelle_revision_id) if self.nouvelle_revision_id else None
            ),
        }


def creer_revision_initiale(
    session: Session, mot_id: uuid.UUID, jour: date, revision_id: uuid.UUID | None = None
) -> Revision:
    """Révision planifiée au jour local courant, état SM-2 initial (ETA-01)."""
    revision = Revision(
        id=revision_id or uuid.uuid4(),
        mot_id=mot_id,
        date_prevue=jour,
        repetitions=0,
        facilite=sm2.FACILITE_INITIALE,
        intervalle_jours=0,
        statut="planifiee",
        mode="rappel",
        verdict_repli=False,
    )
    session.add(revision)
    return revision


def revision_planifiee(session: Session, mot_id: uuid.UUID) -> Revision | None:
    """Révision planifiée non supprimée d'un mot."""
    return session.scalar(
        select(Revision).where(
            Revision.mot_id == mot_id, Revision.statut == "planifiee", Revision.deleted_at.is_(None)
        )
    )


def _etat(revision: Revision) -> sm2.EtatRevision:
    return sm2.EtatRevision(
        revision.repetitions, round(float(revision.facilite), 2), revision.intervalle_jours
    )


def _resultat_existant(
    session: Session, faite: Revision, jour: date, intervalle_max: int, seuil_acquis: int
) -> ResultatReponse:
    """Rejoue le calcul d'une réponse déjà appliquée (idempotence, API-26)."""
    nouvel_etat = sm2.appliquer(_etat(faite), faite.qualite or 0, intervalle_max)
    suivante = revision_planifiee(session, faite.mot_id)
    mot = session.get(Mot, faite.mot_id)
    return ResultatReponse(
        statut="deja_applique",
        prochaine_date=(
            suivante.date_prevue if suivante else date_prevue(jour, nouvel_etat.intervalle_jours)
        ),
        intervalle_jours=nouvel_etat.intervalle_jours,
        facilite=nouvel_etat.facilite,
        repetitions=nouvel_etat.repetitions,
        niveau=(
            mot.niveau
            if mot
            else sm2.niveau_depuis_etat(nouvel_etat, faite.qualite or 0, seuil_acquis)
        ),
        nouvelle_revision_id=suivante.id if suivante else None,
    )


def repondre(
    session: Session,
    revision_id: uuid.UUID,
    op_id: uuid.UUID,
    note: int,
    repondu_le: datetime,
    appareil_id: str | None,
    jour: date,
    *,
    verdict: str | None = None,
    reponse: str | None = None,
    nouvelle_revision_id: uuid.UUID | None = None,
    intervalle_max: int = 365,
    seuil_acquis: int = 21,
) -> ResultatReponse:
    """Marque la révision faite et crée la suivante dans la même transaction (ETA-02)."""
    deja = session.scalar(select(Revision).where(Revision.op_id == op_id))
    if deja is not None:
        return _resultat_existant(session, deja, jour, intervalle_max, seuil_acquis)
    revision = session.scalar(select(Revision).where(Revision.id == revision_id).with_for_update())
    if revision is None or revision.deleted_at is not None:
        raise RevisionIntrouvable()
    mot = session.scalar(select(Mot).where(Mot.id == revision.mot_id).with_for_update())
    if mot is None or mot.deleted_at is not None:
        raise RevisionIntrouvable()
    if revision.statut != "planifiee":
        raise RevisionDejaRepondue()

    nouvel_etat = sm2.appliquer(_etat(revision), note, intervalle_max)
    revision.statut = "faite"
    revision.qualite = note
    revision.repondu_le = repondu_le
    revision.op_id = op_id
    revision.appareil_id = appareil_id
    if verdict is not None:
        revision.verdict = verdict
    if reponse is not None:
        revision.reponse_utilisateur = reponse[:300]
    session.flush()

    suivante = Revision(
        id=nouvelle_revision_id or uuid.uuid4(),
        mot_id=mot.id,
        date_prevue=date_prevue(jour, nouvel_etat.intervalle_jours),
        repetitions=nouvel_etat.repetitions,
        facilite=nouvel_etat.facilite,
        intervalle_jours=nouvel_etat.intervalle_jours,
        statut="planifiee",
        mode="rappel",
        verdict_repli=False,
    )
    session.add(suivante)
    mot.niveau = sm2.niveau_depuis_etat(nouvel_etat, note, seuil_acquis, mot.niveau)
    if note < sm2.NOTE_REUSSITE_MIN:
        mot.nb_echecs += 1
    mot.derniere_revision_le = repondu_le
    session.flush()
    return ResultatReponse(
        "applique",
        suivante.date_prevue,
        nouvel_etat.intervalle_jours,
        nouvel_etat.facilite,
        nouvel_etat.repetitions,
        mot.niveau,
        suivante.id,
    )


def revisions_dues(
    session: Session, jour: date, limite: int
) -> tuple[list[tuple[Revision, Mot]], int]:
    """Révisions planifiées dues, de la plus ancienne à la plus récente (17.5)."""
    filtre = (
        Revision.statut == "planifiee",
        Revision.deleted_at.is_(None),
        Mot.deleted_at.is_(None),
        Revision.date_prevue <= jour,
    )
    total = (
        session.scalar(
            select(func.count())
            .select_from(Revision)
            .join(Mot, Mot.id == Revision.mot_id)
            .where(*filtre)
        )
        or 0
    )
    lignes = session.execute(
        select(Revision, Mot)
        .join(Mot, Mot.id == Revision.mot_id)
        .where(*filtre)
        .order_by(Revision.date_prevue.asc(), Revision.created_at.asc())
        .limit(limite)
    ).all()
    return [(r, m) for r, m in lignes], int(total)


def prochaine_echeance(session: Session, apres: date) -> date | None:
    """Première échéance planifiée après le jour donné."""
    return session.scalar(
        select(func.min(Revision.date_prevue))
        .join(Mot, Mot.id == Revision.mot_id)
        .where(
            Revision.statut == "planifiee",
            Revision.deleted_at.is_(None),
            Mot.deleted_at.is_(None),
            Revision.date_prevue > apres,
        )
    )


def serie_jours(session: Session, jour: date, fuseau: ZoneInfo, heure_changement: time) -> int:
    """Nombre de jours consécutifs avec au moins une révision faite (jusqu'à aujourd'hui)."""
    heures = session.scalars(
        select(func.distinct(func.date_trunc("hour", Revision.repondu_le))).where(
            Revision.statut == "faite",
            Revision.repondu_le.is_not(None),
            Revision.repondu_le >= func.now() - text(f"interval '{SERIE_JOURS_MAX} days'"),
        )
    ).all()
    faits = {jour_local(h, fuseau, heure_changement) for h in heures}
    curseur = jour if jour in faits else jour - timedelta(days=1)
    serie = 0
    while curseur in faits:
        serie += 1
        curseur -= timedelta(days=1)
    return serie


def indice_depuis(extrait: dict | None) -> str | None:
    """Extrait avec le mot masqué, ou None s'il n'y a pas d'extrait (REV-14)."""
    if extrait is None:
        return None
    return masquer_mot(extrait["texte"], extrait["surbrillance_debut"], extrait["surbrillance_fin"])


def jour_courant(instant: datetime, fuseau: ZoneInfo, heure_changement: time) -> date:
    """Jour local courant (ALG-14)."""
    return jour_local(instant, fuseau, heure_changement)
