"""Phrases d'exemple pour apprendre à employer le mot, générées par l'IA locale."""

import json
import re

from app.core.logging import journaliser
from app.services.ai_explainer import charger_prompts
from app.services.extraction import trouver_occurrences
from app.services.normalisation import normaliser
from app.services.ollama_client import OllamaClient

NOMBRE_MAX = 3
LONGUEUR_MAX = 160
JETONS_EXEMPLES = 220
_BLOC_CODE = re.compile(r"```(?:json)?", re.IGNORECASE)


def valider_exemples(brut: str, terme: str) -> list[dict] | None:
    """Liste [{en, fr}] dont chaque phrase anglaise contient le mot (ou une de ses formes)."""
    texte = _BLOC_CODE.sub("", brut).strip()
    debut, fin = texte.find("["), texte.rfind("]")
    if debut == -1 or fin <= debut:
        return None
    try:
        donnees = json.loads(texte[debut : fin + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(donnees, list):
        return None
    terme_normalise = normaliser(terme)
    exemples = []
    for element in donnees:
        if not isinstance(element, dict):
            continue
        en = str(element.get("en", "")).strip().strip('"')
        fr = str(element.get("fr", "")).strip().strip('"')
        if not en or not fr or len(en) > LONGUEUR_MAX or len(fr) > LONGUEUR_MAX:
            continue
        if not (
            trouver_occurrences([en], terme_normalise, variantes=False)
            or trouver_occurrences([en], terme_normalise, variantes=True)
        ):
            continue
        exemples.append({"en": en, "fr": fr})
        if len(exemples) >= NOMBRE_MAX:
            break
    return exemples or None


async def generer_exemples(
    ollama: OllamaClient, terme: str, traduction: str, extrait: str | None
) -> list[dict] | None:
    """Deux phrases d'exemple validées ; deux essais au plus."""
    prompts = charger_prompts()["exemples"]
    contexte = (
        prompts["contexte"].format(extrait=" / ".join(extrait.splitlines())) if extrait else ""
    )
    prompt = prompts["consigne"].format(mot=terme, traduction=traduction, contexte=contexte)
    for tentative in (1, 2):
        exemples = valider_exemples(await ollama.generer(prompt, JETONS_EXEMPLES), terme)
        if exemples:
            return exemples
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="exemples",
            tentative=tentative,
            version_prompt=prompts["version"],
        )
    return None
