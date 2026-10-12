"""Client Musixmatch (38.1) : morceaux d'un artiste, recherche générale, texte d'un morceau.

Le texte reçu n'est jamais stocké ni journalisé : l'appelant le découpe puis l'oublie (MAT-16).
"""

from app.core.errors import QuotaDepasse
from app.core.resilience import ErreurTemporaire
from app.services.types_externes import (
    ArtisteExterne,
    ClientExterne,
    MorceauExterne,
    RefusService,
    verifier_statut_http,
)

ADRESSE_MUSIXMATCH = "https://api.musixmatch.com/ws/1.1/"
STATUTS_INDISPONIBLES = (401, 403)
STATUTS_QUOTA = (402, 429)


class MusixmatchClient(ClientExterne):
    """Accès à l'API Musixmatch (adresses et paramètres à confirmer à la phase 03)."""

    service = "musixmatch"
    code_indisponible = "musixmatch_indisponible"

    def __init__(self, cle: str | None, *args, adresse: str = ADRESSE_MUSIXMATCH, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.cle = cle
        self.adresse = adresse

    @property
    def configure(self) -> bool:
        """Vrai si une clé est renseignée."""
        return bool(self.cle)

    async def _get(self, methode: str, parametres: dict) -> dict | None:
        """Appel brut : retourne le corps, None pour 404 ; lève selon l'enveloppe."""
        if not self.cle:
            raise self._indisponible()

        async def appel() -> dict | None:
            reponse = await self.http.get(
                self.adresse + methode, params={**parametres, "apikey": self.cle}
            )
            if reponse.status_code in STATUTS_QUOTA:
                raise QuotaDepasse(details={"api": self.service})
            verifier_statut_http(reponse)
            if reponse.status_code in STATUTS_INDISPONIBLES:
                raise RefusService(f"HTTP {reponse.status_code}")
            if reponse.status_code == 404:
                return None
            reponse.raise_for_status()
            message = reponse.json().get("message", {})
            statut = int(message.get("header", {}).get("status_code", 200))
            if statut in STATUTS_QUOTA:
                raise QuotaDepasse(details={"api": self.service})
            if statut in STATUTS_INDISPONIBLES:
                raise RefusService(f"enveloppe {statut}")
            if statut == 404:
                return None
            if statut >= 500:
                raise ErreurTemporaire(f"enveloppe {statut}", statut=statut)
            corps = message.get("body")
            return corps if isinstance(corps, dict) else None

        return await self.appeler(methode, appel)

    async def rechercher_artiste(self, nom: str) -> list[ArtisteExterne]:
        """Recherche d'un artiste pour obtenir son musixmatch_id."""
        corps = await self._get("artist.search", {"q_artist": nom, "page_size": 5})
        resultats = []
        for entree in (corps or {}).get("artist_list", []):
            artiste = entree.get("artist", {})
            if artiste.get("artist_id"):
                resultats.append(
                    ArtisteExterne(
                        nom=artiste.get("artist_name", nom),
                        genius_id=None,
                        musixmatch_id=int(artiste["artist_id"]),
                        image_url=None,
                    )
                )
        return resultats

    @staticmethod
    def _morceaux(corps: dict | None) -> list[MorceauExterne]:
        morceaux = []
        for entree in (corps or {}).get("track_list", []):
            piste = entree.get("track", {})
            if not piste.get("track_id") or not piste.get("has_lyrics", 1):
                continue
            morceaux.append(
                MorceauExterne(
                    musixmatch_track_id=int(piste["track_id"]),
                    titre=piste.get("track_name", ""),
                    artiste_nom=piste.get("artist_name", ""),
                    musixmatch_artist_id=(
                        int(piste["artist_id"]) if piste.get("artist_id") else None
                    ),
                )
            )
        return morceaux

    async def lister_morceaux(self, musixmatch_artist_id: int, limite: int) -> list[MorceauExterne]:
        """Morceaux d'un artiste, les plus populaires d'abord (MAT-02)."""
        corps = await self._get(
            "track.search",
            {
                "f_artist_id": musixmatch_artist_id,
                "s_track_rating": "desc",
                "f_has_lyrics": 1,
                "page_size": limite,
                "page": 1,
            },
        )
        return self._morceaux(corps)[:limite]

    async def rechercher_morceaux_par_texte(self, terme: str, limite: int) -> list[MorceauExterne]:
        """Recherche générale par paroles, sans filtre d'artiste (MAT-18)."""
        corps = await self._get(
            "track.search",
            {
                "q_lyrics": terme,
                "f_has_lyrics": 1,
                "s_track_rating": "desc",
                "page_size": limite,
                "page": 1,
            },
        )
        return self._morceaux(corps)[:limite]

    async def obtenir_texte(self, musixmatch_track_id: int) -> str | None:
        """Texte brut (souvent partiel) d'un morceau, ou None."""
        corps = await self._get("track.lyrics.get", {"track_id": musixmatch_track_id})
        paroles = (corps or {}).get("lyrics", {})
        texte = paroles.get("lyrics_body") if isinstance(paroles, dict) else None
        return texte or None
