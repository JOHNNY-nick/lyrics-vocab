"""Exercice de production : phrase à traduire et évaluation de la réponse (E.3, E.4)."""

import json
import re
from dataclasses import dataclass

from app.core.errors import ErreurApi, IaIndisponible
from app.core.logging import journaliser
from app.services.ai_explainer import charger_prompts
from app.services.deepl_client import DeeplClient
from app.services.evaluation_repli import part_commune, verdict_par_mots_cles
from app.services.extraction import trouver_occurrences
from app.services.normalisation import normaliser, sans_accents
from app.services.ollama_client import OllamaClient

LONGUEUR_MAX_PHRASE = 120
LONGUEUR_MAX_EXPLICATION_VERDICT = 200
JETONS_PHRASE = 60
JETONS_EVALUATION = 120
JETONS_EXERCICE = 120
ESSAIS_EXERCICE = 3
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


def emploie_terme(phrase: str, terme: str) -> bool:
    """La phrase contient le mot ou une de ses formes (lowkey, gave up…)."""
    terme_normalise = normaliser(terme)
    return bool(
        trouver_occurrences([phrase], terme_normalise, variantes=False)
        or trouver_occurrences([phrase], terme_normalise, variantes=True)
    )


def analyser_paire(brut: str) -> tuple[str, str] | None:
    """(phrase française, phrase anglaise) depuis le JSON du modèle ; None si invalide."""
    texte = _BLOC_CODE.sub("", brut).strip()
    debut = texte.find("{")
    fin = texte.find("}", debut)
    if debut == -1 or fin <= debut:
        return None
    try:
        donnees = json.loads(texte[debut : fin + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(donnees, dict):
        return None
    fr = _nettoyer_phrase(str(donnees.get("fr", "")))
    en = _nettoyer_phrase(str(donnees.get("en", "")))
    if not fr or not en or len(fr) > LONGUEUR_MAX_PHRASE or len(en) > LONGUEUR_MAX_PHRASE:
        return None
    return fr, en


async def generer_exercice(
    ollama: OllamaClient, terme: str, traduction: str, deja_vues: list[str] | None = None
) -> tuple[str, str]:
    """Phrase française contenant le sens du mot, et sa traduction anglaise qui emploie le mot.

    La phrase anglaise doit contenir le mot ; la française doit contenir sa traduction et ne
    pas citer le mot anglais (sinon la réponse serait donnée). À défaut d'une paire parfaite,
    une paire dont seule la phrase anglaise est juste est acceptée (synonyme en français).
    """
    prompts = charger_prompts()["exercice"]
    mot_fr = mot_principal(traduction)
    a_eviter = (
        prompts["a_eviter"].format(phrases=" ; ".join(f'"{p}"' for p in deja_vues))
        if deja_vues
        else ""
    )
    prompt = prompts["consigne"].format(
        mot=terme, traduction=traduction, mot_fr=mot_fr, a_eviter=a_eviter
    )
    secours: tuple[str, str] | None = None
    for tentative in range(1, ESSAIS_EXERCICE + 1):
        paire = analyser_paire(await ollama.generer(prompt, JETONS_EXERCICE))
        if paire is not None:
            fr, en = paire
            if emploie_terme(en, terme) and not emploie_terme(fr, terme):
                if phrase_valide(fr, mot_fr):
                    return fr, en
                secours = secours or paire
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="exercice",
            tentative=tentative,
            version_prompt=prompts["version"],
        )
    if secours is not None:
        return secours
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


SEUIL_HORS_SUJET = 0.25
SEUIL_CORRECT_MIN = 0.5
EXPLICATION_HORS_SUJET = (
    "Ta phrase ne traduit pas celle qui était proposée : compare avec la traduction attendue."
)


def explication_sans_terme(terme: str) -> str:
    return f"Le sens y est, mais il fallait employer ton mot « {terme} »."


def garde_fou(
    evaluation: Evaluation, reference: str, reponse: str, terme: str | None = None
) -> Evaluation:
    """Corrige un verdict trop généreux du modèle quand la réponse s'éloigne de la référence.

    Moins d'un quart des mots porteurs de sens retrouvés : incorrect. Moins de la moitié : au
    mieux « proche ». Le modèle reste seul juge au-delà (paraphrases, synonymes). Le but étant
    d'employer le mot : une réponse qui ne le contient pas est au mieux « proche ».
    """
    part = part_commune(reference, reponse)
    if part < SEUIL_HORS_SUJET and evaluation.verdict != "incorrect":
        return Evaluation("incorrect", EXPLICATION_HORS_SUJET, evaluation.verdict_repli)
    if part < SEUIL_CORRECT_MIN and evaluation.verdict == "correct":
        return Evaluation("proche", evaluation.explication, evaluation.verdict_repli)
    if terme and evaluation.verdict == "correct" and not emploie_terme(reponse, terme):
        return Evaluation("proche", explication_sans_terme(terme), evaluation.verdict_repli)
    return evaluation


def contient_consigne(reponse: str) -> bool:
    """Détecte une tentative de consigne dans la réponse de l'utilisateur (IA-20)."""
    return bool(MOTIF_INJECTION.search(reponse))


def evaluation_repli(reference: str, reponse: str) -> Evaluation:
    """Verdict par mots-clés, marqué verdict_repli (IA-19)."""
    return Evaluation(verdict_par_mots_cles(reference, reponse), EXPLICATION_REPLI, True)


async def evaluer(
    ollama: OllamaClient, phrase_fr: str, reference: str, reponse: str, terme: str | None = None
) -> Evaluation:
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
        return garde_fou(evaluation_repli(reference, reponse), reference, reponse, terme)
    prompts = charger_prompts()["evaluation"]
    reponse_brute = reponse.replace("<", " ").replace(">", " ")
    mot_attendu = prompts["mot_attendu"].format(mot=terme) if terme else ""
    prompt = prompts["consigne"].format(
        phrase_fr=phrase_fr, ref_en=reference, reponse=reponse_brute, mot_attendu=mot_attendu
    )
    for tentative in (1, 2):
        try:
            brut = await ollama.generer(prompt, JETONS_EVALUATION)
        except IaIndisponible:
            break
        analyse = analyser_json(brut)
        if analyse is not None:
            return garde_fou(Evaluation(analyse[0], analyse[1], False), reference, reponse, terme)
        journaliser(
            "ia_sortie_invalide",
            "avertissement",
            tache="evaluation",
            tentative=tentative,
            repli_utilise=tentative == 2,
            version_prompt=prompts["version"],
        )
    return garde_fou(evaluation_repli(reference, reponse), reference, reponse, terme)
