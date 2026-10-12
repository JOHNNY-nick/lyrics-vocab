"""Logique métier pure : SM-2, normalisation, jour local, extraction, repli (41.1, 41.2)."""

import asyncio
from datetime import UTC, date, datetime, time
from zoneinfo import ZoneInfo

import httpx
import pytest

from app.core.errors import ReponseInvalide, TermeInvalide
from app.core.resilience import Disjoncteur, ErreurTemporaire, avec_reessai
from app.services import sm2
from app.services.calendrier import borner_instant, date_prevue, jour_local
from app.services.evaluation_repli import verdict_par_mots_cles
from app.services.extraction import (
    Occurrence,
    construire_extrait,
    extraire,
    masquer_mot,
    nettoyer_lignes,
    trouver_occurrence,
)
from app.services.normalisation import normaliser, valider_terme

# --- SM-2 (F.4) -----------------------------------------------------------------------------

CAS_SM2 = [
    ((0, 2.5, 0), 4, (1, 2.5, 1)),
    ((1, 2.5, 1), 4, (2, 2.5, 3)),
    ((2, 2.5, 3), 4, (3, 2.5, 8)),
    ((3, 2.5, 8), 5, (4, 2.6, 20)),
    ((3, 2.5, 8), 3, (4, 2.36, 20)),
    ((3, 2.5, 8), 1, (0, 2.5, 1)),
    ((2, 1.3, 3), 3, (3, 1.3, 4)),
    ((0, 2.5, 0), 0, (0, 2.5, 1)),
]


@pytest.mark.parametrize(
    ("depart", "q", "attendu"), CAS_SM2, ids=[f"sm2_cas_{i}" for i in range(1, 9)]
)
def test_sm2_cas(depart, q, attendu):
    resultat = sm2.appliquer(sm2.EtatRevision(*depart), q)
    assert (resultat.repetitions, resultat.facilite, resultat.intervalle_jours) == attendu


def test_sm2_plafond():
    assert sm2.appliquer(sm2.EtatRevision(5, 2.5, 200), 4).intervalle_jours == 365


def test_sm2_facilite_minimale():
    assert sm2.appliquer(sm2.EtatRevision(3, 1.3, 10), 3).facilite == 1.3


def test_notes():
    assert sm2.note_depuis_reponse("rappel", "savais", None) == 4
    assert sm2.note_depuis_reponse("rappel", "ne_savais_pas", None) == 1
    assert sm2.note_depuis_reponse("production", None, "proche") == 3
    with pytest.raises(ReponseInvalide):
        sm2.note_depuis_reponse("rappel", None, None)


def test_niveaux():
    assert sm2.niveau_depuis_etat(sm2.EtatRevision(4, 2.5, 22), 4) == "acquis"
    assert (
        sm2.niveau_depuis_etat(sm2.EtatRevision(0, 2.5, 1), 1, niveau_actuel="acquis") == "en_cours"
    )
    assert sm2.niveau_depuis_etat(sm2.EtatRevision(0, 2.5, 1), 1) == "nouveau"
    assert sm2.niveau_depuis_etat(sm2.EtatRevision(1, 2.5, 1), 4) == "en_cours"


# --- Jour local (20.6) ----------------------------------------------------------------------


def test_jour_local_nuit():
    instant = datetime(2026, 10, 12, 23, 30, tzinfo=UTC)  # 01:30 le 13 à Paris
    assert jour_local(instant, "Europe/Paris", time(4, 0)) == date(2026, 10, 12)


def test_jour_local_ete():
    # Passage à l'heure d'hiver le 25 octobre 2026 : aucune dérive de date.
    avant = datetime(2026, 10, 24, 18, 0, tzinfo=UTC)
    apres = datetime(2026, 10, 25, 18, 0, tzinfo=UTC)
    assert jour_local(avant, "Europe/Paris", time(4, 0)) == date(2026, 10, 24)
    assert jour_local(apres, "Europe/Paris", time(4, 0)) == date(2026, 10, 25)
    assert date_prevue(date(2026, 10, 24), 1) == date(2026, 10, 25)


def test_jour_local_fuseau_objet():
    instant = datetime(2026, 10, 12, 2, 0, tzinfo=UTC)
    assert jour_local(instant, ZoneInfo("America/New_York"), time(4, 0)) == date(2026, 10, 11)


