"""Moteur SQLAlchemy, session par requête et attente de la base au démarrage (T-03, ENV-03)."""

import time
from collections.abc import Callable, Iterator

from fastapi import Request
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import BaseIndisponible
from app.core.logging import journaliser

INTERVALLE_TENTATIVE_S = 2


def creer_moteur(url: str) -> Engine:
    """Crée le moteur avec vérification des connexions (reprise après un arrêt de PostgreSQL)."""
    return create_engine(url, pool_pre_ping=True, pool_size=5, max_overflow=5, future=True)


def creer_fabrique(moteur: Engine) -> sessionmaker[Session]:
    """Fabrique de sessions liée au moteur."""
    return sessionmaker(bind=moteur, expire_on_commit=False, future=True)


def attendre_base(
    moteur: Engine,
    duree_max_s: int = 60,
    dormir: Callable[[float], None] = time.sleep,
    horloge: Callable[[], float] = time.monotonic,
) -> None:
    """Tente SELECT 1 toutes les 2 s ; lève BaseIndisponible au bout de duree_max_s."""
    debut = horloge()
    tentative = 0
    while True:
        tentative += 1
        try:
            with moteur.connect() as connexion:
                connexion.execute(text("SELECT 1"))
            return
        except OperationalError:
            restant = duree_max_s - (horloge() - debut)
            journaliser(
                "base_indisponible",
                "erreur",
                tentative=tentative,
                delai_restant_s=round(max(restant, 0), 1),
            )
            if restant <= 0:
                raise BaseIndisponible(
                    "PostgreSQL ne répond pas : vérifie que le service est démarré."
                ) from None
            dormir(min(INTERVALLE_TENTATIVE_S, max(restant, 0)))


def obtenir_session(request: Request) -> Iterator[Session]:
    """Dépendance FastAPI : ouvre, yield, commit si aucune erreur, rollback sinon, ferme."""
    locataires = getattr(request.app.state, "locataires", None)
    fabrique: sessionmaker[Session] = (
        locataires.depuis_requete(request).fabrique
        if locataires is not None
        else request.app.state.fabrique_sessions
    )
    session = fabrique()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
