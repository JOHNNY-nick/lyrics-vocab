"""Client Deezer : recherche d'artistes et photos, gratuite et sans clé (voir DECISIONS.md).

Utilisé à la place de Genius quand aucun jeton Genius n'est configuré.
"""

from app.services.types_externes import ArtisteExterne, ClientExterne, verifier_statut_http

ADRESSE_DEEZER = "https://api.deezer.com"
RESULTATS_BRUTS = 25


class DeezerClient(ClientExterne):
    """Recherche d'artistes sur Deezer, les plus suivis d'abord."""

    service = "deezer"
    code_indisponible = "deezer_indisponible"
    configure = True

    def __init__(self, *args, adresse: str = ADRESSE_DEEZER, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.adresse = adresse

    async def rechercher_artistes(self, q: str, limite: int = 10) -> list[ArtisteExterne]:
        """Artistes dédoublonnés par nom ; l'homonyme le plus suivi est gardé."""

        async def appel() -> list[dict]:
            reponse = await self.http.get(
                f"{self.adresse}/search/artist", params={"q": q, "limit": RESULTATS_BRUTS}
            )
            verifier_statut_http(reponse)
            reponse.raise_for_status()
            corps = reponse.json()
            if "error" in corps:
                raise ValueError(str(corps["error"]))
            return corps.get("data", [])

        resultats = await self.appeler("search_artist", appel)
        meilleurs: dict[str, dict] = {}
        ordre: list[str] = []
        for r in resultats:
            nom = (r.get("name") or "").strip()
            if not nom:
                continue
            cle = nom.casefold()
            if cle not in meilleurs:
                ordre.append(cle)
                meilleurs[cle] = r
            elif (r.get("nb_fan") or 0) > (meilleurs[cle].get("nb_fan") or 0):
                meilleurs[cle] = r
        tries = sorted(ordre, key=lambda c: -(meilleurs[c].get("nb_fan") or 0))
        exacts = [c for c in tries if c == q.strip().casefold()]
        tries = exacts + [c for c in tries if c not in exacts]
        return [
            ArtisteExterne(
                nom=meilleurs[c]["name"].strip(),
                genius_id=None,
                musixmatch_id=None,
                image_url=meilleurs[c].get("picture_medium") or None,
            )
            for c in tries[:limite]
        ]

    async def metadonnees_morceau(self, titre: str, artiste: str) -> None:
        """Non fourni par Deezer dans cette application."""
        return None
