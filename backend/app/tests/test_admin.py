"""Page /admin : réservée au propriétaire ; invitations, retraits, suppressions."""

import json
import uuid

import pytest
from fastapi.testclient import TestClient

from app.main import creer_app

PROPRIETAIRE = "proprietaire@exemple.com"
TUNNEL = {"Cf-Ray": "abc-LHR"}


@pytest.fixture
def admin(parametres, services, base_vide, tmp_path):
    parametres.proprietaire_login = PROPRIETAIRE
    parametres.codes_acces_fichier = str(tmp_path / "codes.json")
    parametres.registre_utilisateurs_fichier = str(tmp_path / "utilisateurs.json")
    app = creer_app(parametres, services, demarrer_taches=False)
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client, app
        app.state.locataires.fermer_bases_de_test()


def _ligne(client, nom: str) -> dict:
    lignes = client.get("/api/admin/utilisateurs").json()["utilisateurs"]
    return next(u for u in lignes if u["nom"] == nom)


def test_reservee_au_proprietaire(admin):
    client, _ = admin
    assert client.get("/admin").status_code == 200  # requête locale
    moi = {"Tailscale-User-Login": PROPRIETAIRE}
    assert client.get("/admin", headers=moi).status_code == 200
    ami = {"Tailscale-User-Login": "ami@exemple.com"}
    assert client.get("/admin", headers=ami).status_code == 403
    assert client.get("/admin", headers={**TUNNEL, **moi}).status_code == 403
    assert client.get("/api/admin/utilisateurs", headers=TUNNEL).status_code in (
        401,
        403,
    )
    reponse = client.post("/api/admin/invitations", json={"prenom": "Zoé"}, headers=ami)
    assert reponse.status_code == 403


def test_inviter_retirer_supprimer(admin):
    client, app = admin
    code = client.post("/api/admin/invitations", json={"prenom": "Sarah"}).json()["code"]
    sarah = _ligne(client, "Sarah")
    assert sarah["acces"] == "code" and not sarah["connecte"]

    # Sarah se connecte par le tunnel avec son code et ajoute un mot.
    entetes = {**TUNNEL, "X-Code-Acces": code}
    mot = {"id": str(uuid.uuid4()), "terme": "vibe"}
    assert client.post("/api/mots", json=mot, headers=entetes).status_code in (200, 201)
    sarah = _ligne(client, "Sarah")
    assert sarah["connecte"] and sarah["mots"] == 1
    fichier = app.state.parametres.registre_utilisateurs_fichier
    registre = json.loads(open(fichier, encoding="utf-8").read())
    assert "invite:sarah" in [v["compte"] for v in registre.values()]

    # Retrait : plus d'accès, données gardées.
    retrait = client.post("/api/admin/retraits", json={"compte": "invite:sarah"})
    assert retrait.json()["codes_retires"] == 1
    assert client.get("/api/mots", headers=entetes).status_code == 401
    sarah = _ligne(client, "Sarah")
    assert sarah["acces"] == "retire" and sarah["mots"] == 1

    # Suppression : confirmation exigée, puis bibliothèque effacée.
    faux = {"compte": "invite:sarah", "confirmation": "Sara"}
    assert client.post("/api/admin/suppressions", json=faux).status_code == 422
    juste = {"compte": "invite:sarah", "confirmation": "sarah"}
    assert client.post("/api/admin/suppressions", json=juste).status_code == 200
    noms = [u["nom"] for u in client.get("/api/admin/utilisateurs").json()["utilisateurs"]]
    assert noms == ["Toi"]
    soi = {"compte": PROPRIETAIRE, "confirmation": PROPRIETAIRE}
    assert client.post("/api/admin/suppressions", json=soi).status_code == 422
