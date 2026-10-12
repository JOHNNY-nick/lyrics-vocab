"""Schémas de la synchronisation (37, G.4, 18.8)."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

TAILLE_LOT_MAX = 50


class OperationSync(BaseModel):
    """Opération de la file d'actions d'un appareil."""

    op_id: UUID
    type: str = Field(min_length=1, max_length=50)
    donnees: dict


class PushDemande(BaseModel):
    """Lot d'opérations envoyé par un appareil (SCH-03 : 50 au plus)."""

    appareil_id: str = Field(min_length=3, max_length=64)
    operations: list[OperationSync] = Field(max_length=TAILLE_LOT_MAX)


class ResultatOperation(BaseModel):
    """Résultat d'une opération."""

    op_id: UUID
    statut: Literal["applique", "deja_applique", "rejete"]
    code: str | None = None
    message: str | None = None
    donnees: dict | None = None


class PushReponse(BaseModel):
    """Résultats dans l'ordre des opérations reçues."""

    resultats: list[ResultatOperation]


class PullReponse(BaseModel):
    """Changements depuis le curseur, par table."""

    curseur: int
    a_suite: bool
    changements: dict[str, list[dict]]