def test_borner_instant():
    maintenant = datetime(2026, 10, 12, 12, 0, tzinfo=UTC)
    dix_minutes = datetime(2026, 10, 12, 12, 10, tzinfo=UTC)
    assert borner_instant(dix_minutes, maintenant) == (dix_minutes, False)
    trente_heures = datetime(2026, 10, 13, 18, 0, tzinfo=UTC)
    borne, applique = borner_instant(trente_heures, maintenant)
    assert applique and borne == datetime(2026, 10, 13, 12, 0, tzinfo=UTC)
    trois_jours = datetime(2026, 10, 9, 12, 0, tzinfo=UTC)
    plancher = datetime(2026, 10, 1, tzinfo=UTC)
    assert borner_instant(trois_jours, maintenant, plancher) == (trois_jours, False)


# --- Normalisation (B.5, ALG-01) -----------------------------------------------------------


@pytest.mark.parametrize(
    ("saisie", "attendu"),
    [
        ("Lowkey", "lowkey"),
        ("Ain’t", "ain't"),
        ('"break up"', "break up"),
        ("Well-known!", "well-known"),
        ("GONNA", "gonna"),
    ],
)
def test_normaliser_cinq_exemples(saisie, attendu):
    assert normaliser(saisie) == attendu


@pytest.mark.parametrize(
    ("saisie", "attendu"),
    [
        ("Rock 'n' Roll", "rock 'n' roll"),
        ("Y’all", "y'all"),
        ("(Ride or die)", "ride or die"),
        ("Ça va", "ça va"),
        ("Ça va", "ça va"),
    ],
)
def test_normaliser_supplementaires(saisie, attendu):
    assert normaliser(saisie) == attendu


@pytest.mark.parametrize("saisie", ["!!!", "a" * 101, "a b c d e f g", "2024", "   ", "🔥🔥"])
def test_valider_refus(saisie):
    with pytest.raises(TermeInvalide):
        valider_terme(saisie)


def test_valider_accepte():
    assert valider_terme("  Break   UP ") == "break up"
    assert valider_terme("a b c d e f") == "a b c d e f"


# --- Détection et découpe (41.2) ------------------------------------------------------------


def test_trouver_frontiere():
    assert trouver_occurrence(["I love my heart"], "art", False) is None
    assert trouver_occurrence(["Let's party tonight"], "art", False) is None


def test_trouver_apostrophe():
    occ = trouver_occurrence(["I ain’t sorry"], "ain't", False)
    assert occ == Occurrence(0, 2, 7)


def test_trouver_casse_accent():
    occ = trouver_occurrence(["CAFÉ au lait"], "cafe", False)
    assert occ == Occurrence(0, 0, 4)


def test_trouver_expression():
    occ = trouver_occurrence(["We might break up soon"], "break up", False)
    assert occ is not None and "We might break up soon"[occ.debut : occ.fin] == "break up"


def test_trouver_variante():
    ligne = "He was running"
    assert trouver_occurrence([ligne], "run", False) is None
    occ = trouver_occurrence([ligne], "run", True)
    assert occ is not None and ligne[occ.debut : occ.fin] == "running"


def test_trouver_contraction():
    ligne = "I'm going to tell you"
    occ = trouver_occurrence([ligne], "gonna", True)
    assert occ is not None and ligne[occ.debut : occ.fin] == "going to"


def test_apostrophe_interne_non_frontiere():
    assert trouver_occurrence(["y'all ready"], "all", False) is None


def test_extrait_deux_lignes():
    lignes = ["a" * 30 + " lowkey " + "b" * 2, "c" * 40, "d" * 40]
    occ = trouver_occurrence(lignes, "lowkey", False)
    extrait = construire_extrait(lignes, occ)
    assert extrait.texte.count("\n") == 1
    assert extrait.texte[extrait.debut : extrait.fin] == "lowkey"


def test_extrait_derniere_ligne_prend_la_precedente():
    lignes = ["first line here", "then lowkey here"]
    extrait = construire_extrait(lignes, trouver_occurrence(lignes, "lowkey", False))
    assert extrait.texte == "first line here\nthen lowkey here"
    assert extrait.texte[extrait.debut : extrait.fin] == "lowkey"


