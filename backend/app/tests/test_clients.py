"""Clients externes avec réponses HTTP simulées (DT-02) et quotas persistants (D.8)."""

import asyncio
import json
import logging

import httpx
import pytest

from app.core.errors import IaIndisponible, QuotaDepasse, ServiceIndisponible
from app.core.logging import configurer_journaux
from app.core.resilience import Disjoncteur
from app.services.deepl_client import DeeplClient
from app.services.genius_client import GeniusClient
from app.services.musixmatch_client import MusixmatchClient
from app.services.ollama_client import OllamaClient
from app.services.quotas import CompteurQuotas
from app.tests.doubles import CompteurMemoire


async def _sans_pause(_: float) -> None:
    return None


def _http(gestionnaire) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(gestionnaire))


def _enveloppe(corps: dict, statut: int = 200) -> httpx.Response:
    return httpx.Response(200, json={"message": {"header": {"status_code": statut}, "body": corps}})


def _musixmatch(gestionnaire, compteur=None, disjoncteur=None) -> MusixmatchClient:
    return MusixmatchClient(
        "cle-mxm-secrete",
        _http(gestionnaire),
        compteur or CompteurMemoire(),
        disjoncteur or Disjoncteur("musixmatch", 5, 5),
        dormir=_sans_pause,
    )


def test_musixmatch_succes_et_texte():
    def repondre(requete: httpx.Request) -> httpx.Response:
        assert requete.url.params["apikey"] == "cle-mxm-secrete"
        if "track.search" in requete.url.path:
            return _enveloppe(
                {
                    "track_list": [
                        {
                            "track": {
                                "track_id": 7,
                                "track_name": "Titre",
                                "artist_name": "A",
                                "artist_id": 3,
                                "has_lyrics": 1,
                            }
                        }
                    ]
                }
            )
        return _enveloppe(
            {"lyrics": {"lyrics_body": "I lowkey miss you\n...\n*** NOT for " "Commercial use ***"}}
        )

    client = _musixmatch(repondre)
    morceaux = asyncio.run(client.lister_morceaux(3, 25))
    assert morceaux[0].musixmatch_track_id == 7 and morceaux[0].titre == "Titre"
    assert "lowkey" in asyncio.run(client.obtenir_texte(7))


def test_musixmatch_404_et_vide():
    client = _musixmatch(lambda r: _enveloppe({}, 404))
    assert asyncio.run(client.obtenir_texte(1)) is None
    assert asyncio.run(client.rechercher_morceaux_par_texte("x", 10)) == []


def test_musixmatch_quota_et_refus():
    with pytest.raises(QuotaDepasse):
        asyncio.run(_musixmatch(lambda r: _enveloppe({}, 402)).obtenir_texte(1))
    with pytest.raises(ServiceIndisponible) as erreur:
        asyncio.run(_musixmatch(lambda r: httpx.Response(401)).obtenir_texte(1))
    assert erreur.value.details["code"] == "musixmatch_indisponible"


def test_musixmatch_5xx_reessai_puis_indisponible():
    appels = {"n": 0}

    def repondre(_: httpx.Request) -> httpx.Response:
        appels["n"] += 1
        return httpx.Response(503)

    compteur = CompteurMemoire()
    with pytest.raises(ServiceIndisponible):
        asyncio.run(_musixmatch(repondre, compteur).obtenir_texte(1))
    assert appels["n"] == 3 and compteur.appels["musixmatch"] == 3


