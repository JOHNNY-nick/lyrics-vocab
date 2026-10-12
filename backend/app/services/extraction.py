"""Détection du mot dans les paroles et découpe de l'extrait (D.3, D.4, 20.2, 20.3)."""

import re
import unicodedata
from dataclasses import dataclass

from app.services.normalisation import APOSTROPHES, sans_accents

LONGUEUR_MAX_EXTRAIT = 240
CONTEXTE_LIGNE_LONGUE = 100
ELLIPSE = "…"
SEPARATEUR_EXPRESSION = r"[^\w']{1,3}"

MOTIFS_LICENCE = (
    re.compile(r"not\s+for\s+commercial\s+use", re.IGNORECASE),
    re.compile(r"lyrics\s+(powered|provided)\s+by", re.IGNORECASE),
    re.compile(r"musixmatch", re.IGNORECASE),
    re.compile(r"^\*{3,}"),
    re.compile(r"^\(?\d{6,}\)?$"),
    re.compile(r"^\.{3,}$"),
)

# MAT-11 : contractions informelles usuelles (dans les deux sens).
CONTRACTIONS = {
    "gonna": ("going to",),
    "wanna": ("want to",),
    "gotta": ("got to", "have got to"),
    "lemme": ("let me",),
    "gimme": ("give me",),
    "kinda": ("kind of",),
    "outta": ("out of",),
    "dunno": ("don't know",),
}

# MAT-10 : irréguliers fréquents (base -> formes).
IRREGULIERS = {
    "be": ("is", "are", "was", "were", "been", "being", "am"),
    "break": ("broke", "broken"),
    "bring": ("brought",),
    "buy": ("bought",),
    "catch": ("caught",),
    "come": ("came",),
    "do": ("did", "done", "does"),
    "drink": ("drank", "drunk"),
    "drive": ("drove", "driven"),
    "eat": ("ate", "eaten"),
    "fall": ("fell", "fallen"),
    "feel": ("felt",),
    "fight": ("fought",),
    "find": ("found",),
    "fly": ("flew", "flown"),
    "forget": ("forgot", "forgotten"),
    "get": ("got", "gotten"),
    "give": ("gave", "given"),
    "go": ("went", "gone", "goes"),
    "hold": ("held",),
    "keep": ("kept",),
    "know": ("knew", "known"),
    "leave": ("left",),
    "let": ("let",),
    "lose": ("lost",),
    "make": ("made",),
    "mean": ("meant",),
    "meet": ("met",),
    "pay": ("paid",),
    "ride": ("rode", "ridden"),
    "ring": ("rang", "rung"),
    "rise": ("rose", "risen"),
    "run": ("ran",),
    "say": ("said",),
    "see": ("saw", "seen"),
    "sell": ("sold",),
    "send": ("sent",),
    "shine": ("shone",),
    "sing": ("sang", "sung"),
    "sleep": ("slept",),
    "speak": ("spoke", "spoken"),
    "spend": ("spent",),
    "stand": ("stood",),
    "steal": ("stole", "stolen"),
    "take": ("took", "taken"),
    "teach": ("taught",),
    "tell": ("told",),
    "think": ("thought",),
    "throw": ("threw", "thrown"),
    "wake": ("woke", "woken"),
    "wear": ("wore", "worn"),
    "win": ("won",),
    "write": ("wrote", "written"),
}

VOYELLES = "aeiou"


@dataclass(frozen=True)
class Occurrence:
    """Position d'un mot trouvé : indice de ligne et positions dans cette ligne."""

    ligne: int
    debut: int
    fin: int


@dataclass(frozen=True)
class ExtraitDecoupe:
    """Extrait final et positions de surbrillance (points de code)."""

    texte: str
    debut: int
    fin: int


def nettoyer_lignes(texte: str) -> list[str]:
    """Découpe en lignes et retire les lignes vides et les mentions de licence (MAT-15)."""
    lignes = []
    for brute in texte.splitlines():
        ligne = brute.strip()
        if not ligne:
            continue
        if any(motif.search(ligne) for motif in MOTIFS_LICENCE):
            continue
        lignes.append(ligne)
    return lignes


