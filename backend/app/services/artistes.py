"""Artistes préférés et artistes rencontrés (API-33, 18.6, ENR-07)."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Artiste

# Liste de secours embarquée (H.3, écran 1) : la même liste existe côté application.
SUGGESTIONS = (
    "Drake",
    "Eminem",
    "Taylor Swift",
    "The Weeknd",
    "Billie Eilish",
    "Kendrick Lamar",
    "Ed Sheeran",
    "Dua Lipa",
    "Post Malone",
    "Ariana Grande",
    "Bruno Mars",
    "Rihanna",
    "Travis Scott",
    "Adele",
    "Harry Styles",
)


def preferes(session: Session) -> list[Artiste]:
    """Artistes préférés dans l'ordre de leur rang."""
    return list(
        session.scalars(
            select(Artiste)
            .where(Artiste.est_prefere.is_(True), Artiste.deleted_at.is_(None))
            .order_by(Artiste.rang.asc().nulls_last(), Artiste.nom)
        ).all()
    )


def trouver(session: Session, nom: str, genius_id: int | None) -> Artiste | None:
    """Artiste par identifiant Genius, sinon par nom (insensible à la casse)."""
    if genius_id is not None:
        artiste = session.scalar(select(Artiste).where(Artiste.genius_id == genius_id))
        if artiste is not None:
            return artiste
    return session.scalar(
        select(Artiste)
        .where(func.lower(Artiste.nom) == nom.strip().lower(), Artiste.deleted_at.is_(None))
        .order_by(Artiste.genius_id.is_(None))
        .limit(1)
    )


def obtenir_ou_creer(
    session: Session,
    nom: str,
    genius_id: int | None = None,
    musixmatch_id: int | None = None,
    image_url: str | None = None,
) -> Artiste:
    """Retourne l'artiste existant ou le crée avec est_prefere = faux."""
    artiste = trouver(session, nom, genius_id)
    if artiste is None and musixmatch_id is not None:
        artiste = session.scalar(select(Artiste).where(Artiste.musixmatch_id == musixmatch_id))
    if artiste is None:
        artiste = Artiste(
            id=uuid.uuid4(),
            nom=nom.strip(),
            genius_id=genius_id,
            musixmatch_id=musixmatch_id,
            image_url=image_url,
            est_prefere=False,
        )
        session.add(artiste)
        session.flush()
        return artiste
    if genius_id is not None and artiste.genius_id is None:
        artiste.genius_id = genius_id
    if musixmatch_id is not None and artiste.musixmatch_id is None:
        artiste.musixmatch_id = musixmatch_id
    if image_url and not artiste.image_url:
        artiste.image_url = image_url
    return artiste


def remplacer_liste(session: Session, artistes: list[dict]) -> list[Artiste]:
    """L'ordre fixe le rang ; les artistes absents passent à est_prefere = faux (18.6)."""
    choisis: list[Artiste] = []
    vus: set[uuid.UUID] = set()
    for entree in artistes:
        artiste = obtenir_ou_creer(
            session, entree["nom"], entree.get("genius_id"), image_url=entree.get("image_url")
        )
        if artiste.id in vus:
            continue
        vus.add(artiste.id)
        if entree.get("image_url"):
            artiste.image_url = entree["image_url"]
        choisis.append(artiste)
    for artiste in preferes(session):
        if artiste.id not in vus:
            artiste.est_prefere = False
            artiste.rang = None
    session.flush()
    for rang, artiste in enumerate(choisis, start=1):
        artiste.est_prefere = True
        artiste.rang = rang
    session.flush()
    return choisis
