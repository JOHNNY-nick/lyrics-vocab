"""Client Ollama (38.4) : génération de texte et contrôle de santé mis en cache 60 s."""

import asyncio
import time
from collections.abc import Callable

import httpx

from app.core.errors import IaIndisponible
from app.core.logging import journaliser
from app.services.quotas import Compteur

CONSERVATION_MODELE = "60m"  # pas de rechargement après une pause
TEMPERATURE = 0.2
DELAI_SANTE_S = 2
CACHE_SANTE_S = 60


class OllamaClient:
    """Accès au modèle local ; aucun prompt ici (IA-07)."""

    service = "ollama"

    def __init__(
        self,
        http: httpx.AsyncClient,
        adresse: str,
        modele: str,
        compteur: Compteur,
        delai_s: int = 30,
        max_paralleles: int = 2,
        horloge: Callable[[], float] = time.monotonic,
    ) -> None:
        self.http = http
        self.adresse = adresse.rstrip("/")
        self.modele = modele
        self.compteur = compteur
        self.delai_s = delai_s
        self.horloge = horloge
        self._file = asyncio.Semaphore(max_paralleles)
        self._sante: tuple[float, bool] | None = None

    async def generer(self, prompt: str, max_jetons: int = 150) -> str:
        """Texte généré ; lève IaIndisponible (réseau, délai, réponse vide)."""
        corps = {
            "model": self.modele,
            "prompt": prompt,
            "stream": False,
            "keep_alive": CONSERVATION_MODELE,
            "options": {"temperature": TEMPERATURE, "num_predict": max_jetons},
        }
        derniere: Exception | None = None
        for tentative in (1, 2):
            debut = time.perf_counter()
            try:
                async with self._file:
                    self.compteur.incrementer(self.service)
                    reponse = await self.http.post(
                        f"{self.adresse}/api/generate", json=corps, timeout=self.delai_s
                    )
                reponse.raise_for_status()
                texte = (reponse.json().get("response") or "").strip()
                if not texte:
                    raise IaIndisponible("Réponse vide du modèle.")
                self._journal("ok", debut, tentative)
                self._sante = (self.horloge(), True)
                return texte
            except (httpx.HTTPError, ValueError, IaIndisponible) as exc:
                derniere = exc
                self._journal("echec", debut, tentative, type(exc).__name__)
        self._sante = (self.horloge(), False)
        raise IaIndisponible() from derniere

    async def disponible(self) -> bool:
        """Contrôle /api/tags avec un délai de 2 s, mis en cache 60 s (IA-24)."""
        if self._sante and self.horloge() - self._sante[0] < CACHE_SANTE_S:
            return self._sante[1]
        try:
            reponse = await self.http.get(f"{self.adresse}/api/tags", timeout=DELAI_SANTE_S)
            etat = reponse.status_code == 200
        except httpx.HTTPError:
            etat = False
        self._sante = (self.horloge(), etat)
        return etat

    def etat_en_cache(self) -> bool | None:
        """Dernier état connu sans appel réseau (pour /api/health, API-34)."""
        return None if self._sante is None else self._sante[1]

    def _journal(self, statut: str, debut: float, tentative: int, code: str | None = None) -> None:
        journaliser(
            "appel_externe",
            "info" if statut == "ok" else "avertissement",
            service=self.service,
            operation="generate",
            statut=statut,
            duree_ms=round((time.perf_counter() - debut) * 1000),
            tentative=tentative,
            code=code,
        )
