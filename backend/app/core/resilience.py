"""Réessais avec attente croissante et disjoncteur (T-12, ALG-08, ALG-10, QUO-05, QUO-06)."""

import asyncio
import time
from collections.abc import Awaitable, Callable
from typing import TypeVar

import httpx
from tenacity import AsyncRetrying, RetryError, retry_if_exception, stop_after_attempt

from app.core.logging import journaliser

T = TypeVar("T")

DELAIS_SERVEUR_S = (1, 2, 4)
STATUTS_TEMPORAIRES = (408, 429)


class ErreurTemporaire(Exception):
    """Erreur qui mérite une nouvelle tentative (délai, réseau, 408, 429, 5xx)."""

    def __init__(self, message: str = "", statut: int | None = None) -> None:
        super().__init__(message)
        self.statut = statut


def est_temporaire(exc: BaseException) -> bool:
    """Vrai pour les erreurs à rejouer seulement (ALG-10)."""
    if isinstance(exc, ErreurTemporaire):
        return True
    if isinstance(exc, (httpx.TimeoutException, httpx.NetworkError, httpx.RemoteProtocolError)):
        return True
    if isinstance(exc, httpx.HTTPStatusError):
        statut = exc.response.status_code
        return statut in STATUTS_TEMPORAIRES or statut >= 500
    return False


async def avec_reessai(
    fonction: Callable[[], Awaitable[T]],
    *,
    tentatives: int = 3,
    delais: tuple[float, ...] = DELAIS_SERVEUR_S,
    dormir: Callable[[float], Awaitable[None]] = asyncio.sleep,
) -> T:
    """Exécute fonction en réessayant seulement les erreurs temporaires."""

    def attente(etat) -> float:
        indice = min(etat.attempt_number - 1, len(delais) - 1)
        return delais[indice]

    try:
        async for tentative in AsyncRetrying(
            stop=stop_after_attempt(tentatives),
            wait=attente,
            retry=retry_if_exception(est_temporaire),
            sleep=dormir,
            reraise=True,
        ):
            with tentative:
                return await fonction()
    except RetryError as exc:  # pragma: no cover - reraise=True évite ce cas
        raise exc.last_attempt.exception() from None
    raise RuntimeError("avec_reessai : aucune tentative exécutée")  # pragma: no cover


class Disjoncteur:
    """Après `seuil` échecs consécutifs, service suspendu `pause_min` minutes."""

    def __init__(
        self,
        service: str,
        seuil: int,
        pause_min: int,
        horloge: Callable[[], float] = time.monotonic,
    ) -> None:
        self.service = service
        self.seuil = seuil
        self.pause_s = pause_min * 60
        self.horloge = horloge
        self.echecs = 0
        self.ouvert_jusqua: float | None = None

    def autoriser(self) -> bool:
        """Vrai si un appel peut être tenté."""
        if self.ouvert_jusqua is None:
            return True
        if self.horloge() >= self.ouvert_jusqua:
            self.ouvert_jusqua = None
            self.echecs = 0
            return True
        return False

    def enregistrer_succes(self) -> None:
        """Remet le compteur d'échecs à zéro."""
        self.echecs = 0
        self.ouvert_jusqua = None

    def enregistrer_echec(self) -> None:
        """Compte un échec et ouvre le disjoncteur au seuil."""
        self.echecs += 1
        if self.echecs >= self.seuil and self.ouvert_jusqua is None:
            self.ouvert_jusqua = self.horloge() + self.pause_s
            journaliser(
                "disjoncteur_ouvert",
                "avertissement",
                service=self.service,
                echecs=self.echecs,
                pause_min=self.pause_s // 60,
            )
