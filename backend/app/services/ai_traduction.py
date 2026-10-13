"""Traduction du mot par l'IA locale quand DeepL n'est pas configuré (voir DECISIONS.md)."""

import re

from app.core.logging import journaliser
from app.services.ai_explainer import charger_prompts, est_refus
from app.services.grossieretes import secours
from app.services.ollama_client import OllamaClient

JETONS_TRADUCTION = 40
LONGUEUR_MAX = 200
MOTS_MAX = 12
_PREFIXE = re.compile(r"^\s*(traduction|réponse|reponse|en français)\s*[:：-]\s*", re.IGNORECASE)
_GUILLEMETS = "\"'«» “”`"


def nettoyer_traduction(brut: str) -> str | None:
    """Première ligne, sans préfixe ni guillemets ; None si la sortie ne ressemble pas à une
    traduction courte."""
    lignes = [x for x in brut.strip().splitlines() if x.strip()]
    if not lignes:
        return None
    texte = _PREFIXE.sub("", lignes[0]).strip().strip(_GUILLEMETS).strip().rstrip(".").strip()
    texte = texte.strip(_GUILLEMETS).strip()
    if not texte or len(texte) > LONGUEUR_MAX or len(texte.split()) > MOTS_MAX:
        return None
    if est_refus(texte):
        return None
    return texte


def accorder_casse(traduction: str, mot: str) -> str:
    """Minuscule initiale quand le mot saisi est en minuscules (« heart » → « cœur »)."""
    if mot[:1].islower() and traduction[:1].isupper() and traduction[1:2].islower():
        return traduction[:1].lower() + traduction[1:]
    return traduction


async def traduire_par_ia(ollama: OllamaClient, mot: str, contexte: str | None) -> str | None:
    """Traduction courte du mot, en tenant compte de l'extrait s'il existe (TRA-03)."""
    prompts = charger_prompts()["traduction"]
    partie_contexte = (
        prompts["contexte"].format(extrait=contexte.replace("\n", " / ")).rstrip()
        if contexte
        else ""
    )
    for tentative in (1, 2):
        brut = await ollama.generer(
            prompts["mot"].format(mot=mot, contexte=partie_contexte), JETONS_TRADUCTION
        )
        traduction = nettoyer_traduction(brut)
        if traduction:
            return accorder_casse(traduction, mot)
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="traduction",
            tentative=tentative,
            version_prompt=prompts["version"],
        )
    connu = secours(mot)  # mot grossier refusé par le modèle
    return connu[0] if connu else None
