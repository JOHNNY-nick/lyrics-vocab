"""Schémas des mots et extraits (37, 18.1 à 18.3)."""

from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.communs import DateHeureUtc, Niveau, StatutEnrichissement


class MotCreation(BaseModel):
    """Entrée de POST /api/mots."""

    model_config = ConfigDict(extra="forbid")
    id: UUID
    terme: str = Field(min_length=1, max_length=100)


class MorceauSortie(BaseModel):
    """Titre et artiste d'un extrait."""

    titre: str
    artiste: str
    url_genius: str | None = None


class ExtraitSortie(BaseModel):
    """Extrait avec positions de surbrillance (indices en points de code)."""

    model_config = ConfigDict(from_attributes=True)
    id: UUID
    texte: str
    surbrillance_debut: int
    surbrillance_fin: int
    hors_liste: bool
    morceau: MorceauSortie


class MotResume(BaseModel):
    """Mot dans une liste."""

    model_config = ConfigDict(from_attributes=True)
    id: UUID
    terme: str
    terme_normalise: str
    traduction_fr: str | None
    statut_enrichissement: StatutEnrichissement
    niveau: Niveau
    prochaine_revision: date | None


class MotDetail(MotResume):
    """Fiche complète d'un mot."""

    explication: str | None
    source_explication: Literal["ia", "traduction_seule"] | None
    erreur_enrichissement: str | None = None
    nb_echecs: int
    extraits: list[ExtraitSortie]
    created_at: DateHeureUtc
    updated_at: DateHeureUtc


class Page(BaseModel):
    """Liste paginée (API-10)."""

    items: list[MotResume]
    total: int
    page: int
    taille: int
