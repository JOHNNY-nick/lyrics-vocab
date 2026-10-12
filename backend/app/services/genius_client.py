"""Client Genius (38.2) : recherche d'artistes et métadonnées, jamais de paroles."""

from app.services.types_externes import (
    ArtisteExterne,
    ClientExterne,
    MetaMorceau,
    RefusService,
    verifier_statut_http,
)

ADRESSE_GENIUS = "https://api.genius.com"
STATUTS_INDISPONIBLES = (401, 403)


class GeniusClient(ClientExterne):
    """Accès à l'API Genius (adresses à confirmer à la phase 03)."""

    service = "genius"
    code_indisponible = "genius_indisponible"

    def __init__(self, jeton: str | None, *args, adresse: str = ADRESSE_GENIUS, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.jeton = jeton
        self.adresse = adresse

    @property
    def configure(self) -> bool:
        """Vrai si un jeton est renseigné."""
        return bool(self.jeton)

    async def _rechercher(self, q: str) -> list[dict]:
        if not self.jeton:
            raise self._indisponible()

        async def appel() -> list[dict]:
            reponse = await self.http.get(
                f"{self.adresse}/search",
                params={"q": q},
                headers={"Authorization": f"Bearer {self.jeton}"},
            )
            verifier_statut_http(reponse)
            if reponse.status_code in STATUTS_INDISPONIBLES:
                raise RefusService(f"HTTP {reponse.status_code}")
            if reponse.status_code == 404:
                return []
            reponse.raise_for_status()
            hits = reponse.json().get("response", {}).get("hits", [])
            return [h.get("result", {}) for h in hits if isinstance(h, dict)]

        return await self.appeler("search", appel)

    async def rechercher_artistes(self, q: str, limite: int = 10) -> list[ArtisteExterne]:
        """Artistes dédoublonnés par genius_id, dans l'ordre de pertinence."""
        artistes: list[ArtisteExterne] = []
        vus: set[int] = set()
        for resultat in await self._rechercher(q):
            principal = resultat.get("primary_artist") or {}
            identifiant = principal.get("id")
            if not identifiant or identifiant in vus:
                continue
            vus.add(identifiant)
            image = principal.get("image_url")
            if image and "default_avatar" in image:
                image = None
            artistes.append(
                ArtisteExterne(
                    nom=principal.get("name", ""),
                    genius_id=int(identifiant),
                    musixmatch_id=None,
                    image_url=image,
                )
            )
            if len(artistes) >= limite:
                break
        return artistes

    async def metadonnees_morceau(self, titre: str, artiste: str) -> MetaMorceau | None:
        """Identifiant, adresse et pochette d'un morceau (S)."""
        for resultat in await self._rechercher(f"{titre} {artiste}"):
            nom = (resultat.get("primary_artist") or {}).get("name", "")
            if nom.lower() == artiste.lower() and resultat.get("id"):
                return MetaMorceau(
                    genius_song_id=int(resultat["id"]),
                    url=resultat.get("url"),
                    pochette_url=resultat.get("song_art_image_thumbnail_url"),
                )
        return None
