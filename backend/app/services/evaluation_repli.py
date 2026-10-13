"""Verdict de repli par mots-clés (IA-19)."""

import re

from app.services.normalisation import sans_accents

SEUIL_CORRECT = 0.70
SEUIL_PROCHE = 0.40
_NON_MOT = re.compile(r"[^\w\s']")


def _mots(texte: str) -> list[str]:
    propre = _NON_MOT.sub(" ", sans_accents(texte.lower().replace("’", "'")))
    return [m for m in propre.split() if m]


MOTS_OUTILS = {
    "a",
    "an",
    "the",
    "is",
    "are",
    "was",
    "were",
    "be",
    "been",
    "am",
    "i",
    "you",
    "he",
    "she",
    "it",
    "we",
    "they",
    "my",
    "your",
    "his",
    "her",
    "its",
    "our",
    "their",
    "me",
    "him",
    "us",
    "them",
    "to",
    "of",
    "in",
    "on",
    "at",
    "for",
    "with",
    "and",
    "or",
    "but",
    "so",
    "that",
    "this",
    "these",
    "those",
    "do",
    "does",
    "did",
    "have",
    "has",
    "had",
    "will",
    "would",
    "can",
    "could",
    "not",
    "very",
    "i'm",
    "it's",
    "don't",
    "s",
}
PREFIXE_COMMUN = 5


def _meme_mot(a: str, b: str) -> bool:
    """Égalité ou même racine (« perfect » et « perfectly »)."""
    if a == b:
        return True
    n = min(len(a), len(b))
    if n >= PREFIXE_COMMUN and a[:PREFIXE_COMMUN] == b[:PREFIXE_COMMUN]:
        return True
    court, long = sorted((a, b), key=len)
    return len(court) >= 4 and long.startswith(court)  # « play » et « playing »


def part_commune(reference: str, reponse: str) -> float:
    """Part des mots porteurs de sens de la référence retrouvés dans la réponse (0 à 1)."""
    porteurs = [m for m in _mots(reference) if m not in MOTS_OUTILS] or _mots(reference)
    if not porteurs:
        return 0.0
    mots_reponse = _mots(reponse)
    trouves = sum(1 for m in porteurs if any(_meme_mot(m, r) for r in mots_reponse))
    return trouves / len(porteurs)


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
