"""Types communs : dates UTC avec Z, heures HH:MM, littéraux (SCH-02)."""

from datetime import UTC, datetime, time
from typing import Annotated, Literal

from pydantic import AwareDatetime, BeforeValidator, PlainSerializer

Niveau = Literal["nouveau", "en_cours", "acquis"]
StatutEnrichissement = Literal["en_attente", "en_cours", "ok", "partiel", "echec"]
Verdict = Literal["correct", "proche", "incorrect"]


def format_utc(valeur: datetime) -> str:
    """Date ISO 8601 en UTC avec le suffixe Z."""
    if valeur.tzinfo is None:
        valeur = valeur.replace(tzinfo=UTC)
    return valeur.astimezone(UTC).isoformat().replace("+00:00", "Z")


def format_heure(valeur: time) -> str:
    """Heure au format HH:MM."""
    return valeur.strftime("%H:%M")


def _lire_heure(valeur: object) -> object:
    if isinstance(valeur, str) and len(valeur) == 5:
        return valeur + ":00"
    return valeur


DateHeureUtc = Annotated[datetime, PlainSerializer(format_utc, return_type=str)]
DateHeureEntree = AwareDatetime
Heure = Annotated[
    time, BeforeValidator(_lire_heure), PlainSerializer(format_heure, return_type=str)
]
