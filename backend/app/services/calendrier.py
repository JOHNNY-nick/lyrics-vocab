"""Jour local et dates d'échéance (20.6, ALG-13 à ALG-15)."""

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

BORNE_HORLOGE = timedelta(hours=24)


def fuseau_valide(nom: str | None, defaut: str) -> ZoneInfo:
    """Retourne le fuseau IANA demandé, ou le fuseau par défaut s'il est inconnu."""
    for candidat in (nom, defaut, "UTC"):
        if not candidat:
            continue
        try:
            return ZoneInfo(candidat)
        except (ZoneInfoNotFoundError, ValueError):
            continue
    return ZoneInfo("UTC")  # pragma: no cover


def jour_local(instant_utc: datetime, fuseau: str | ZoneInfo, heure_changement: time) -> date:
    """Date de (heure locale − heure_changement_jour)."""
    zone = fuseau if isinstance(fuseau, ZoneInfo) else ZoneInfo(fuseau)
    if instant_utc.tzinfo is None:
        instant_utc = instant_utc.replace(tzinfo=UTC)
    local = instant_utc.astimezone(zone)
    decalage = timedelta(hours=heure_changement.hour, minutes=heure_changement.minute)
    return (local.replace(tzinfo=None) - decalage).date()


def date_prevue(jour_reponse: date, intervalle: int) -> date:
    """Jour de la réponse + intervalle, en calendrier local."""
    return jour_reponse + timedelta(days=intervalle)


def borner_instant(
    propose: datetime | None, maintenant: datetime, plancher: datetime | None = None
) -> tuple[datetime, bool]:
    """Borne une date de réponse proposée par un appareil (G.6, SYN-31, voir DECISIONS.md).

    Vers le futur : au plus 24 h après l'heure du serveur. Vers le passé : une réponse faite
    hors-ligne plusieurs jours plus tôt reste valable, mais jamais avant `plancher` (création de
    la révision) ni plus de 24 h avant l'heure du serveur quand aucun plancher n'est connu.
    """
    if propose is None:
        return maintenant, False
    if propose.tzinfo is None:
        propose = propose.replace(tzinfo=UTC)
    if propose > maintenant + BORNE_HORLOGE:
        return maintenant + BORNE_HORLOGE, True
    borne_basse = plancher if plancher is not None else maintenant - BORNE_HORLOGE
    if propose < borne_basse:
        return borne_basse, True
    return propose, False