def test_extrait_ligne_longue():
    ligne = " ".join(["word"] * 50) + " lowkey " + " ".join(["more"] * 50)
    extrait = construire_extrait([ligne], trouver_occurrence([ligne], "lowkey", False))
    assert len(extrait.texte) <= 240
    assert extrait.texte.startswith("…") and extrait.texte.endswith("…")
    assert extrait.texte[extrait.debut : extrait.fin] == "lowkey"
    assert " wor…" not in extrait.texte  # coupe aux frontières de mots


def test_extrait_deux_lignes_trop_longues():
    lignes = ["x " * 70 + "lowkey", "y " * 80]
    extrait = construire_extrait(lignes, trouver_occurrence(lignes, "lowkey", False))
    assert "\n" not in extrait.texte and len(extrait.texte) <= 240


def test_extrait_licence():
    texte = (
        "I lowkey miss you\nBut I'm never saying that\n...\n"
        "******* This Lyrics is NOT for Commercial use *******\n(1409617729462)"
    )
    assert nettoyer_lignes(texte) == ["I lowkey miss you", "But I'm never saying that"]
    extrait = extraire(texte, "lowkey")
    assert extrait.texte == "I lowkey miss you\nBut I'm never saying that"
    assert (extrait.debut, extrait.fin) == (2, 8)


def test_extrait_mot_absent_apres_licence():
    texte = "Nothing here\n******* This Lyrics is NOT for Commercial use lowkey *******"
    assert extraire(texte, "lowkey") is None


def test_occurrence_la_plus_lisible():
    lignes = ["lowkey " + "z " * 120, "short", "we lowkey vibe", "ok then"]
    occ = trouver_occurrence(lignes, "lowkey", False)
    assert occ.ligne == 2


def test_masquer():
    assert masquer_mot("I lowkey miss you", 2, 8) == "I ______ miss you"


# --- Repli par mots-clés (IA-19) ------------------------------------------------------------


def test_repli_seuils():
    reference = "I am lowkey happy to see you"
    assert verdict_par_mots_cles(reference, "I'm lowkey happy to see you, I am") == "correct"
    assert verdict_par_mots_cles(reference, "lowkey happy you") == "proche"
    assert verdict_par_mots_cles(reference, "bonjour le monde") == "incorrect"
    assert (
        verdict_par_mots_cles(
            "one two three four five six seven eight nine ten", "one two three four five six seven"
        )
        == "correct"
    )
    assert (
        verdict_par_mots_cles(
            "one two three four five six seven eight nine ten", "one two three four"
        )
        == "proche"
    )
    assert (
        verdict_par_mots_cles("one two three four five six seven eight nine ten", "one two three")
        == "incorrect"
    )


# --- Résilience (20.4, QUO-06) --------------------------------------------------------------


def test_reessai_erreurs_temporaires():
    attentes: list[float] = []
    essais = {"n": 0}

    async def dormir(s: float) -> None:
        attentes.append(s)

    async def fonction() -> str:
        essais["n"] += 1
        if essais["n"] < 3:
            raise ErreurTemporaire("503", 503)
        return "ok"

    assert asyncio.run(avec_reessai(fonction, dormir=dormir)) == "ok"
    assert attentes == [1, 2]


def test_reessai_erreur_definitive_non_rejouee():
    essais = {"n": 0}

    async def dormir(_: float) -> None:
        return None

    async def fonction() -> str:
        essais["n"] += 1
        raise httpx.HTTPStatusError(
            "400", request=httpx.Request("GET", "http://x"), response=httpx.Response(400)
        )

    with pytest.raises(httpx.HTTPStatusError):
        asyncio.run(avec_reessai(fonction, dormir=dormir))
    assert essais["n"] == 1


def test_disjoncteur():
    instant = {"t": 0.0}
    disjoncteur = Disjoncteur("deepl", 5, 5, horloge=lambda: instant["t"])
    for _ in range(4):
        disjoncteur.enregistrer_echec()
    assert disjoncteur.autoriser()
    disjoncteur.enregistrer_echec()
    assert not disjoncteur.autoriser()
    instant["t"] = 299
    assert not disjoncteur.autoriser()
    instant["t"] = 300
    assert disjoncteur.autoriser()
