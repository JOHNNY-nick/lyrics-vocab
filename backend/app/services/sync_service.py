"""Synchronisation serveur : push idempotent et pull par curseur (G.4, G.5, 39.2)."""

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, time
from zoneinfo import ZoneInfo

from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import (
    CurseurInvalide,
    ErreurApi,
    OperationInconnue,
    ParametreInvalide,
    RevisionIntrouvable,
)
from app.core.logging import journaliser
from app.models import Artiste, Extrait, Morceau, Mot, Reglage, Revision, SyncOp
from app.schemas.communs import format_heure, format_utc
from app.schemas.reglages import ArtistesPreferes, ReglagesPartiels
from app.services import artistes, mots, reglages, revisions, sm2
from app.services.calendrier import borner_instant, jour_local

TYPES = ("mot.creer", "mot.supprimer", "revision.repondre", "reglage.modifier", "artistes.modifier")
MODELES = {
    "mots": Mot,
    "artistes": Artiste,
    "extraits": Extrait,
    "revisions": Revision,
    "reglages": Reglage,
}


@dataclass
class ContexteSync:
    """Fuseau de l'appareil et paramètres utiles au rejeu."""

    fuseau: ZoneInfo
    intervalle_max: int
    seuil_acquis: int
    maintenant: Callable[[], datetime] = lambda: datetime.now(UTC)


def _uuid(valeur: object, champ: str) -> uuid.UUID:
    try:
        return uuid.UUID(str(valeur))
    except (ValueError, TypeError):
        raise ParametreInvalide(f"Champ {champ} invalide.", details={"champ": champ}) from None


def _datetime(valeur: object) -> datetime | None:
    if valeur in (None, ""):
        return None
    try:
        instant = datetime.fromisoformat(str(valeur).replace("Z", "+00:00"))
    except ValueError:
        raise ParametreInvalide("Date invalide.", details={"champ": "repondu_le"}) from None
    return instant if instant.tzinfo else instant.replace(tzinfo=UTC)


def _heure_changement(session: Session) -> time:
    return reglages.obtenir(session).heure_changement_jour


def _mot_resolu(session: Session, mot_id: uuid.UUID) -> uuid.UUID:
    """Identifiant du mot conservé quand un mot local a été fusionné (20.7)."""
    mot = session.get(Mot, mot_id)
    if mot is not None:
        return mot_id
    op = session.scalar(
        select(SyncOp).where(
            SyncOp.type == "mot.creer", SyncOp.resultat["donnees"]["id_local"].astext == str(mot_id)
        )
    )
    if op is not None:
        return uuid.UUID(op.resultat["donnees"]["mot_id"])
    return mot_id


def _creer_mot(session: Session, donnees: dict, contexte: ContexteSync) -> dict:
    mot_id = _uuid(donnees.get("id"), "id")
    terme = str(donnees.get("terme", ""))
    revision_id = (
        _uuid(donnees["revision_id"], "revision_id") if donnees.get("revision_id") else None
    )
    jour = jour_local(contexte.maintenant(), contexte.fuseau, _heure_changement(session))
    mot, cree = mots.creer_mot(session, mot_id, terme, jour, revision_id)
    return {
        "mot_id": str(mot.id),
        "id_local": str(mot_id),
        "fusion": mot.id != mot_id,
        "cree": cree,
    }


