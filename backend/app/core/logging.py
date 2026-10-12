"""Journaux structurés JSON avec rotation et identifiant de corrélation (T-05, LOG-01 à LOG-08)."""

import json
import logging
import logging.handlers
import re
from collections import deque
from contextvars import ContextVar
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

identifiant_correlation: ContextVar[str | None] = ContextVar(
    "identifiant_correlation", default=None
)

NOM_JOURNAL = "lyrics_vocab"
FICHIER_JOURNAL = "backend.jsonl"
NIVEAUX = {
    "debug": logging.DEBUG,
    "info": logging.INFO,
    "avertissement": logging.WARNING,
    "erreur": logging.ERROR,
}
MOTIF_CLE_SECRETE = re.compile(
    r"(key|token|secret|password|mot_de_passe|apikey|authorization)", re.IGNORECASE
)
MASQUE = "***"
ERREURS_RECENTES_MAX = 200

_secrets: list[str] = []
_erreurs_recentes: deque[dict] = deque(maxlen=ERREURS_RECENTES_MAX)
_journal = logging.getLogger(NOM_JOURNAL)


class _FormatJson(logging.Formatter):
    """Le message enregistré est déjà une ligne JSON."""

    def format(self, record: logging.LogRecord) -> str:
        return record.getMessage()


def configurer_journaux(
    dossier: Path | None, taille_mo: int, fichiers: int, secrets: list[str] | None = None
) -> None:
    """Configure la sortie JSON avec rotation (10 Mo × 14 fichiers par défaut)."""
    global _secrets
    _secrets = sorted(secrets or [], key=len, reverse=True)
    for gestionnaire in list(_journal.handlers):
        _journal.removeHandler(gestionnaire)
        gestionnaire.close()
    _journal.setLevel(logging.INFO)
    _journal.propagate = False
    # httpx journalise les adresses complètes (paramètre apikey de Musixmatch) : QUO-07.
    for bavard in ("httpx", "httpcore"):
        logging.getLogger(bavard).setLevel(logging.WARNING)
    if dossier is None:
        _journal.addHandler(logging.NullHandler())
        return
    dossier.mkdir(parents=True, exist_ok=True)
    gestionnaire = logging.handlers.RotatingFileHandler(
        dossier / FICHIER_JOURNAL,
        maxBytes=taille_mo * 1024 * 1024,
        backupCount=fichiers,
        encoding="utf-8",
    )
    gestionnaire.setFormatter(_FormatJson())
    _journal.addHandler(gestionnaire)


def _nettoyer(valeur: Any) -> Any:
    """Retire les valeurs secrètes d'une valeur à journaliser (QUO-07, LOG-04)."""
    if isinstance(valeur, str):
        for secret in _secrets:
            valeur = valeur.replace(secret, MASQUE)
        return valeur
    if isinstance(valeur, dict):
        return {
            k: (MASQUE if MOTIF_CLE_SECRETE.search(str(k)) else _nettoyer(v))
            for k, v in valeur.items()
        }
    if isinstance(valeur, (list, tuple)):
        return [_nettoyer(v) for v in valeur]
    return valeur


def construire_evenement(evenement: str, niveau: str = "info", **champs: Any) -> dict:
    """Construit l'événement JSON (LOG-02) sans secret."""
    donnees: dict[str, Any] = {
        "horodatage": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "niveau": niveau,
        "composant": champs.pop("composant", "backend"),
        "correlation_id": identifiant_correlation.get(),
        "evenement": evenement,
    }
    for cle, valeur in champs.items():
        if MOTIF_CLE_SECRETE.search(cle):
            continue
        donnees[cle] = _nettoyer(valeur)
    return donnees


def journaliser(evenement: str, niveau: str = "info", **champs: Any) -> None:
    """Écrit une ligne JSON pour un événement du catalogue (partie 30)."""
    donnees = construire_evenement(evenement, niveau, **champs)
    if niveau == "erreur":
        _erreurs_recentes.append(donnees)
    _journal.log(
        NIVEAUX.get(niveau, logging.INFO), json.dumps(donnees, ensure_ascii=False, default=str)
    )


def erreurs_recentes(limite: int = 50) -> list[dict]:
    """Dernières erreurs journalisées, la plus récente d'abord (LOG-05)."""
    return list(reversed(_erreurs_recentes))[:limite]
