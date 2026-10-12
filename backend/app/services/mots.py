"""Création, lecture, suppression et fusion des mots (36.3, API-12 à API-21, BDD-08)."""

import uuid
from datetime import UTC, date, datetime

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import ErreurApi, MotIntrouvable, ParametreInvalide
from app.models import Artiste, Extrait, Morceau, Mot, Revision
from app.services.normalisation import sans_accents, valider_terme
from app.services.revisions import creer_revision_initiale

TRIS = ("created_desc", "created_asc", "prochaine_revision", "alpha")
NIVEAUX = ("nouveau", "en_cours", "acquis")
ACCENTS = "àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ"
SANS_ACCENTS = "aaaaaaceeeeiiiinooooouuuuyyoa"


class IdentifiantDejaUtilise(ErreurApi):
    code, statut_http = "identifiant_deja_utilise", 409
    message_defaut = "Cet identifiant de mot est déjà utilisé."


def maintenant() -> datetime:
    """Heure UTC courante."""
    return datetime.now(UTC)


def trouver_par_terme(session: Session, terme_normalise: str) -> Mot | None:
    """Mot non supprimé ayant ce terme normalisé."""
    return session.scalar(
        select(Mot).where(Mot.terme_normalise == terme_normalise, Mot.deleted_at.is_(None))
    )


def _reprendre_cache(session: Session, mot: Mot) -> None:
    """Réutilise la traduction et les extraits d'un ancien mot supprimé (CAC-02)."""
    ancien = session.scalar(
        select(Mot)
        .where(
            Mot.terme_normalise == mot.terme_normalise,
            Mot.deleted_at.is_not(None),
            Mot.id != mot.id,
        )
        .order_by(Mot.deleted_at.desc())
        .limit(1)
    )
    if ancien is None:
        return
    mot.traduction_fr = ancien.traduction_fr
    if ancien.source_explication == "ia":
        mot.explication = ancien.explication
        mot.source_explication = ancien.source_explication
    anciens_extraits = session.scalars(select(Extrait).where(Extrait.mot_id == ancien.id)).all()
    for extrait in anciens_extraits:
        session.add(
            Extrait(
                id=uuid.uuid4(),
                mot_id=mot.id,
                morceau_id=extrait.morceau_id,
                texte=extrait.texte,
                surbrillance_debut=extrait.surbrillance_debut,
                surbrillance_fin=extrait.surbrillance_fin,
                hors_liste=extrait.hors_liste,
            )
        )


def creer_mot(
    session: Session,
    id: uuid.UUID,
    terme: str,
    jour_local: date,
    revision_id: uuid.UUID | None = None,
) -> tuple[Mot, bool]:
    """Crée le mot et sa révision initiale ; retourne (existant, False) si déjà présent."""
    normalise = valider_terme(terme)
    existant = trouver_par_terme(session, normalise)
    if existant is not None:
        return existant, False
    meme_id = session.get(Mot, id)
    if meme_id is not None:
        if meme_id.deleted_at is None:
            return meme_id, False
        raise IdentifiantDejaUtilise()
    mot = Mot(
        id=id,
        terme=terme.strip(),
        terme_normalise=normalise,
        statut_enrichissement="en_attente",
        niveau="nouveau",
        nb_echecs=0,
    )
    try:
        with session.begin_nested():
            session.add(mot)
            session.flush()
            _reprendre_cache(session, mot)
            creer_revision_initiale(session, mot.id, jour_local, revision_id)
            session.flush()
    except IntegrityError:
        existant = trouver_par_terme(session, normalise)
        if existant is None:
            raise
        return existant, False
    return mot, True


def obtenir_mot(session: Session, mot_id: uuid.UUID) -> Mot:
    """Mot non supprimé ou MotIntrouvable."""
    mot = session.get(Mot, mot_id)
    if mot is None or mot.deleted_at is not None:
        raise MotIntrouvable()
    return mot


def supprimer_mot(session: Session, mot_id: uuid.UUID) -> None:
    """Suppression logique du mot, de ses extraits et de sa révision planifiée (BDD-08)."""
    mot = session.get(Mot, mot_id)
    if mot is None or mot.deleted_at is not None:
        return
    instant = maintenant()
    mot.deleted_at = instant
    session.execute(
        update(Extrait)
        .where(Extrait.mot_id == mot_id, Extrait.deleted_at.is_(None))
        .values(deleted_at=instant)
    )
    session.execute(
        update(Revision)
        .where(
            Revision.mot_id == mot_id, Revision.statut == "planifiee", Revision.deleted_at.is_(None)
        )
        .values(deleted_at=instant, statut="ignoree")
    )
    session.flush()


def prochaines_revisions(session: Session, mot_ids: list[uuid.UUID]) -> dict[uuid.UUID, date]:
    """Date prévue de la révision planifiée de chaque mot."""
    if not mot_ids:
        return {}
    lignes = session.execute(
        select(Revision.mot_id, Revision.date_prevue).where(
            Revision.mot_id.in_(mot_ids),
            Revision.statut == "planifiee",
            Revision.deleted_at.is_(None),
        )
    ).all()
    return {mot_id: date_prevue for mot_id, date_prevue in lignes}