def _normaliser_avec_carte(ligne: str) -> tuple[str, list[int]]:
    """Copie normalisée (NFKC, apostrophes, minuscules, sans accents) et carte vers l'origine."""
    caracteres: list[str] = []
    carte: list[int] = []
    for indice, caractere in enumerate(ligne):
        transforme = unicodedata.normalize("NFKC", caractere)
        for apostrophe in APOSTROPHES:
            transforme = transforme.replace(apostrophe, "'")
        transforme = sans_accents(transforme.lower())
        for c in transforme:
            caracteres.append(c)
            carte.append(indice)
    return "".join(caracteres), carte


def _formes_verbe(mot: str) -> set[str]:
    """Formes en -s, -ed, -ing et irréguliers fréquents (MAT-10)."""
    formes = {mot + "s", mot + "es", mot + "ed", mot + "ing"}
    if mot.endswith("e"):
        formes |= {mot + "d", mot[:-1] + "ing"}
    if len(mot) > 2 and mot.endswith("y") and mot[-2] not in VOYELLES:
        formes |= {mot[:-1] + "ies", mot[:-1] + "ied"}
    if (
        len(mot) >= 3
        and mot[-1] not in VOYELLES + "wxy"
        and mot[-2] in VOYELLES
        and mot[-3] not in VOYELLES
    ):
        formes |= {mot + mot[-1] + "ing", mot + mot[-1] + "ed"}
    formes |= set(IRREGULIERS.get(mot, ()))
    for base, irreguliers in IRREGULIERS.items():
        if mot in irreguliers:
            formes.add(base)
    formes.discard(mot)
    return formes


def variantes_terme(terme: str) -> list[str]:
    """Variantes d'un terme normalisé : formes du premier mot et contractions (MAT-10, MAT-11)."""
    variantes: list[str] = []
    for contraction, developpes in CONTRACTIONS.items():
        if terme == contraction:
            variantes.extend(developpes)
        elif terme in developpes:
            variantes.append(contraction)
    mots = terme.split(" ")
    if mots[0].isalpha():
        for forme in sorted(_formes_verbe(mots[0])):
            variantes.append(" ".join([forme, *mots[1:]]))
    return [v for v in dict.fromkeys(variantes) if v != terme]


def _motif(terme: str) -> re.Pattern[str]:
    """Motif à frontières de mots ; les espaces deviennent une ponctuation légère (ALG-04)."""
    mots = [re.escape(m) for m in sans_accents(terme).split(" ") if m]
    corps = SEPARATEUR_EXPRESSION.join(mots)
    return re.compile(rf"(?<!\w)(?<!\w')(?:{corps})(?!\w)(?!'\w)")


def _occurrences(lignes: list[str], termes: list[str]) -> list[Occurrence]:
    motifs = [_motif(t) for t in termes if t]
    trouvees: list[Occurrence] = []
    for indice, ligne in enumerate(lignes):
        normalisee, carte = _normaliser_avec_carte(ligne)
        for motif in motifs:
            for correspondance in motif.finditer(normalisee):
                if correspondance.end() == correspondance.start():
                    continue
                debut = carte[correspondance.start()]
                fin = carte[correspondance.end() - 1] + 1
                trouvees.append(Occurrence(indice, debut, fin))
    return trouvees


def trouver_occurrences(
    lignes: list[str], terme_normalise: str, variantes: bool
) -> list[Occurrence]:
    """Toutes les occurrences du terme (ou de ses variantes) dans les lignes."""
    termes = variantes_terme(terme_normalise) if variantes else [terme_normalise]
    return _occurrences(lignes, termes)


def _qualite(extrait: ExtraitDecoupe) -> int:
    """0 : deux lignes complètes ; 1 : une ligne complète ; 2 : ligne tronquée."""
    if extrait.texte.startswith(ELLIPSE) or extrait.texte.endswith(ELLIPSE):
        return 2
    return 0 if "\n" in extrait.texte else 1


