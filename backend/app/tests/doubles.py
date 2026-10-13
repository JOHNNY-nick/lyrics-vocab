"""Doubles des services externes : aucun test n'appelle une vraie API (QUAL-03, DT-02)."""

import asyncio
from collections import Counter
from dataclasses import dataclass, field

from app.core.errors import IaIndisponible, QuotaDepasse, ServiceIndisponible
from app.core.resilience import Disjoncteur
from app.services.types_externes import ArtisteExterne, MorceauExterne


class CompteurMemoire:
    """Compteur de quotas en mémoire."""

    def __init__(self, limites: dict[str, int] | None = None) -> None:
        self.appels: Counter[str] = Counter()
        self.limites = limites or {}

    def verifier(self, api: str, caracteres: int = 0) -> None:
        if api in self.limites and self.appels[api] >= self.limites[api]:
            raise QuotaDepasse(details={"api": api})

    def incrementer(self, api: str, caracteres: int = 0) -> None:
        self.appels[api] += 1

    def etat(self) -> dict:
        return {
            "jour": "2026-10-12",
            "seuil_alerte_pct": 80,
            "apis": [
                {"api": a, "nb": n, "limite": None, "alerte": False, "atteint": False}
                for a, n in self.appels.items()
            ],
        }


@dataclass
class FauxMusixmatch:
    """Musixmatch simulé : artistes, morceaux et textes en mémoire."""

    compteur: CompteurMemoire
    morceaux_par_artiste: dict[int, list[MorceauExterne]] = field(default_factory=dict)
    morceaux_generaux: list[MorceauExterne] = field(default_factory=list)
    textes: dict[int, str] = field(default_factory=dict)
    ids_artistes: dict[str, int] = field(default_factory=dict)
    panne: bool = False
    quota: bool = False
    lenteur_s: float = 0.0
    disjoncteur: Disjoncteur = field(default_factory=lambda: Disjoncteur("musixmatch", 5, 5))
    configure: bool = True
    service: str = "musixmatch"

    def _appel(self) -> None:
        if self.quota:
            raise QuotaDepasse(details={"api": "musixmatch"})
        if self.panne:
            raise ServiceIndisponible(details={"service": "musixmatch"})
        self.compteur.incrementer("musixmatch")

    async def rechercher_artiste(self, nom: str) -> list[ArtisteExterne]:
        self._appel()
        identifiant = self.ids_artistes.get(nom)
        return [ArtisteExterne(nom, None, identifiant, None)] if identifiant else []

    async def lister_morceaux(self, musixmatch_artist_id: int, limite: int) -> list[MorceauExterne]:
        self._appel()
        return self.morceaux_par_artiste.get(musixmatch_artist_id, [])[:limite]

    async def rechercher_morceaux_par_texte(self, terme: str, limite: int) -> list[MorceauExterne]:
        self._appel()
        return self.morceaux_generaux[:limite]

    async def morceaux_artiste(self, nom: str, musixmatch_id: int | None, limite: int):
        if musixmatch_id is None:
            candidats = await self.rechercher_artiste(nom)
            if not candidats:
                return [], None
            musixmatch_id = candidats[0].musixmatch_id
        return await self.lister_morceaux(musixmatch_id, limite), musixmatch_id

    async def texte_de(self, morceau: MorceauExterne) -> str | None:
        return await self.obtenir_texte(morceau.musixmatch_track_id)

    async def obtenir_texte(self, musixmatch_track_id: int) -> str | None:
        self._appel()
        if self.lenteur_s:
            await asyncio.sleep(self.lenteur_s)
        return self.textes.get(musixmatch_track_id)


@dataclass
class FauxGenius:
    """Genius simulé."""

    compteur: CompteurMemoire
    artistes: list[ArtisteExterne] = field(default_factory=list)
    panne: bool = False
    configure: bool = True

    async def lien_morceau(self, titre: str, artiste: str) -> str | None:
        if self.panne:
            raise ServiceIndisponible(details={"service": "genius"})
        return f"https://lien.test/{titre}"

    async def rechercher_artistes(self, q: str, limite: int = 10) -> list[ArtisteExterne]:
        if self.panne:
            raise ServiceIndisponible(details={"service": "genius"})
        self.compteur.incrementer("genius")
        return [a for a in self.artistes if q.lower() in a.nom.lower()][:limite]


@dataclass
class FauxDeepl:
    """DeepL simulé : dictionnaire de traductions."""

    compteur: CompteurMemoire
    traductions: dict[str, str] = field(default_factory=dict)
    panne: bool = False
    vide: bool = False
    configure: bool = True
    contextes: list[str | None] = field(default_factory=list)

    async def traduire(
        self, texte: str, contexte: str | None = None, source: str = "EN", cible: str = "FR"
    ) -> str | None:
        if self.panne:
            raise ServiceIndisponible(details={"service": "deepl"})
        self.compteur.incrementer("deepl")
        self.contextes.append(contexte)
        if self.vide:
            return None
        return self.traductions.get(texte, f"[{cible}] {texte}")


@dataclass
class FauxOllama:
    """Ollama simulé : réponses programmées dans l'ordre, ou fonction de réponse."""

    compteur: CompteurMemoire
    reponses: list[str] = field(default_factory=list)
    defaut: str = (
        "Argot : ce mot signifie « un peu » ou « en secret ». Ici, il avoue ce qu'il ressent."
    )
    panne: bool = False
    prompts: list[str] = field(default_factory=list)
    # Phrases d'exemple : réponse séparée pour ne pas consommer les réponses programmées.
    exemples: str = '[{"en": "%s", "fr": "Exemple."}]'

    async def generer(self, prompt: str, max_jetons: int = 150) -> str:
        if self.panne:
            raise IaIndisponible()
        self.compteur.incrementer("ollama")
        self.prompts.append(prompt)
        if "phrases d'exemple" in prompt:
            return self.exemples % prompt.split('"')[1]
        return self.reponses.pop(0) if self.reponses else self.defaut

    async def disponible(self) -> bool:
        return not self.panne

    def etat_en_cache(self) -> bool | None:
        return not self.panne