def _sans_accents_sql(colonne):
    return func.translate(func.lower(func.coalesce(colonne, "")), ACCENTS, SANS_ACCENTS)


def lister_mots(
    session: Session, niveau: str | None, q: str | None, tri: str, page: int, taille: int
) -> tuple[list[tuple[Mot, date | None]], int]:
    """Liste filtrée, recherchée, triée et paginée des mots non supprimés (API-18, API-19)."""
    if tri not in TRIS:
        raise ParametreInvalide("Valeur de tri inconnue.", details={"champ": "tri"})
    if niveau is not None and niveau not in NIVEAUX:
        raise ParametreInvalide("Niveau inconnu.", details={"champ": "niveau"})
    planifiee = (
        select(Revision.mot_id, Revision.date_prevue)
        .where(Revision.statut == "planifiee", Revision.deleted_at.is_(None))
        .subquery()
    )
    requete = (
        select(Mot, planifiee.c.date_prevue)
        .outerjoin(planifiee, planifiee.c.mot_id == Mot.id)
        .where(Mot.deleted_at.is_(None))
    )
    if niveau:
        requete = requete.where(Mot.niveau == niveau)
    if q and q.strip():
        motif = "%" + sans_accents(q.strip().lower()).replace("%", r"\%").replace("_", r"\_") + "%"
        requete = requete.where(
            _sans_accents_sql(Mot.terme).like(motif)
            | _sans_accents_sql(Mot.traduction_fr).like(motif)
        )
    total = session.scalar(select(func.count()).select_from(requete.subquery())) or 0
    ordres = {
        "created_desc": (Mot.created_at.desc(), Mot.id),
        "created_asc": (Mot.created_at.asc(), Mot.id),
        "prochaine_revision": (planifiee.c.date_prevue.asc().nulls_last(), Mot.terme_normalise),
        "alpha": (Mot.terme_normalise.asc(), Mot.id),
    }
    lignes = session.execute(
        requete.order_by(*ordres[tri]).offset((page - 1) * taille).limit(taille)
    ).all()
    return [(mot, prochaine) for mot, prochaine in lignes], int(total)


def extraits_du_mot(session: Session, mot_id: uuid.UUID) -> list[dict]:
    """Extraits non supprimés avec le titre et l'artiste du morceau."""
    lignes = session.execute(
        select(Extrait, Morceau.titre, Morceau.url_genius, Artiste.nom)
        .join(Morceau, Morceau.id == Extrait.morceau_id)
        .join(Artiste, Artiste.id == Morceau.artiste_id)
        .where(Extrait.mot_id == mot_id, Extrait.deleted_at.is_(None))
        .order_by(Extrait.created_at, Extrait.id)
    ).all()
    return [
        {
            "id": e.id,
            "texte": e.texte,
            "surbrillance_debut": e.surbrillance_debut,
            "surbrillance_fin": e.surbrillance_fin,
            "hors_liste": e.hors_liste,
            "morceau": {"titre": titre, "artiste": nom, "url_genius": url},
        }
        for e, titre, url, nom in lignes
    ]


def resume(mot: Mot, prochaine: date | None) -> dict:
    """Résumé d'un mot pour une liste."""
    return {
        "id": mot.id,
        "terme": mot.terme,
        "terme_normalise": mot.terme_normalise,
        "traduction_fr": mot.traduction_fr,
        "statut_enrichissement": mot.statut_enrichissement,
        "niveau": mot.niveau,
        "prochaine_revision": prochaine,
    }


def detail(session: Session, mot: Mot) -> dict:
    """Fiche complète d'un mot (API-20)."""
    prochaine = prochaines_revisions(session, [mot.id]).get(mot.id)
    return {
        **resume(mot, prochaine),
        "explication": mot.explication,
        "source_explication": mot.source_explication,
        "erreur_enrichissement": mot.erreur_enrichissement,
        "nb_echecs": mot.nb_echecs,
        "extraits": extraits_du_mot(session, mot.id),
        "created_at": mot.created_at,
        "updated_at": mot.updated_at,
    }


def fusionner_mots(session: Session, conserve_id: uuid.UUID, retire_id: uuid.UUID) -> None:
    """Rattache au mot conservé les révisions faites du mot retiré (20.7, ETA-03)."""
    if conserve_id == retire_id:
        return
    session.execute(
        update(Revision)
        .where(
            Revision.mot_id == retire_id,
            Revision.statut == "planifiee",
            Revision.deleted_at.is_(None),
        )
        .values(statut="doublon", deleted_at=maintenant())
    )
    session.execute(
        update(Revision)
        .where(Revision.mot_id == retire_id, Revision.statut == "faite")
        .values(mot_id=conserve_id)
    )
    supprimer_mot(session, retire_id)