def _repondre(
    session: Session, donnees: dict, appareil_id: str, op_id: uuid.UUID, contexte: ContexteSync
) -> dict:
    revision_id = _uuid(donnees.get("revision_id"), "revision_id")
    revision = session.get(Revision, revision_id)
    if revision is None and donnees.get("mot_id"):
        conserve = _mot_resolu(session, _uuid(donnees["mot_id"], "mot_id"))
        planifiee = revisions.revision_planifiee(session, conserve)
        if planifiee is None:
            raise RevisionIntrouvable()
        revision = planifiee
    if revision is None:
        raise RevisionIntrouvable()
    note = sm2.note_depuis_reponse("rappel", None, donnees.get("verdict"), donnees.get("qualite"))
    propose = _datetime(donnees.get("repondu_le"))
    instant, borne = borner_instant(propose, contexte.maintenant(), revision.created_at)
    if borne:
        journaliser(
            "sync_horloge_bornee", "avertissement", op_id=str(op_id), appareil_id=appareil_id
        )
    jour = jour_local(instant, contexte.fuseau, _heure_changement(session))
    nouvelle = donnees.get("nouvelle_revision_id")
    resultat = revisions.repondre(
        session,
        revision.id,
        op_id,
        note,
        instant,
        appareil_id,
        jour,
        verdict=donnees.get("verdict"),
        reponse=donnees.get("reponse"),
        nouvelle_revision_id=_uuid(nouvelle, "nouvelle_revision_id") if nouvelle else None,
        intervalle_max=contexte.intervalle_max,
        seuil_acquis=contexte.seuil_acquis,
    )
    return resultat.en_dict()


def appliquer_operation(
    session: Session,
    type_op: str,
    donnees: dict,
    appareil_id: str,
    op_id: uuid.UUID,
    contexte: ContexteSync,
    apres_validation: list[uuid.UUID],
) -> dict | None:
    """Applique une opération ; lève ErreurApi pour un rejet."""
    if type_op == "mot.creer":
        resultat = _creer_mot(session, donnees, contexte)
        if resultat["cree"]:
            apres_validation.append(uuid.UUID(resultat["mot_id"]))
        return resultat
    if type_op == "mot.supprimer":
        mots.supprimer_mot(session, _uuid(donnees.get("id"), "id"))  # API-37 : idempotent
        return None
    if type_op == "revision.repondre":
        return _repondre(session, donnees, appareil_id, op_id, contexte)
    if type_op == "reglage.modifier":
        try:
            champs = ReglagesPartiels.model_validate(donnees).model_dump(exclude_none=True)
        except ValidationError:
            raise ParametreInvalide("Réglages invalides.") from None
        reglages.mettre_a_jour(session, champs)
        return None
    if type_op == "artistes.modifier":
        try:
            liste = ArtistesPreferes.model_validate(donnees)
        except ValidationError:
            raise ParametreInvalide("Liste d'artistes invalide.") from None
        artistes.remplacer_liste(session, [a.model_dump() for a in liste.artistes])
        return None
    raise OperationInconnue()


def ordonner(operations: list) -> list:
    """Réponses d'un même mot triées par repondu_le, aux mêmes positions (SYN-17, SYN-29)."""

    def cle_mot(op) -> str | None:
        if op.type != "revision.repondre":
            return None
        return str(op.donnees.get("mot_id") or op.donnees.get("revision_id"))

    groupes: dict[str, list[int]] = {}
    for indice, op in enumerate(operations):
        cle = cle_mot(op)
        if cle is not None:
            groupes.setdefault(cle, []).append(indice)
    resultat = list(operations)
    for indices in groupes.values():
        triees = sorted(
            (operations[i] for i in indices), key=lambda o: str(o.donnees.get("repondu_le") or "")
        )
        for position, op in zip(indices, triees, strict=True):
            resultat[position] = op
    return resultat


