"""Verdict de repli par mots-clés (IA-19)."""

import re

from app.services.normalisation import sans_accents

SEUIL_CORRECT = 0.70
SEUIL_PROCHE = 0.40
_NON_MOT = re.compile(r"[^\w\s']")


def _mots(texte: str) -> list[str]:
    propre = _NON_MOT.sub(" ", sans_accents(texte.lower().replace("’", "'")))
    return [m for m in propre.split() if m]


def verdict_par_mots_cles(reference: str, reponse: str) -> str:
    """Part des mots de la référence présents dans la réponse : ≥70 % correct, ≥40 % proche."""
    mots_reference = _mots(reference)
    if not mots_reference:
        return "incorrect"
    mots_reponse = set(_mots(reponse))
    presents = sum(1 for mot in mots_reference if mot in mots_reponse)
    part = presents / len(mots_reference)
    if part >= SEUIL_CORRECT:
        return "correct"
    if part >= SEUIL_PROCHE:
        return "proche"
    return "incorrect"
