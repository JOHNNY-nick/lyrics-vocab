"""Client LRCLIB (lrclib.net) : paroles gratuites, sans clé (voir DECISIONS.md).

Utilisé comme source de paroles quand aucune clé Musixmatch n'est configurée. La recherche
renvoie les paroles complètes ; seul l'extrait de 2 lignes est conservé (C1, MAT-16).
"""

from app.services.normalisation import sans_accents
from app.services.types_externes import ClientExterne, MorceauExterne, verifier_statut_http

ADRESSE_LRCLIB = "https://lrclib.net/api"
AGENT = "LyricsVocab/1.0 (application personnelle)"


def _comparable(texte: str) -> str:
    return sans_accents(texte.casefold()).strip()


class LrclibClient(ClientExterne):
    """Recherche de morceaux et de paroles sur LRCLIB."""

    service = "lrclib"
    code_indisponible = "lrclib_indisponible"
    configure = True

    def __init__(self, *args, adresse: str = ADRESSE_LRCLIB, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.adresse = adresse

    async def _rechercher(self, q: str) -> list[dict]:
        async def appel() -> list[dict]:
            reponse = await self.http.get(
                f"{self.adresse}/search", params={"q": q}, headers={"User-Agent": AGENT}
            )
            verifier_statut_http(reponse)
            if reponse.status_code == 404:
                return []
            reponse.raise_for_status()
            donnees = reponse.json()
            return donnees if isinstance(donnees, list) else []

        return await self.appeler("search", appel)

    @staticmethod
    def _morceaux(resultats: list[dict], filtre_artiste: str | None, limite: int) -> list:
        morceaux: list[MorceauExterne] = []
        titres: set[str] = set()
        for r in resultats:
            texte = r.get("plainLyrics")
            if r.get("instrumental") or not texte or not r.get("id"):
                continue
            artiste = r.get("artistName") or ""
            if filtre_artiste and filtre_artiste not in _comparable(artiste):
                continue
            titre = (r.get("trackName") or "").strip()
            cle = _comparable(titre)
            if cle in titres:  # mêmes paroles publiées plusieurs fois
                continue
            titres.add(cle)
            morceaux.append(
                MorceauExterne(
                    musixmatch_track_id=int(r["id"]),
                    titre=titre or "Titre inconnu",
                    artiste_nom=artiste,
                    musixmatch_artist_id=None,
                    texte=texte,
                )
            )
            if len(morceaux) >= limite:
                break
        return morceaux

    async def morceaux_artiste(
        self, nom: str, musixmatch_id: int | None, limite: int
    ) -> tuple[list[MorceauExterne], int | None]:
        """Morceaux de l'artiste (paroles comprises)."""
        resultats = await self._rechercher(nom)
        return self._morceaux(resultats, _comparable(nom), limite), musixmatch_id

    async def rechercher_morceaux_par_texte(self, terme: str, limite: int) -> list:
        """Recherche générale (titre, artiste, album) pour le repli hors liste (MAT-18)."""
        return self._morceaux(await self._rechercher(terme), None, limite)

    async def texte_de(self, morceau: MorceauExterne) -> str | None:
        """Les paroles ont déjà été reçues avec la recherche : aucun appel supplémentaire."""
        return morceau.texte
