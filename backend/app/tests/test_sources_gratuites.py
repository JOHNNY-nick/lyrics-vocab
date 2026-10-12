"""Sources gratuites sans clé : LRCLIB, Deezer et traduction par l'IA locale (DECISIONS.md)."""

import asyncio
import uuid
from datetime import date

import httpx

from app.core.resilience import Disjoncteur
from app.models import Extrait, Mot
from app.services import artistes, mots
from app.services.ai_traduction import nettoyer_traduction, traduire_par_ia
from app.services.deezer_client import DeezerClient
from app.services.enrichissement import enrichir
from app.services.lrclib_client import LrclibClient
from app.tests.doubles import CompteurMemoire, FauxOllama

PAROLES = "I lowkey miss you\nBut I'm never saying that\nNo no no"


async def _sans_pause(_: float) -> None:
    return None


def _http(gestionnaire) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(gestionnaire))


def _resultats_lrclib(requete: httpx.Request) -> httpx.Response:
    assert "LyricsVocab" in requete.headers["user-agent"]
    q = requete.url.params["q"]
    if q == "Adele":
        return httpx.Response(
            200,
            json=[
                {"id": 1, "trackName": "Hello", "artistName": "Adele", "plainLyrics": PAROLES},
                {"id": 2, "trackName": "Hello", "artistName": "Adele", "plainLyrics": PAROLES},
                {"id": 3, "trackName": "Intro", "artistName": "Adele", "instrumental": True},
                {"id": 4, "trackName": "Cover", "artistName": "Autre", "plainLyrics": PAROLES},
                {"id": 5, "trackName": "Skyfall", "artistName": "Adele", "plainLyrics": "x"},
            ],
        )
    return httpx.Response(
        200, json=[{"id": 9, "trackName": "Lowkey", "artistName": "B", "plainLyrics": PAROLES}]
    )


def _lrclib(gestionnaire=_resultats_lrclib, compteur=None) -> LrclibClient:
    return LrclibClient(
        _http(gestionnaire),
        compteur or CompteurMemoire(),
        Disjoncteur("lrclib", 5, 5),
        dormir=_sans_pause,
    )


def test_lrclib_morceaux_artiste():
    morceaux, identifiant = asyncio.run(_lrclib().morceaux_artiste("Adele", None, 25))
    assert identifiant is None
    assert [m.titre for m in morceaux] == ["Hello", "Skyfall"]  # doublon, instrumental, autre
    assert morceaux[0].texte == PAROLES
    assert asyncio.run(_lrclib().texte_de(morceaux[0])) == PAROLES


def test_lrclib_repli_et_panne():
    assert asyncio.run(_lrclib().rechercher_morceaux_par_texte("lowkey", 10))[0].titre == "Lowkey"
    client = _lrclib(lambda r: httpx.Response(503))
    try:
        asyncio.run(client.morceaux_artiste("Adele", None, 25))
        raise AssertionError("aurait dû échouer")
    except Exception as exc:
        assert getattr(exc, "code", "") == "service_indisponible"


def test_deezer_artistes():
    def repondre(requete: httpx.Request) -> httpx.Response:
        assert requete.url.path == "/search/artist"
        return httpx.Response(
            200,
            json={
                "data": [
                    {"id": 1, "name": "Drake", "nb_fan": 10, "picture_medium": "petit"},
                    {"id": 2, "name": "Drake Bell", "nb_fan": 500, "picture_medium": "b"},
                    {"id": 3, "name": "Drake", "nb_fan": 999, "picture_medium": "grand"},
                ]
            },
        )

    client = DeezerClient(
        _http(repondre), CompteurMemoire(), Disjoncteur("deezer", 5, 5), dormir=_sans_pause
    )
    resultats = asyncio.run(client.rechercher_artistes("drake"))
    assert [(a.nom, a.image_url) for a in resultats] == [("Drake", "grand"), ("Drake Bell", "b")]
    assert resultats[0].genius_id is None


def test_titre_sans_prefixe_et_casse():
    from app.services.ai_traduction import accorder_casse
    from app.services.lrclib_client import _sans_prefixe_artiste

    assert _sans_prefixe_artiste("Billie Eilish, Khalid - lovely", "Billie Eilish") == "lovely"
    assert _sans_prefixe_artiste("Hello - Live", "Adele") == "Hello - Live"
    assert accorder_casse("Cœur", "heart") == "cœur"
    assert accorder_casse("Londres", "London") == "Londres"
    assert accorder_casse("OK", "ok") == "OK"


def test_nettoyer_traduction():
    assert nettoyer_traduction("Traduction : « discrètement ; plutôt ».") == "discrètement ; plutôt"
    assert nettoyer_traduction("") is None
    assert nettoyer_traduction("mot " * 30) is None


def test_traduction_par_ia_avec_contexte():
    ollama = FauxOllama(CompteurMemoire(), reponses=['"discrètement"'])
    assert asyncio.run(traduire_par_ia(ollama, "lowkey", "I lowkey miss you")) == "discrètement"
    assert "I lowkey miss you" in ollama.prompts[0]


def test_enrichissement_sans_aucune_cle(fabrique, services):
    """Sans DeepL : la traduction vient de l'IA locale, l'explication aussi ; statut ok."""
    services.deepl.configure = False
    services.paroles = _lrclib(compteur=services.compteur)
    services.ollama.reponses = [
        "discrètement ; plutôt",
        "Argot : « lowkey » veut dire « un peu » ou « en secret ».",
    ]
    with fabrique() as session:
        artistes.remplacer_liste(session, [{"nom": "Adele"}])
        mot, _ = mots.creer_mot(session, uuid.uuid4(), "lowkey", date(2026, 10, 12))
        session.commit()
        mot_id = mot.id
    statut = asyncio.run(enrichir(services, mot_id))
    with fabrique() as session:
        mot = session.get(Mot, mot_id)
        extraits = session.query(Extrait).filter(Extrait.mot_id == mot_id).all()
        assert statut == "ok", (mot.erreur_enrichissement, mot.traduction_fr)
        assert mot.traduction_fr == "discrètement ; plutôt"
        assert extraits[0].texte == "I lowkey miss you\nBut I'm never saying that"
        assert extraits[0].hors_liste is False
    assert services.compteur.appels["lrclib"] == 1  # une seule recherche, paroles comprises
