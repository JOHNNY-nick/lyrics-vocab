"""Lecture et mise à jour de la ligne unique de réglages (US-07)."""

import uuid

from sqlalchemy.orm import Session

from app.models import ID_REGLAGE, Reglage

CHAMPS = (
    "frequence_rappels",
    "heure_rappel",
    "heures_rappel_sup",
    "intervalle_notifications_min",
    "notifications_debut",
    "notifications_fin",
    "mots_par_session",
    "mode_revision",
    "heure_changement_jour",
    "sync_wifi_seulement",
)


def obtenir(session: Session) -> Reglage:
    """Ligne unique des réglages ; la recrée avec les valeurs par défaut si elle manque."""
    reglage = session.get(Reglage, uuid.UUID(ID_REGLAGE))
    if reglage is None:
        reglage = Reglage(id=uuid.UUID(ID_REGLAGE))
        session.add(reglage)
        session.flush()
        session.refresh(reglage)
    return reglage


def mettre_a_jour(session: Session, champs: dict) -> Reglage:
    """Met à jour les champs reçus ; la dernière écriture reçue gagne (G.6)."""
    reglage = obtenir(session)
    for nom, valeur in champs.items():
        if nom in CHAMPS and valeur is not None:
            setattr(reglage, nom, valeur)
    session.flush()
    return reglage


def en_dict(reglage: Reglage) -> dict:
    """Réglages sous forme de dictionnaire."""
    return {nom: getattr(reglage, nom) for nom in CHAMPS}
