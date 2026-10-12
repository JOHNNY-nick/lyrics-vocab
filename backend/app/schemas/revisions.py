"""Schémas des révisions et exercices (37, 18.4, 18.5)."""

from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.communs import DateHeureEntree, Niveau, Verdict
from app.schemas.mots import ExtraitSortie


class ReponseRevision(BaseModel):
    """Entrée de POST /api/revisions/{id}/reponse."""

    model_config = ConfigDict(extra="forbid")
    op_id: UUID
    qualite: int | None = Field(default=None, ge=0, le=5)
    verdict: Verdict | None = None
    reponse: str | None = Field(default=None, max_length=300)
    repondu_le: DateHeureEntree | None = None
    nouvelle_revision_id: UUID | None = None


class ResultatReponse(BaseModel):
    """Résultat d'une réponse : prochaine échéance SM-2."""

    statut: Literal["applique", "deja_applique"]
    prochaine_date: date
    intervalle_jours: int
    facilite: float
    repetitions: int
    niveau: Niveau
    nouvelle_revision_id: UUID | None = None


class RevisionDue(BaseModel):
    """Révision due avec l'indice (mot masqué) et les données révélées."""

    id: UUID
    mot_id: UUID
    mode: Literal["rappel", "production"]
    date_prevue: date
    terme: str
    traduction_fr: str | None
    indice: str | None
    explication: str | None = None
    source_explication: str | None = None
    extrait: ExtraitSortie | None = None


class RevisionsDues(BaseModel):
    """Réponse de GET /api/revisions/dues."""

    total_dus: int
    jour: date
    prochaine_date: date | None = None
    serie: int = 0
    items: list[RevisionDue]


class ExerciceDemande(BaseModel):
    """Entrée de POST /api/exercices."""

    model_config = ConfigDict(extra="forbid")
    mot_id: UUID


class ExerciceSortie(BaseModel):
    """Phrase française à traduire ; l'identifiant est celui de la révision planifiée."""

    id: UUID
    phrase_fr: str
    generee: bool = True


class EvaluationDemande(BaseModel):
    """Entrée de POST /api/exercices/{id}/evaluer."""

    model_config = ConfigDict(extra="forbid")
    reponse: str = Field(min_length=1, max_length=300)


class EvaluationSortie(BaseModel):
    """Verdict de l'exercice ; ne modifie pas SM-2."""

    verdict: Verdict
    explication: str
    verdict_repli: bool
    reference_en: str | None
