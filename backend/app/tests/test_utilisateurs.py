"""Plusieurs utilisateurs : une base par compte Tailscale (app/core/locataires.py)."""

import uuid

import pytest
from fastapi.testclient import TestClient

from app.main import creer_app

PROPRIETAIRE = "proprietaire@exemple.com"
AMI = "ami@exemple.com"
AMIE = "amie@exemple.com"


@pytest.fixture
def client_multi(parametres, services, base_vide):
    parametres.proprietaire_login = PROPRIETAIRE
    app = creer_app(parametres, services, demarrer_taches=False)
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client
        app.state.locataires.fermer_bases_de_test()


def _ajouter(client, terme: str, login: str | None) -> None:
    entetes = {"Tailscale-User-Login": login} if login else {}
    reponse = client.post(
        "/api/mots", json={"id": str(uuid.uuid4()), "terme": terme}, headers=entetes
    )
    assert reponse.status_code in (200, 201), reponse.text


def _termes(client, login: str | None) -> list[str]:
    entetes = {"Tailscale-User-Login": login} if login else {}
    return sorted(m["terme"] for m in client.get("/api/mots", headers=entetes).json()["items"])


def test_chaque_compte_a_sa_bibliotheque(client_multi):
    _ajouter(client_multi, "lowkey", PROPRIETAIRE)
    _ajouter(client_multi, "vibe", AMI)
    _ajouter(client_multi, "craft", AMIE)
    _ajouter(client_multi, "flaw", None)  # requête locale (scripts) : base du propriétaire
    assert _termes(client_multi, PROPRIETAIRE) == ["flaw", "lowkey"]
    assert _termes(client_multi, AMI) == ["vibe"]
    assert _termes(client_multi, AMIE.upper()) == ["craft"]  # comptes sans casse


def test_reglages_et_synchronisation_separes(client_multi):
    entetes_ami = {"Tailscale-User-Login": AMI}
    reglages = client_multi.get("/api/reglages", headers=entetes_ami).json()
    nouveaux = {**reglages, "mots_par_session": 7}
    assert client_multi.put("/api/reglages", json=nouveaux, headers=entetes_ami).status_code == 204
    assert client_multi.get("/api/reglages").json()["mots_par_session"] == 20
    _ajouter(client_multi, "vibe", AMI)
    tirage = client_multi.get("/api/sync/pull?since=0", headers=entetes_ami).json()
    assert [m["terme"] for m in tirage["changements"]["mots"]] == ["vibe"]
    proprietaire = client_multi.get("/api/sync/pull?since=0").json()
    assert proprietaire["changements"]["mots"] == []


def test_sans_proprietaire_un_seul_utilisateur(client):
    _ajouter(client, "lowkey", AMI)
    assert _termes(client, None) == ["lowkey"]  # mode d'origine : une seule base


def test_tunnel_code_d_invitation_obligatoire(parametres, services, base_vide, tmp_path):
    import json

    from app.core.codes_acces import empreinte

    fichier = tmp_path / "codes.json"
    fichier.write_text(
        json.dumps(
            {empreinte("LV-AAAA-BBBB"): "invite:mangala", empreinte("LV-MOI1-MOI2"): PROPRIETAIRE}
        ),
        encoding="utf-8",
    )
    parametres.proprietaire_login = PROPRIETAIRE
    parametres.codes_acces_fichier = str(fichier)
    app = creer_app(parametres, services, demarrer_taches=False)
    tunnel = {"Cf-Ray": "abc-LHR"}
    with TestClient(app, raise_server_exceptions=False) as client:
        try:
            assert client.get("/api/health", headers=tunnel).status_code == 200
            refuse = client.get("/api/mots", headers=tunnel)
            assert refuse.status_code == 401 and refuse.json()["code"] == "code_acces_requis"
            # L'en-tête Tailscale traverse le tunnel tel quel : il est ignoré.
            usurpe = client.get(
                "/api/mots", headers={**tunnel, "Tailscale-User-Login": PROPRIETAIRE}
            )
            assert usurpe.status_code == 401
            faux = client.get("/api/mots", headers={**tunnel, "X-Code-Acces": "LV-ZZZZ-ZZZZ"})
            assert faux.status_code == 401
            mangala = {**tunnel, "X-Code-Acces": "lv-aaaa-bbbb"}  # casse indifférente
            _ajouter_avec(client, "vibe", mangala)
            assert _termes_avec(client, mangala) == ["vibe"]
            assert _termes(client, None) == []  # la bibliothèque du propriétaire n'a pas bougé
            moi = {**tunnel, "X-Code-Acces": "LV-MOI1-MOI2"}
            _ajouter_avec(client, "lowkey", moi)
            assert _termes(client, None) == ["lowkey"]
            bases = [loc.base for loc in app.state.locataires.tous()]
            assert len(bases) == 2  # propriétaire + Mangala ; aucune base « anonyme »
        finally:
            app.state.locataires.fermer_bases_de_test()


def _ajouter_avec(client, terme: str, entetes: dict) -> None:
    reponse = client.post(
        "/api/mots", json={"id": str(uuid.uuid4()), "terme": terme}, headers=entetes
    )
    assert reponse.status_code in (200, 201), reponse.text


def _termes_avec(client, entetes: dict) -> list[str]:
    return sorted(m["terme"] for m in client.get("/api/mots", headers=entetes).json()["items"])
