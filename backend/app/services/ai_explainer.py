"""Explication contextuelle par l'IA (E.2, IA-08 à IA-12)."""

import re
import tomllib
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from app.core.errors import IaIndisponible
from app.core.logging import journaliser
from app.services.normalisation import sans_accents
from app.services.ollama_client import OllamaClient

FICHIER_PROMPTS = Path(__file__).resolve().parents[1] / "prompts.toml"
LONGUEUR_MAX_EXPLICATION = 400
MOTS_CITES_MAX = 8
PREFIXES = re.compile(
    r"^\s*(explication|réponse|reponse|voici l'explication|voici|sens)\s*[:：-]\s*", re.IGNORECASE
)
GUILLEMETS_BORD = "\"'«» “”"
MOTS_FRANCAIS = {
    "le",
    "la",
    "les",
    "de",
    "des",
    "du",
    "un",
    "une",
    "est",
    "et",
    "en",
    "que",
    "qui",
    "pour",
    "dans",
    "ce",
    "se",
    "pas",
    "au",
    "aux",
    "il",
    "elle",
    "sur",
    "ou",
    "signifie",
    "veut",
    "dire",
    "c'est",
    "mot",
    "sens",
    "argot",
    "ici",
}
MOTS_ANGLAIS = {
    "the",
    "is",
    "and",
    "of",
    "to",
    "in",
    "it",
    "that",
    "you",
    "this",
    "means",
    "word",
    "slang",
    "here",
    "are",
    "with",
    "for",
}
_MOT = re.compile(r"[\w']+")


class FormatInvalide(IaIndisponible):
    code = "ia_format_invalide"


@lru_cache
def charger_prompts() -> dict:
    """Prompts versionnés du dépôt (IA-07)."""
    with FICHIER_PROMPTS.open("rb") as fichier:
        return tomllib.load(fichier)


@dataclass
class Explication:
    """Explication validée et version du prompt utilisé."""

    texte: str
    version_prompt: str


# Refus du modèle (mots grossiers ou sensibles) : jamais enregistré comme traduction ou
# explication (cas signalé : « fuck » traduit par « je suis désolé, mais je ne peux pas… »).
REFUS = re.compile(
    r"(je ne peux pas|je suis désolé|désolé,? mais|je ne suis pas en mesure|je refuse|"
    r"en tant qu'(ia|intelligence)|contenu (offensant|inapproprié)|"
    r"i can'?t|i cannot|i'?m sorry|as an ai|i won'?t)",
    re.IGNORECASE,
)


def est_refus(texte: str | None) -> bool:
    return bool(texte) and bool(REFUS.search(texte))


def est_francais(texte: str) -> bool:
    """Détection simple : plus de mots outils français qu'anglais (IA-11)."""
    mots = [m.lower() for m in _MOT.findall(texte)]
    francais = sum(1 for m in mots if m in MOTS_FRANCAIS)
    anglais = sum(1 for m in mots if m in MOTS_ANGLAIS)
    accents = sum(1 for c in texte if c in "éèêàùçâîôûœ")
    return francais + min(accents, 3) >= 2 and francais >= anglais


def limiter_citation(explication: str, extrait: str | None, maximum: int = MOTS_CITES_MAX) -> str:
    """Tronque toute reprise de plus de 8 mots consécutifs de l'extrait (IA-12)."""
    if not extrait:
        return explication
    cle = lambda m: sans_accents(m.group(0).lower().replace("’", "'"))  # noqa: E731
    mots_extrait = [cle(m) for m in _MOT.finditer(extrait)]
    sequences = {
        tuple(mots_extrait[i : i + maximum + 1]) for i in range(len(mots_extrait) - maximum)
    }
    if not sequences:
        return explication
    jetons = list(_MOT.finditer(explication))
    valeurs = [cle(m) for m in jetons]
    for i in range(len(jetons) - maximum):
        if tuple(valeurs[i : i + maximum + 1]) in sequences:
            coupure = jetons[i + maximum - 1].end()
            return explication[:coupure].rstrip() + "…"
    return explication


def nettoyer_explication(brut: str, extrait: str | None) -> str:
    """Retire guillemets et préfixes, limite la citation et tronque à 400 caractères."""
    texte = PREFIXES.sub("", brut.strip())
    texte = texte.strip().strip(GUILLEMETS_BORD).strip()
    texte = re.sub(r"\s+", " ", texte)
    texte = limiter_citation(texte, extrait)
    if len(texte) > LONGUEUR_MAX_EXPLICATION:
        coupe = texte[: LONGUEUR_MAX_EXPLICATION - 1]
        fin_phrase = coupe.rfind(". ")
        texte = coupe[: fin_phrase + 1] if fin_phrase > 100 else coupe.rstrip() + "…"
    return texte


async def expliquer(
    ollama: OllamaClient, mot: str, extrait: str | None, max_jetons: int = 150
) -> Explication:
    """Explication validée ; lève IaIndisponible ou FormatInvalide (IA-02, IA-11)."""
    prompts = charger_prompts()["explication"]
    if extrait:
        prompt = prompts["avec_extrait"].format(mot=mot, extrait=extrait.replace("\n", " / "))
    else:
        prompt = prompts["sans_extrait"].format(mot=mot)
    brut = await ollama.generer(prompt, max_jetons)
    texte = nettoyer_explication(brut, extrait)
    if not texte or not est_francais(texte) or est_refus(texte):
        from app.services.grossieretes import secours

        connu = secours(mot)  # mot grossier refusé par le modèle
        if connu:
            return Explication(connu[1], "dictionnaire-grossieretes")
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="explication",
            tentative=1,
            repli_utilise=False,
            version_prompt=prompts["version"],
        )
        raise FormatInvalide("Explication invalide.")
    return Explication(texte, prompts["version"])


def est_argot(explication: str | None, traduction: str | None) -> bool:
    """Vrai si l'explication ou la traduction signale de l'argot (pastille « Argot »)."""
    contenu = " ".join(x for x in (explication, traduction) if x).lower()
    return bool(re.search(r"\bargot", contenu)) and not re.search(
        r"(pas|non|ni)\s+(d'|de l'|de |du )?\s*argot", contenu
    )