def trouver_occurrence(
    lignes: list[str], terme_normalise: str, variantes: bool
) -> Occurrence | None:
    """Occurrence dont l'extrait est la plus lisible, la plus courte, la plus tôt (ALG-07)."""
    occurrences = trouver_occurrences(lignes, terme_normalise, variantes)
    if not occurrences:
        return None

    def cle(occ: Occurrence) -> tuple[int, int, int, int]:
        extrait = construire_extrait(lignes, occ)
        return (_qualite(extrait), len(extrait.texte), occ.ligne, occ.debut)

    return min(occurrences, key=cle)


def _couper_ligne(ligne: str, debut: int, fin: int, max_car: int) -> ExtraitDecoupe:
    """Garde le contexte autour du mot en coupant aux frontières de mots, avec « … »."""
    contexte = min(CONTEXTE_LIGNE_LONGUE, max(0, (max_car - (fin - debut) - 2) // 2))
    gauche = max(0, debut - contexte)
    droite = min(len(ligne), fin + contexte)
    if gauche > 0:
        espace = ligne.find(" ", gauche, debut)
        gauche = espace + 1 if espace != -1 else debut
    if droite < len(ligne):
        espace = ligne.rfind(" ", fin, droite)
        droite = espace if espace != -1 else fin
    morceau = ligne[gauche:droite]
    prefixe = ELLIPSE if gauche > 0 else ""
    suffixe = ELLIPSE if droite < len(ligne) else ""
    texte = prefixe + morceau + suffixe
    decalage = len(prefixe) - gauche
    return ExtraitDecoupe(texte, debut + decalage, fin + decalage)


def construire_extrait(
    lignes: list[str], occ: Occurrence, max_car: int = LONGUEUR_MAX_EXTRAIT
) -> ExtraitDecoupe:
    """Ligne trouvée et la suivante (ou la précédente), 240 caractères au plus (20.3)."""
    i = occ.ligne
    ligne = lignes[i]
    if i + 1 < len(lignes):
        texte, decalage = f"{ligne}\n{lignes[i + 1]}", 0
    elif i - 1 >= 0:
        texte, decalage = f"{lignes[i - 1]}\n{ligne}", len(lignes[i - 1]) + 1
    else:
        texte, decalage = ligne, 0
    if len(texte) <= max_car:
        return ExtraitDecoupe(texte, occ.debut + decalage, occ.fin + decalage)
    if len(ligne) <= max_car:
        return ExtraitDecoupe(ligne, occ.debut, occ.fin)
    return _couper_ligne(ligne, occ.debut, occ.fin, max_car)


def extrait_valide(extrait: ExtraitDecoupe, max_car: int = LONGUEUR_MAX_EXTRAIT) -> bool:
    """Rejette un extrait vide, trop long, sans le mot ou réduit à une mention (MAT-17)."""
    if not extrait.texte.strip() or len(extrait.texte) > max_car:
        return False
    if not 0 <= extrait.debut < extrait.fin <= len(extrait.texte):
        return False
    if not extrait.texte[extrait.debut : extrait.fin].strip():
        return False
    return bool(nettoyer_lignes(extrait.texte))


def extraire(texte: str, terme_normalise: str) -> ExtraitDecoupe | None:
    """Cherche l'exacte puis les variantes et construit l'extrait ; le texte n'est pas conservé."""
    lignes = nettoyer_lignes(texte)
    occ = trouver_occurrence(lignes, terme_normalise, variantes=False)
    if occ is None:
        occ = trouver_occurrence(lignes, terme_normalise, variantes=True)
    if occ is None:
        return None
    extrait = construire_extrait(lignes, occ)
    return extrait if extrait_valide(extrait) else None


def masquer_mot(texte: str, debut: int, fin: int) -> str:
    """Remplace le mot par des tirets bas de même longueur (MAQ-05)."""
    return texte[:debut] + "_" * (fin - debut) + texte[fin:]