def traiter_push(
    session: Session, appareil_id: str, operations: list, contexte: ContexteSync
) -> tuple[list[dict], list[uuid.UUID]]:
    """Chaque opération dans sa propre transaction ; un rejeu renvoie le même résultat."""
    resultats: dict[uuid.UUID, dict] = {}
    a_enrichir: list[uuid.UUID] = []
    for op in ordonner(operations):
        deja = session.get(SyncOp, op.op_id)
        if deja is not None:
            stocke = dict(deja.resultat)
            if stocke.get("statut") == "applique":
                stocke["statut"] = "deja_applique"
            resultats[op.op_id] = {"op_id": str(op.op_id), **stocke}
            continue
        nouveaux: list[uuid.UUID] = []
        try:
            with session.begin_nested():
                if op.type not in TYPES:
                    raise OperationInconnue()
                donnees = appliquer_operation(
                    session, op.type, op.donnees, appareil_id, op.op_id, contexte, nouveaux
                )
                resultat = {"statut": "applique", "donnees": donnees}
                session.add(
                    SyncOp(op_id=op.op_id, appareil_id=appareil_id, type=op.type, resultat=resultat)
                )
                session.flush()
            a_enrichir.extend(nouveaux)
        except ErreurApi as exc:
            resultat = {"statut": "rejete", "code": exc.code, "message": exc.message}
            with session.begin_nested():
                session.add(
                    SyncOp(op_id=op.op_id, appareil_id=appareil_id, type=op.type, resultat=resultat)
                )
            journaliser(
                "sync_operation_rejetee",
                "avertissement",
                op_id=str(op.op_id),
                type=op.type,
                code=exc.code,
            )
        session.commit()
        resultats[op.op_id] = {"op_id": str(op.op_id), **resultat}
    return [resultats[op.op_id] for op in operations], a_enrichir


def curseur_serveur(session: Session) -> int:
    """Plus grand server_seq des tables synchronisées."""
    maximum = 0
    for modele in MODELES.values():
        valeur = session.scalar(select(func.max(modele.server_seq)))
        maximum = max(maximum, valeur or 0)
    return maximum


def _valeur(valeur: object) -> object:
    if isinstance(valeur, datetime):
        return format_utc(valeur)
    if isinstance(valeur, date):
        return valeur.isoformat()
    if isinstance(valeur, time):
        return format_heure(valeur)
    if isinstance(valeur, uuid.UUID):
        return str(valeur)
    if isinstance(valeur, float):
        return round(valeur, 2)
    return valeur


def _ligne(objet: object) -> dict:
    return {c.key: _valeur(getattr(objet, c.key)) for c in objet.__table__.columns}


def _extraits_avec_morceau(session: Session, lignes: list[Extrait]) -> list[dict]:
    if not lignes:
        return []
    morceaux = {
        m.id: (m, a)
        for m, a in session.execute(
            select(Morceau, Artiste)
            .join(Artiste, Artiste.id == Morceau.artiste_id)
            .where(Morceau.id.in_({e.morceau_id for e in lignes}))
        ).all()
    }
    sortie = []
    for extrait in lignes:
        donnees = _ligne(extrait)
        morceau, artiste = morceaux.get(extrait.morceau_id, (None, None))
        donnees["titre"] = morceau.titre if morceau else None
        donnees["artiste"] = artiste.nom if artiste else None
        donnees["url_genius"] = morceau.url_genius if morceau else None
        sortie.append(donnees)
    return sortie


def traiter_pull(session: Session, since: int, limite: int) -> dict:
    """Changements par plages de server_seq ; le curseur ne saute aucun changement (17.5)."""
    if since < 0 or since > curseur_serveur(session):
        raise CurseurInvalide()
    lus: dict[str, list] = {}
    tronquees: list[int] = []
    for nom, modele in MODELES.items():
        lignes = list(
            session.scalars(
                select(modele)
                .where(modele.server_seq > since)
                .order_by(modele.server_seq.asc())
                .limit(limite + 1)
            ).all()
        )
        if len(lignes) > limite:
            lignes = lignes[:limite]
            tronquees.append(lignes[-1].server_seq)
        lus[nom] = lignes
    if tronquees:
        curseur = min(tronquees)
        lus = {nom: [x for x in lignes if x.server_seq <= curseur] for nom, lignes in lus.items()}
    else:
        curseur = max([since, *(x.server_seq for lignes in lus.values() for x in lignes)])
    changements = {
        nom: (
            [*_extraits_avec_morceau(session, lignes)]
            if nom == "extraits"
            else [_ligne(x) for x in lignes]
        )
        for nom, lignes in lus.items()
    }
    return {"curseur": curseur, "a_suite": bool(tronquees), "changements": changements}
