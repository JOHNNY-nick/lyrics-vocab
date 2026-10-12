"""Routes des artistes et des réglages (API-31 à API-33, 18.6)."""

import time

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.core.database import obtenir_session
from app.core.errors import ErreurApi, ParametreInvalide
from app.routers.deps import services
from app.schemas.reglages import ArtisteSortie, ArtistesPreferes, ReglagesSchema
from app.services import artistes, reglages
from app.services.enrichissement import Services

routeur = APIRouter(prefix="/api", tags=["artistes et réglages"])
CACHE_RECHERCHE_S = 24 * 3600
LONGUEUR_MIN_RECHERCHE = 2
RESULTATS_MAX = 10
_cache: dict[str, tuple[float, list[dict]]] = {}


def _artiste_externe(a) -> dict:
    return {"nom": a.nom, "genius_id": a.genius_id, "image_url": a.image_url, "est_prefere": False}


async def _rechercher(conteneur: Services, q: str) -> list[dict]:
    cle = q.strip().lower()
    trouve = _cache.get(cle)
    if trouve and time.monotonic() - trouve[0] < CACHE_RECHERCHE_S:
        return trouve[1]
    resultats = [
        _artiste_externe(a)
        for a in await conteneur.genius.rechercher_artistes(q.strip(), RESULTATS_MAX)
    ]
    _cache[cle] = (time.monotonic(), resultats)
    return resultats


@routeur.get("/artistes/recherche", response_model=list[ArtisteSortie])
async def rechercher(
    q: str = Query(..., max_length=100), conteneur: Services = Depends(services)
) -> list[dict]:
    """Recherche via Genius, 2 caractères au moins, 10 résultats, cache 24 h (CAC-03)."""
    if len(q.strip()) < LONGUEUR_MIN_RECHERCHE:
        raise ParametreInvalide("Saisis au moins 2 caractères.", details={"champ": "q"})
    return await _rechercher(conteneur, q)


@routeur.get("/artistes/suggestions", response_model=list[ArtisteSortie])
async def suggestions(conteneur: Services = Depends(services)) -> list[dict]:
    """Artistes suggérés à l'onboarding, avec photo Genius quand elle est disponible."""
    resultats = []
    for nom in artistes.SUGGESTIONS:
        entree = {"nom": nom, "genius_id": None, "image_url": None, "est_prefere": False}
        if conteneur.genius.configure:
            try:
                trouves = await _rechercher(conteneur, nom)
                exact = next((t for t in trouves if t["nom"].lower() == nom.lower()), None)
                if exact:
                    entree = exact
            except ErreurApi:
                pass
        resultats.append(entree)
    return resultats


@routeur.get("/artistes-preferes", response_model=list[ArtisteSortie])
def lire_preferes(session: Session = Depends(obtenir_session)) -> list:
    """Artistes préférés dans l'ordre."""
    return artistes.preferes(session)


@routeur.put("/artistes-preferes", status_code=status.HTTP_204_NO_CONTENT)
def ecrire_preferes(
    entree: ArtistesPreferes, session: Session = Depends(obtenir_session)
) -> Response:
    """Remplace la liste ordonnée (30 au plus) en une transaction."""
    artistes.remplacer_liste(session, [a.model_dump() for a in entree.artistes])
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@routeur.get("/reglages", response_model=ReglagesSchema)
def lire_reglages(session: Session = Depends(obtenir_session)):
    """Réglages courants."""
    return reglages.obtenir(session)


@routeur.put("/reglages", status_code=status.HTTP_204_NO_CONTENT)
def ecrire_reglages(
    entree: ReglagesSchema, session: Session = Depends(obtenir_session)
) -> Response:
    """Enregistre les réglages ; la dernière écriture reçue gagne."""
    reglages.mettre_a_jour(session, entree.model_dump())
    return Response(status_code=status.HTTP_204_NO_CONTENT)