def test_delai_depasse_et_json_invalide():
    def delai(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("lent")

    with pytest.raises(ServiceIndisponible):
        asyncio.run(_musixmatch(delai).obtenir_texte(1))
    with pytest.raises(ServiceIndisponible):
        asyncio.run(_musixmatch(lambda r: httpx.Response(200, text="pas du json")).obtenir_texte(1))


def test_disjoncteur_ouvert_bloque_les_appels():
    appels = {"n": 0}

    def repondre(_: httpx.Request) -> httpx.Response:
        appels["n"] += 1
        return httpx.Response(401)

    disjoncteur = Disjoncteur("musixmatch", 5, 5)
    client = _musixmatch(repondre, disjoncteur=disjoncteur)
    for _ in range(6):
        with pytest.raises(ServiceIndisponible):
            asyncio.run(client.obtenir_texte(1))
    assert appels["n"] == 5 and not disjoncteur.autoriser()


def test_genius_recherche_dedoublonnee():
    def repondre(requete: httpx.Request) -> httpx.Response:
        assert requete.headers["authorization"] == "Bearer jeton"
        hits = [
            {"result": {"primary_artist": {"id": 1, "name": "Drake", "image_url": "u1"}}},
            {"result": {"primary_artist": {"id": 1, "name": "Drake", "image_url": "u1"}}},
            {
                "result": {
                    "primary_artist": {
                        "id": 2,
                        "name": "Drake Bell",
                        "image_url": "https://x/default_avatar.png",
                    }
                }
            },
        ]
        return httpx.Response(200, json={"response": {"hits": hits}})

    client = GeniusClient(
        "jeton", _http(repondre), CompteurMemoire(), Disjoncteur("g", 5, 5), dormir=_sans_pause
    )
    artistes = asyncio.run(client.rechercher_artistes("drake"))
    assert [(a.nom, a.genius_id, a.image_url) for a in artistes] == [
        ("Drake", 1, "u1"),
        ("Drake Bell", 2, None),
    ]


def test_deepl_traduction_contexte_et_quota():
    corps_recus = []

    def repondre(requete: httpx.Request) -> httpx.Response:
        corps_recus.append(json.loads(requete.content))
        assert requete.headers["authorization"] == "DeepL-Auth-Key cle:fx"
        return httpx.Response(200, json={"translations": [{"text": "discrètement"}]})

    compteur = CompteurMemoire()
    client = DeeplClient(
        "cle:fx", _http(repondre), compteur, Disjoncteur("d", 5, 5), dormir=_sans_pause
    )
    assert client.adresse.startswith("https://api-free.deepl.com")
    assert asyncio.run(client.traduire("lowkey", "I lowkey miss you")) == "discrètement"
    assert corps_recus[0]["context"] == "I lowkey miss you"
    assert corps_recus[0]["source_lang"] == "EN" and corps_recus[0]["target_lang"] == "FR"
    quota = DeeplClient(
        "cle:fx",
        _http(lambda r: httpx.Response(456)),
        compteur,
        Disjoncteur("d", 5, 5),
        dormir=_sans_pause,
    )
    with pytest.raises(QuotaDepasse):
        asyncio.run(quota.traduire("x"))
    vide = DeeplClient(
        "cle:fx",
        _http(lambda r: httpx.Response(200, json={"translations": [{"text": " "}]})),
        compteur,
        Disjoncteur("d", 5, 5),
        dormir=_sans_pause,
    )
    assert asyncio.run(vide.traduire("x")) is None


def test_deepl_429_rejoue():
    reponses = [httpx.Response(429), httpx.Response(200, json={"translations": [{"text": "ok"}]})]
    client = DeeplClient(
        "cle:fx",
        _http(lambda r: reponses.pop(0)),
        CompteurMemoire(),
        Disjoncteur("d", 5, 5),
        dormir=_sans_pause,
    )
    assert asyncio.run(client.traduire("x")) == "ok"


def test_ollama_generation_et_sante():
    def repondre(requete: httpx.Request) -> httpx.Response:
        if requete.url.path == "/api/tags":
            return httpx.Response(200, json={"models": []})
        corps = json.loads(requete.content)
        assert corps["stream"] is False and corps["options"]["temperature"] == 0.2
        assert corps["options"]["num_predict"] == 150 and corps["keep_alive"]
        return httpx.Response(200, json={"response": " Bonjour "})

    client = OllamaClient(
        _http(repondre), "http://127.0.0.1:11434", "llama3.1:8b", CompteurMemoire()
    )
    assert asyncio.run(client.generer("p")) == "Bonjour"
    assert asyncio.run(client.disponible()) is True and client.etat_en_cache() is True


def test_ollama_panne():
    def repondre(_: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("refusé")

    client = OllamaClient(_http(repondre), "http://127.0.0.1:11434", "m", CompteurMemoire())
    with pytest.raises(IaIndisponible):
        asyncio.run(client.generer("p"))
    assert asyncio.run(client.disponible()) is False


def test_quotas_80_puis_100(fabrique, parametres, tmp_path):
    """MAT-T09 : alerte à 80 %, puis appels suspendus et 429 à 100 %."""
    configurer_journaux(tmp_path, 10, 14)
    parametres.quota_musixmatch_jour = 10
    compteur = CompteurQuotas(fabrique, parametres)
    for _ in range(8):
        compteur.verifier("musixmatch")
        compteur.incrementer("musixmatch")
    journal = (tmp_path / "backend.jsonl").read_text(encoding="utf-8")
    assert '"quota_alerte"' in journal
    etat = {e["api"]: e for e in compteur.etat()["apis"]}
    assert etat["musixmatch"]["alerte"] and etat["musixmatch"]["nb"] == 8
    compteur.incrementer("musixmatch")
    compteur.incrementer("musixmatch")
    with pytest.raises(QuotaDepasse):
        compteur.verifier("musixmatch")
    compteur.incrementer("deepl", caracteres=1000)
    etat = {e["api"]: e for e in compteur.etat()["apis"]}
    assert etat["deepl"]["caracteres_mois"] == 1000
    parametres.quota_deepl_mois = 1000
    with pytest.raises(QuotaDepasse):
        compteur.verifier("deepl", caracteres=10)
    logging.getLogger("lyrics_vocab").handlers.clear()
