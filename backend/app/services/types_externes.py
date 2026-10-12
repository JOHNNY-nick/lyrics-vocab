"""Types échangés avec les clients externes (38.5) et socle commun des clients (COD-03)."""

import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import TypeVar

import httpx

from app.core.errors import QuotaDepasse, ServiceIndisponible
from app.core.logging import journaliser
from app.core.resilience import Disjoncteur, ErreurTemporaire, avec_reessai
from app.services.quotas import Compteur

T = TypeVar("T")


class RefusService(Exception):
    """Réponse définitive refusée par un service (clé invalide, accès restreint)."""


@dataclass
class ArtisteExterne:
    """Artiste renvoyé par Genius ou Musixmatch."""

    nom: str
    genius_id: int | None
    musixmatch_id: int | None
    image_url: str | None


@dataclass
class MorceauExterne:
    """Morceau renvoyé par Musixmatch."""

    musixmatch_track_id: int
    titre: str
    artiste_nom: str
    musixmatch_artist_id: int | None


@dataclass
class MetaMorceau:
    """Métadonnées d'un morceau (Genius)."""

    genius_song_id: int
    url: str | None
    pochette_url: str | None


class ClientExterne:
    """Socle : disjoncteur, quotas, réessais, journalisation des appels (LOG-03)."""

    service = "externe"
    code_indisponible = "service_indisponible"

    def __init__(
        self,
        http: httpx.AsyncClient,
        compteur: Compteur,
        disjoncteur: Disjoncteur,
        dormir: Callable[[float], Awaitable[None]] | None = None,
    ) -> None:
        self.http = http
        self.compteur = compteur
        self.disjoncteur = disjoncteur
        self.dormir = dormir

    def _indisponible(self) -> ServiceIndisponible:
        return ServiceIndisponible(
            details={"service": self.service, "code": self.code_indisponible}
        )

    async def appeler(
        self,
        operation: str,
        fonction: Callable[[], Awaitable[T]],
        caracteres: int = 0,
        tentatives: int = 3,
    ) -> T:
        """Exécute un appel externe protégé ; lève ServiceIndisponible ou QuotaDepasse."""
        if not self.disjoncteur.autoriser():
            raise self._indisponible()
        self.compteur.verifier(self.service, caracteres)
        numero = 0

        async def une_tentative() -> T:
            nonlocal numero
            numero += 1
            debut = time.perf_counter()
            self.compteur.incrementer(self.service, caracteres)
            try:
                resultat = await fonction()
            except QuotaDepasse:
                self._journal(operation, "quota", debut, numero, "quota_depasse")
                raise
            except Exception as exc:
                code = getattr(exc, "statut", None) or type(exc).__name__
                self._journal(operation, "echec", debut, numero, str(code))
                raise
            self._journal(operation, "ok", debut, numero, None)
            return resultat

        options = {"tentatives": tentatives}
        if self.dormir is not None:
            options["dormir"] = self.dormir
        try:
            resultat = await avec_reessai(une_tentative, **options)
        except QuotaDepasse:
            raise
        except (
            ErreurTemporaire,
            RefusService,
            httpx.HTTPError,
            ServiceIndisponible,
            ValueError,
            KeyError,
            TypeError,
        ) as exc:
            self.disjoncteur.enregistrer_echec()
            raise self._indisponible() from exc
        self.disjoncteur.enregistrer_succes()
        return resultat

    def _journal(
        self, operation: str, statut: str, debut: float, tentative: int, code: str | None
    ) -> None:
        journaliser(
            "appel_externe",
            "info" if statut == "ok" else "avertissement",
            service=self.service,
            operation=operation,
            statut=statut,
            duree_ms=round((time.perf_counter() - debut) * 1000),
            tentative=tentative,
            code=code,
        )


def verifier_statut_http(reponse: httpx.Response) -> None:
    """Convertit 408, 429 et 5xx en ErreurTemporaire ; laisse passer les autres."""
    if reponse.status_code in (408, 429) or reponse.status_code >= 500:
        raise ErreurTemporaire(f"HTTP {reponse.status_code}", statut=reponse.status_code)
