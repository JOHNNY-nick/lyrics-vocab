"""Algorithme SM-2 adapté (partie F, 20.5, ALG-11, ALG-12)."""

import math
from dataclasses import dataclass

from app.core.errors import ReponseInvalide

FACILITE_INITIALE = 2.5
FACILITE_MIN = 1.3
INTERVALLE_MAX_DEFAUT = 365
NOTE_REUSSITE_MIN = 3
SEUIL_ACQUIS_DEFAUT = 21

NOTES_RAPPEL = {"ne_savais_pas": 1, "savais": 4, "facile": 5}
NOTES_VERDICT = {"correct": 4, "proche": 3, "incorrect": 1}


@dataclass(frozen=True)
class EtatRevision:
    """État SM-2 d'un mot."""

    repetitions: int = 0
    facilite: float = FACILITE_INITIALE
    intervalle_jours: int = 0


def appliquer(
    etat: EtatRevision, q: int, intervalle_max: int = INTERVALLE_MAX_DEFAUT
) -> EtatRevision:
    """Calcule l'état suivant pour la note q (0 à 5)."""
    if q < NOTE_REUSSITE_MIN:
        return EtatRevision(0, round(etat.facilite, 2), 1)
    if etat.repetitions == 0:
        intervalle = 1
    elif etat.repetitions == 1:
        intervalle = 3
    else:
        intervalle = math.ceil(round(etat.intervalle_jours * etat.facilite, 6))
    facilite = max(FACILITE_MIN, etat.facilite + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
    return EtatRevision(etat.repetitions + 1, round(facilite, 2), min(intervalle, intervalle_max))


def note_depuis_reponse(
    mode: str, reponse: str | None, verdict: str | None, qualite: int | None = None
) -> int:
    """Déduit la note q de la table F.2 ; lève ReponseInvalide sinon."""
    if qualite is not None:
        if not 0 <= qualite <= 5:
            raise ReponseInvalide()
        return qualite
    if verdict is not None:
        if verdict not in NOTES_VERDICT:
            raise ReponseInvalide()
        return NOTES_VERDICT[verdict]
    if mode == "rappel" and reponse in NOTES_RAPPEL:
        return NOTES_RAPPEL[reponse]
    raise ReponseInvalide()


def niveau_depuis_etat(
    etat: EtatRevision,
    derniere_note: int,
    seuil_acquis_jours: int = SEUIL_ACQUIS_DEFAUT,
    niveau_actuel: str = "nouveau",
) -> str:
    """Niveau du mot après une réponse (REV-09)."""
    if derniere_note < NOTE_REUSSITE_MIN:
        return "nouveau" if niveau_actuel == "nouveau" else "en_cours"
    if etat.intervalle_jours > seuil_acquis_jours:
        return "acquis"
    return "en_cours"
