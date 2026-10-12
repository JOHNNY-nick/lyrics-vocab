"""Synchronisation serveur (41.5, SYN-T07 à SYN-T10)."""

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from app.tests.conftest import nouvel_id

APPAREIL = "android-7f3a"


def _push(client, operations, **entetes):
    reponse = client.post(
        "/api/sync/push", json={"appareil_id": APPAREIL, "operations": operations}, headers=entetes
    )
    assert reponse.status_code == 200, reponse.text
    return reponse.json()["resultats"]


def _op(type_op, **donnees):
    return {"op_id": nouvel_id(), "type": type_op, "donnees": donnees}


def _iso(instant: datetime) -> str:
    return instant.astimezone(UTC).isoformat().replace("+00:00", "Z")


def test_push_idempotent(client):
    """SYN-T07 : même lot deux fois : un seul effet."""
    lot = [_op("mot.creer", id=nouvel_id(), terme="lowkey", cree_le=_iso(datetime.now(UTC)))]
    assert _push(client, lot)[0]["statut"] == "applique"
    second = _push(client, lot)
    assert second[0]["statut"] == "deja_applique"
    assert client.get("/api/mots").json()["total"] == 1


def test_push_partiel(client):
    lot = [
        _op("mot.creer", id=nouvel_id(), terme="vibe"),
        _op("inconnu.faire"),
        _op("mot.creer", id=nouvel_id(), terme="gonna"),
    ]
    resultats = _push(client, lot)
    assert [r["statut"] for r in resultats] == ["applique", "rejete", "applique"]
    assert resultats[1]["code"] == "operation_inconnue"
    rejeu = _push(client, [lot[1]])
    assert rejeu[0]["statut"] == "rejete" and rejeu[0]["code"] == "operation_inconnue"  # SYN-30


def test_push_lot_trop_grand(client):
    lot = [_op("mot.supprimer", id=nouvel_id()) for _ in range(51)]
    reponse = client.post("/api/sync/push", json={"appareil_id": APPAREIL, "operations": lot})
    assert reponse.status_code == 422


def test_push_ordre_reponses(client):
    """Trois réponses du même mot, dans le désordre : rejouées par repondu_le."""
    mot_id, r1, r2, r3, r4 = (nouvel_id() for _ in range(5))
    maintenant = datetime.now(UTC)
    _push(client, [_op("mot.creer", id=mot_id, terme="lowkey", revision_id=r1)])
    reponses = [
        _op(
            "revision.repondre",
            revision_id=r3,
            mot_id=mot_id,
            qualite=4,
            repondu_le=_iso(maintenant - timedelta(minutes=1)),
            nouvelle_revision_id=r4,
        ),
        _op(
            "revision.repondre",
            revision_id=r1,
            mot_id=mot_id,
            qualite=4,
            repondu_le=_iso(maintenant - timedelta(minutes=3)),
            nouvelle_revision_id=r2,
        ),
        _op(
            "revision.repondre",
            revision_id=r2,
            mot_id=mot_id,
            qualite=4,
            repondu_le=_iso(maintenant - timedelta(minutes=2)),
            nouvelle_revision_id=r3,
        ),
    ]
    resultats = _push(client, reponses)
    assert all(r["statut"] == "applique" for r in resultats), resultats
    assert resultats[0]["donnees"]["repetitions"] == 3
    assert resultats[0]["donnees"]["intervalle_jours"] == 8
    detail = client.get(f"/api/mots/{mot_id}").json()
    assert detail["niveau"] == "en_cours"


def test_push_interruption(client):
    """SYN-T08 : accusé perdu, rejeu : deja_applique, aucun doublon."""
    mot_id, r1 = nouvel_id(), nouvel_id()
    _push(client, [_op("mot.creer", id=mot_id, terme="ain't", revision_id=r1)])
    reponse = _op(
        "revision.repondre", revision_id=r1, qualite=4, repondu_le=_iso(datetime.now(UTC))
    )
    _push(client, [reponse])
    assert _push(client, [reponse])[0]["statut"] == "deja_applique"
    pull = client.get("/api/sync/pull", params={"since": 0}).json()
    faites = [r for r in pull["changements"]["revisions"] if r["statut"] == "faite"]
    assert len(faites) == 1


def test_pull_curseur(client, base_vide):
    """450 changements, limite 200 : 3 appels, aucun manqué ni répété."""
    with base_vide.begin() as connexion:
        connexion.execute(
            text(
                "INSERT INTO mot (id, terme, terme_normalise) SELECT gen_random_uuid(), 'w' || g, "
                "'w' || g FROM generate_series(1, 450) g"
            )
        )
    curseur, vus, suites = 0, [], []
    while True:
        page = client.get("/api/sync/pull", params={"since": curseur, "limite": 200}).json()
        vus.extend(m["id"] for m in page["changements"]["mots"])
        suites.append(page["a_suite"])
        curseur = page["curseur"]
        if not page["a_suite"]:
            break
    assert suites == [True, True, False]
    assert len(vus) == 450 and len(set(vus)) == 450


