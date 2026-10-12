"""Normalisation et validation du terme (B.5, 20.1, ALG-01 à ALG-03)."""

import re
import unicodedata

from app.core.errors import TermeInvalide

LONGUEUR_MAX = 100
MOTS_MAX = 6
APOSTROPHES = ("’", "‘", "ʼ")
MESSAGE_VIDE = "Saisis un mot ou une expression."
MESSAGE_TROP_LONG = "Un mot ou une expression de 6 mots au plus, sans dépasser 100 caractères."

_ESPACES = re.compile(r"\s+")
_PONCTUATION_BORD = re.compile(r"^[^\w']+|[^\w']+$")


def normaliser(terme: str) -> str:
    """Normalise un terme : NFKC, apostrophes, minuscules, espaces, ponctuation de bord."""
    t = unicodedata.normalize("NFKC", terme)
    for apostrophe in APOSTROPHES:
        t = t.replace(apostrophe, "'")
    t = t.lower()
    t = _ESPACES.sub(" ", t).strip()
    t = _PONCTUATION_BORD.sub("", t)
    t = t.strip("'")
    return t


def compter_mots(terme_normalise: str) -> int:
    """Nombre de mots séparés par des espaces."""
    return len([m for m in terme_normalise.split(" ") if m])


def valider_terme(terme: str) -> str:
    """Retourne le terme normalisé ou lève TermeInvalide."""
    brut = terme.strip()
    if len(brut) > LONGUEUR_MAX:
        raise TermeInvalide(MESSAGE_TROP_LONG, details={"champ": "terme"})
    normalise = normaliser(brut)
    if not normalise or not any(c.isalpha() for c in normalise):
        raise TermeInvalide(MESSAGE_VIDE, details={"champ": "terme"})
    if compter_mots(normalise) > MOTS_MAX or len(normalise) > LONGUEUR_MAX:
        raise TermeInvalide(MESSAGE_TROP_LONG, details={"champ": "terme"})
    return normalise


def sans_accents(texte: str) -> str:
    """Retire les marques diacritiques (comparaisons insensibles aux accents)."""
    decompose = unicodedata.normalize("NFD", texte)
    return "".join(c for c in decompose if not unicodedata.combining(c))
