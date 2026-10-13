"""Schémas des réglages et des artistes (37, 18.6)."""

from datetime import time
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.communs import Heure

MAX_ARTISTES = 30
MAX_RAPPELS_SUP = 2

Frequence = Literal[
    "quotidien", "tous_les_2_jours", "tous_les_3_jours", "hebdomadaire", "desactive"
]
Intervalle = Literal[0, 30, 60, 120, 180, 240, 360]
HeureTexte = Annotated[str, Field(pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")]


class ReglagesSchema(BaseModel):
    """Réglages complets."""

    model_config = ConfigDict(from_attributes=True, extra="forbid")
    frequence_rappels: Frequence
    heure_rappel: Heure
    heures_rappel_sup: list[HeureTexte] = Field(default_factory=list, max_length=MAX_RAPPELS_SUP)
    intervalle_notifications_min: Intervalle = 120
    notifications_debut: Heure = time(9, 0)
    notifications_fin: Heure = time(21, 0)
    mots_par_session: int = Field(ge=5, le=100)
    mode_revision: Literal["rappel", "melange"]
    heure_changement_jour: Heure
    sync_wifi_seulement: bool


class ReglagesPartiels(BaseModel):
    """Champs modifiés (opération reglage.modifier)."""

    model_config = ConfigDict(extra="forbid")
    frequence_rappels: Frequence | None = None
    heure_rappel: Heure | None = None
    heures_rappel_sup: list[HeureTexte] | None = Field(default=None, max_length=MAX_RAPPELS_SUP)
    intervalle_notifications_min: Intervalle | None = None
    notifications_debut: Heure | None = None
    notifications_fin: Heure | None = None
    mots_par_session: int | None = Field(default=None, ge=5, le=100)
    mode_revision: Literal["rappel", "melange"] | None = None
    heure_changement_jour: Heure | None = None
    sync_wifi_seulement: bool | None = None


class ArtisteEntree(BaseModel):
    """Artiste choisi (l'ordre du tableau fixe le rang)."""

    model_config = ConfigDict(extra="forbid")
    genius_id: int | None = None
    nom: str = Field(min_length=1, max_length=200)
    image_url: str | None = Field(default=None, max_length=1000)


class ArtistesPreferes(BaseModel):
    """Entrée de PUT /api/artistes-preferes."""

    model_config = ConfigDict(extra="forbid")
    artistes: list[ArtisteEntree] = Field(max_length=MAX_ARTISTES)


class ArtisteSortie(BaseModel):
    """Artiste renvoyé au client."""

    model_config = ConfigDict(from_attributes=True)
    id: UUID | None = None
    nom: str
    genius_id: int | None = None
    image_url: str | None = None
    est_prefere: bool = False
    rang: int | None = None