def test_pull_plusieurs_tables(client, creer_mot):
    for terme in ("a1", "b1", "c1"):
        creer_mot(terme)
    page = client.get("/api/sync/pull", params={"since": 0, "limite": 2}).json()
    vus = {("mots", m["id"]) for m in page["changements"]["mots"]} | {
        ("revisions", r["id"]) for r in page["changements"]["revisions"]
    }
    curseur = page["curseur"]
    while page["a_suite"]:
        page = client.get("/api/sync/pull", params={"since": curseur, "limite": 2}).json()
        curseur = page["curseur"]
        vus |= {("mots", m["id"]) for m in page["changements"]["mots"]}
        vus |= {("revisions", r["id"]) for r in page["changements"]["revisions"]}
    assert len([v for v in vus if v[0] == "mots"]) == 3
    assert len([v for v in vus if v[0] == "revisions"]) == 3
    assert any(r["id"] for r in client.get("/api/sync/pull").json()["changements"]["reglages"])


def test_pull_suppression(client, creer_mot):
    mot = creer_mot("lowkey")
    curseur = client.get("/api/sync/pull").json()["curseur"]
    client.delete(f"/api/mots/{mot['id']}")
    page = client.get("/api/sync/pull", params={"since": curseur}).json()
    assert page["changements"]["mots"][0]["deleted_at"] is not None
    assert "server_seq" in page["changements"]["mots"][0]


def test_pull_curseur_invalide(client):
    reponse = client.get("/api/sync/pull", params={"since": 10**9})
    assert reponse.status_code == 400 and reponse.json()["code"] == "curseur_invalide"


def test_fusion_doublon(client, creer_mot):
    """SYN-T09 / CL-07 : même mot créé sur PC et téléphone : fusion ; réponses rattachées."""
    existant = creer_mot("lowkey")
    local_id, local_revision = nouvel_id(), nouvel_id()
    resultats = _push(
        client,
        [
            _op("mot.creer", id=local_id, terme="Lowkey", revision_id=local_revision),
            _op(
                "revision.repondre",
                revision_id=local_revision,
                mot_id=local_id,
                qualite=4,
                repondu_le=_iso(datetime.now(UTC)),
            ),
        ],
    )
    assert resultats[0]["donnees"]["mot_id"] == existant["id"]
    assert resultats[0]["donnees"]["fusion"] is True
    assert resultats[1]["statut"] == "applique"
    assert client.get("/api/mots").json()["total"] == 1
    assert client.get(f"/api/mots/{existant['id']}").json()["niveau"] == "en_cours"


def test_suppression_l_emporte(client, creer_mot):
    """SYN-T10 : mot supprimé sur PC, révisé sur téléphone : la réponse est rejetée."""
    mot = creer_mot("gonna")
    revision_id = client.get("/api/revisions/dues").json()["items"][0]["id"]
    client.delete(f"/api/mots/{mot['id']}")
    resultat = _push(
        client,
        [
            _op(
                "revision.repondre",
                revision_id=revision_id,
                mot_id=mot["id"],
                qualite=4,
                repondu_le=_iso(datetime.now(UTC)),
            )
        ],
    )
    assert resultat[0]["statut"] == "rejete" and resultat[0]["code"] == "revision_introuvable"
    supprime = _push(client, [_op("mot.supprimer", id=str(uuid.uuid4()))])
    assert supprime[0]["statut"] == "applique"  # API-37


def test_horloge_decalee(client, base_vide):
    """Réponse avancée de 10 minutes acceptée ; de 30 heures bornée et journalisée."""
    mot_a, ra, mot_b, rb = (nouvel_id() for _ in range(4))
    _push(
        client,
        [
            _op("mot.creer", id=mot_a, terme="vibe", revision_id=ra),
            _op("mot.creer", id=mot_b, terme="slay", revision_id=rb),
        ],
    )
    maintenant = datetime.now(UTC)
    _push(
        client,
        [
            _op(
                "revision.repondre",
                revision_id=ra,
                qualite=4,
                repondu_le=_iso(maintenant + timedelta(minutes=10)),
            ),
            _op(
                "revision.repondre",
                revision_id=rb,
                qualite=4,
                repondu_le=_iso(maintenant + timedelta(hours=30)),
            ),
        ],
    )
    with base_vide.connect() as connexion:
        lignes = dict(
            connexion.execute(
                text("SELECT id::text, repondu_le FROM revision WHERE statut='faite'")
            ).all()
        )
    assert abs(lignes[ra] - (maintenant + timedelta(minutes=10))) < timedelta(seconds=1)
    assert lignes[rb] <= maintenant + timedelta(hours=24, seconds=5)


def test_reglages_et_artistes_par_sync(client):
    _push(
        client,
        [
            _op("reglage.modifier", mots_par_session=30, heure_rappel="08:15"),
            _op("artistes.modifier", artistes=[{"nom": "Adele"}]),
        ],
    )
    assert client.get("/api/reglages").json()["mots_par_session"] == 30
    assert client.get("/api/reglages").json()["heure_rappel"] == "08:15"
    assert client.get("/api/artistes-preferes").json()[0]["nom"] == "Adele"
    rejet = _push(client, [_op("reglage.modifier", mots_par_session=500)])
    assert rejet[0]["statut"] == "rejete"


def test_push_enrichit_les_mots_crees(client):
    """SYN-23 : un mot créé hors-ligne est enrichi à la réception."""
    mot_id = nouvel_id()
    _push(client, [_op("mot.creer", id=mot_id, terme="slay")])
    assert uuid.UUID(mot_id) in client.app.state.gestionnaire.en_attente
