"""Exercice de production : phrase à traduire et évaluation de la réponse (E.3, E.4)."""

import json
import re
from dataclasses import dataclass

from app.core.errors import ErreurApi, IaIndisponible
from app.core.logging import journaliser
from app.services.ai_explainer import charger_prompts
from app.services.deepl_client import DeeplClient
from app.services.evaluation_repli import verdict_par_mots_cles
from app.services.normalisation import sans_accents
from app.services.ollama_client import OllamaClient

LONGUEUR_MAX_PHRASE = 120
LONGUEUR_MAX_EXPLICATION_VERDICT = 200
JETONS_PHRASE = 60
JETONS_EVALUATION = 120
VERDICTS = ("correct", "proche", "incorrect")
EXPLICATION_REPLI = "Évaluation simplifiée : comparaison des mots avec la traduction attendue."
MOTIF_INJECTION = re.compile(
    r"(ignore|oublie|instruction|consigne|prompt|syst[eè]me|r[ée]ponds?\s+(correct|juste)|"
    r"verdict|json|answer\s+correct)",
    re.IGNORECASE,
)
_BLOC_CODE = re.compile(r"```(?:json)?", re.IGNORECASE)
_SEPARATEURS_TRADUCTION = re.compile(r"[;,/]| ou ")


@dataclass
class Evaluation:
    """Verdict de l'exercice."""

    verdict: str
    explication: str
    verdict_repli: bool


def mot_principal(traduction: str) -> str:
    """Premier sens de la traduction (« discrètement ; plutôt » → « discrètement »)."""
    premier = _SEPARATEURS_TRADUCTION.split(traduction)[0]
    return premier.strip().strip(".").strip() or traduction.strip()


def _comparable(texte: str) -> str:
    return sans_accents(texte.lower().replace("’", "'"))


def phrase_valide(phrase: str, mot_fr: str) -> bool:
    """Rejette une phrase vide, de plus de 120 caractères ou sans le mot (IA-15)."""
    if not phrase or len(phrase) > LONGUEUR_MAX_PHRASE:
        return False
    cible = _comparable(mot_fr)
    phrase_comparable = _comparable(phrase)
    if cible in phrase_comparable:
        return True
    racine = cible[: max(4, len(cible) - 2)]
    return len(cible) >= 5 and racine in phrase_comparable


def _nettoyer_phrase(brut: str) -> str:
    ligne = brut.strip().splitlines()[0] if brut.strip() else ""
    return ligne.strip().strip("\"'«» “”").strip()


async def generer_phrase(ollama: OllamaClient, mot_fr: str) -> str:
    """Phrase française simple avec le mot ; deux essais puis IaIndisponible."""
    prompts = charger_prompts()["phrase"]
    for tentative in (1, 2):
        phrase = _nettoyer_phrase(
            await ollama.generer(prompts["generation"].format(mot_fr=mot_fr), JETONS_PHRASE)
        )
        if phrase_valide(phrase, mot_fr):
            return phrase
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="phrase",
            tentative=tentative,
            repli_utilise=False,
            version_prompt=prompts["version"],
        )
    raise IaIndisponible()


async def traduire_reference(
    phrase_fr: str, deepl: DeeplClient | None, ollama: OllamaClient
) -> str:
    """Phrase de référence anglaise par DeepL, à défaut par Ollama (IA-14)."""
    if deepl is not None and deepl.configure:
        try:
            reference = await deepl.traduire(phrase_fr, source="FR", cible="EN-US")
            if reference:
                return reference
        except ErreurApi:
            pass
    prompts = charger_prompts()["phrase"]
    brut = await ollama.generer(
        prompts["traduction_reference"].format(phrase_fr=phrase_fr), JETONS_PHRASE
    )
    reference = _nettoyer_phrase(brut)
    if not reference:
        raise IaIndisponible()
    return reference


def analyser_json(brut: str) -> tuple[str, str] | None:
    """Analyse tolérante du JSON du modèle (IA-17) ; None si invalide."""
    texte = _BLOC_CODE.sub("", brut).strip()
    debut, fin = texte.find("{"), texte.rfind("}")
    if debut == -1 or fin <= debut:
        return None
    try:
        donnees = json.loads(texte[debut : fin + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(donnees, dict):
        return None
    verdict = str(donnees.get("verdict", "")).strip().lower()
    explication = str(donnees.get("explication", "")).strip()
    if verdict not in VERDICTS or not explication:
        return None
    return verdict, explication[:LONGUEUR_MAX_EXPLICATION_VERDICT]


def contient_consigne(reponse: str) -> bool:
    """Détecte une tentative de consigne dans la réponse de l'utilisateur (IA-20)."""
    return bool(MOTIF_INJECTION.search(reponse))


def evaluation_repli(reference: str, reponse: str) -> Evaluation:
    """Verdict par mots-clés, marqué verdict_repli (IA-19)."""
    return Evaluation(verdict_par_mots_cles(reference, reponse), EXPLICATION_REPLI, True)


async def evaluer(ollama: OllamaClient, phrase_fr: str, reference: str, reponse: str) -> Evaluation:
    """Évaluation par l'IA ; une nouvelle tentative, puis repli par mots-clés (IA-18)."""
    reponse = reponse[:300]
    if contient_consigne(reponse):
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="evaluation",
            tentative=0,
            repli_utilise=True,
            raison="consigne_dans_reponse",
        )
        return evaluation_repli(reference, reponse)
    prompts = charger_prompts()["evaluation"]
    reponse_brute = reponse.replace("<", " ").replace(">", " ")
    prompt = prompts["consigne"].format(
        phrase_fr=phrase_fr, ref_en=reference, reponse=reponse_brute
    )
    for tentative in (1, 2):
        try:
            brut = await ollama.generer(prompt, JETONS_EVALUATION)
        except IaIndisponible:
            break
        analyse = analyser_json(brut)
        if analyse is not None:
            return Evaluation(analyse[0], analyse[1], False)
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="evaluation",
            tentative=tentative,
            repli_utilise=tentative == 2,
            version_prompt=prompts["version"],
        )
    return evaluation_repli(reference, reponse)
