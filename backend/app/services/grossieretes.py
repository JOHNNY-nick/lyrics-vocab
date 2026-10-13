"""Mots grossiers courants des chansons : traduction et explication de secours.

Le modèle local refuse parfois de traduire ces mots (« je ne peux pas répondre à cette
demande ») ; ils sont pourtant fréquents dans les paroles. Ces entrées ne servent que si
l'IA refuse.
"""

from app.services.normalisation import normaliser

DICTIONNAIRE: dict[str, tuple[str, str]] = {
    "fuck": (
        "putain ; baiser (vulgaire)",
        "Argot très vulgaire : juron pour exprimer la colère, la surprise ou l'insistance "
        "(« putain »), ou verbe signifiant « coucher avec ». À éviter en conversation polie.",
    ),
    "fucking": (
        "putain de ; foutu",
        "Argot très vulgaire : intensifie le mot qui suit (« fucking great » : « super "
        "génial », « this fucking car » : « cette putain de voiture »).",
    ),
    "fucked up": (
        "foutu ; détraqué",
        "Argot vulgaire : se dit d'une situation ratée ou d'une personne qui va très mal.",
    ),
    "motherfucker": (
        "enfoiré ; connard",
        "Insulte très vulgaire ; dans le rap, peut aussi désigner quelqu'un de façon "
        "familière, voire admirative, selon le ton.",
    ),
    "shit": (
        "merde",
        "Argot vulgaire : juron (« merde ») ou, familièrement, « des trucs » (« my shit » : "
        "« mes affaires »).",
    ),
    "bullshit": (
        "conneries",
        "Argot vulgaire : désigne des mensonges ou des absurdités (« c'est des conneries »).",
    ),
    "bitch": (
        "salope ; garce",
        "Insulte vulgaire visant surtout une femme ; dans le rap, s'emploie aussi pour "
        "rabaisser quelqu'un, ou comme verbe « to bitch » : se plaindre.",
    ),
    "damn": (
        "zut ; bon sang",
        "Juron familier assez léger : exprime la surprise ou l'agacement.",
    ),
    "ass": (
        "cul",
        "Familier : le derrière ; « kick ass » (être génial), « dumbass » (abruti).",
    ),
    "asshole": ("connard", "Insulte vulgaire : une personne méprisable."),
    "dick": (
        "bite ; connard",
        "Argot vulgaire : le sexe masculin, ou une personne méchante.",
    ),
    "pussy": (
        "chatte ; mauviette",
        "Argot vulgaire : le sexe féminin, ou une personne lâche.",
    ),
    "bastard": ("salaud ; bâtard", "Insulte : une personne méprisable."),
    "crap": ("merde ; nul", "Familier : quelque chose de mauvais ou sans valeur."),
    "hell": (
        "enfer",
        "Sens propre : l'enfer ; familier dans « what the hell » (« qu'est-ce que… ») "
        "ou « hell yeah » (« carrément »).",
    ),
}


def secours(terme: str) -> tuple[str, str] | None:
    """(traduction, explication) d'un mot grossier connu, sinon None."""
    return DICTIONNAIRE.get(normaliser(terme))
