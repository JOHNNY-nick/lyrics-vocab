"""Compteurs de quotas des API externes (D.8, QUO-01 à QUO-04, OBS-03)."""

import threading
from collections.abc import Callable
from datetime import UTC, date, datetime
from typing import Protocol

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Parametres
from app.core.errors import QuotaDepasse
from app.core.logging import journaliser
from app.models import QuotaApi
from app.services.calendrier import fuseau_valide

APIS = ("musixmatch", "genius", "deepl", "ollama")


class Compteur(Protocol):
    """Interface commune des compteurs de quota (injectée dans les clients)."""

    def verifier(self, api: str, caracteres: int = 0) -> None: ...

    def incrementer(self, api: str, caracteres: int = 0) -> None: ...


class CompteurQuotas:
    """Compteur persistant dans quota_api, jour courant au fuseau du PC."""

    def __init__(
        self,
        fabrique: sessionmaker[Session],
        parametres: Parametres,
        horloge: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self.fabrique = fabrique
        self.parametres = parametres
        self.horloge = horloge
        self._alertes: set[tuple[str, date]] = set()
        self._verrou = threading.Lock()

    def jour(self) -> date:
        """Jour courant au fuseau du PC."""
        return self.horloge().astimezone(fuseau_valide(None, self.parametres.fuseau_pc)).date()

    def limite_jour(self, api: str) -> int | None:
        """Limite journalière d'appels (None : aucune)."""
        return {
            "musixmatch": self.parametres.quota_musixmatch_jour,
            "genius": self.parametres.quota_genius_jour,
        }.get(api)

    def _compteurs(self, session: Session, api: str, jour: date) -> tuple[int, int]:
        ligne = session.get(QuotaApi, (api, jour))
        nb = ligne.nb if ligne else 0
        debut_mois = jour.replace(day=1)
        caracteres_mois = (
            session.scalar(
                select(func.coalesce(func.sum(QuotaApi.caracteres), 0)).where(
                    QuotaApi.api == api, QuotaApi.jour >= debut_mois, QuotaApi.jour <= jour
                )
            )
            or 0
        )
        return nb, int(caracteres_mois)

    def verifier(self, api: str, caracteres: int = 0) -> None:
        """Lève QuotaDepasse si la limite du service est atteinte (QUO-03)."""
        jour = self.jour()
        with self.fabrique() as session:
            nb, caracteres_mois = self._compteurs(session, api, jour)
        limite = self.limite_jour(api)
        if limite is not None and nb >= limite:
            journaliser("quota_atteint", "erreur", service=api, jour=jour.isoformat())
            raise QuotaDepasse(details={"api": api})
        if api == "deepl" and caracteres_mois + caracteres > self.parametres.quota_deepl_mois:
            journaliser("quota_atteint", "erreur", service=api, jour=jour.isoformat())
            raise QuotaDepasse(details={"api": api})

    def incrementer(self, api: str, caracteres: int = 0) -> None:
        """Compte un appel sortant (QUO-01) et alerte à 80 % (QUO-03)."""
        jour = self.jour()
        with self._verrou, self.fabrique() as session:
            session.execute(
                insert(QuotaApi)
                .values(api=api, jour=jour, nb=1, caracteres=caracteres)
                .on_conflict_do_update(
                    index_elements=[QuotaApi.api, QuotaApi.jour],
                    set_={"nb": QuotaApi.nb + 1, "caracteres": QuotaApi.caracteres + caracteres},
                )
            )
            session.commit()
            nb, caracteres_mois = self._compteurs(session, api, jour)
        self._alerter(api, jour, nb, caracteres_mois)

    def _pourcentage(self, api: str, nb: int, caracteres_mois: int) -> float | None:
        if api == "deepl":
            return 100 * caracteres_mois / max(self.parametres.quota_deepl_mois, 1)
        limite = self.limite_jour(api)
        return None if not limite else 100 * nb / limite

    def _alerter(self, api: str, jour: date, nb: int, caracteres_mois: int) -> None:
        pourcentage = self._pourcentage(api, nb, caracteres_mois)
        if pourcentage is None or pourcentage < self.parametres.quota_alerte_pct:
            return
        if (api, jour) in self._alertes:
            return
        self._alertes.add((api, jour))
        journaliser(
            "quota_alerte",
            "avertissement",
            service=api,
            nb=nb,
            limite=self.limite_jour(api) or self.parametres.quota_deepl_mois,
            pourcentage=round(pourcentage, 1),
        )

    def etat(self) -> dict:
        """Compteurs du jour par API et seuils d'alerte (GET /api/quotas)."""
        jour = self.jour()
        apis = []
        with self.fabrique() as session:
            for api in APIS:
                nb, caracteres_mois = self._compteurs(session, api, jour)
                pourcentage = self._pourcentage(api, nb, caracteres_mois)
                entree: dict = {
                    "api": api,
                    "nb": nb,
                    "limite": self.limite_jour(api),
                    "alerte": pourcentage is not None
                    and pourcentage >= self.parametres.quota_alerte_pct,
                    "atteint": pourcentage is not None and pourcentage >= 100,
                }
                if api == "deepl":
                    entree.update(
                        caracteres_mois=caracteres_mois,
                        limite_mois=self.parametres.quota_deepl_mois,
                    )
                apis.append(entree)
        return {
            "jour": jour.isoformat(),
            "seuil_alerte_pct": self.parametres.quota_alerte_pct,
            "apis": apis,
        }
