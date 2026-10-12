"""Modèles ORM (un fichier par groupe de tables de la partie 17)."""

from app.models.artiste import Artiste, Morceau
from app.models.base import ID_REGLAGE, TABLES_SYNCHRONISEES, Base
from app.models.extrait import Extrait
from app.models.mot import Mot
from app.models.reglage import QuotaApi, Reglage, SyncOp
from app.models.revision import Revision

__all__ = [
    "Artiste",
    "Base",
    "Extrait",
    "ID_REGLAGE",
    "Morceau",
    "Mot",
    "QuotaApi",
    "Reglage",
    "Revision",
    "SyncOp",
    "TABLES_SYNCHRONISEES",
]
