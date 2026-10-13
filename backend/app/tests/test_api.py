"""Routes de l'API (C.5, 41.3) : au moins un test par route (API-T07)."""

import uuid
from datetime import date, timedelta

from sqlalchemy import text

from app.tests.conftest import nouvel_id
from app.tests.doubles import ArtisteExterne


def test_sante(client):
    corps = client.get("/api/health").json()
    assert corps["status"] == "ok" and corps["base"] == "ok"
    assert corps["version"] and "curseur" in corps and corps["heure_serveur"].endswith("Z")
    assert corps["alerte_sauvegarde"] is True  # aucune sauvegarde dans le dossier de test (SAV-T02)


def test_creer_mot_nominal(client, base_vide):
    identifiant = nouvel_id()
    reponse = client.post("/api/mots", json={"id": identifiant, "terme": "  Lowkey "})
    assert reponse.status_code == 201
    corps = reponse.json()
    assert corps["id"] == identifiant and corps["terme"] == "Lowkey"
    assert corps["terme_normalise"] == "lowkey" and corps["statut_enrichissement"] == "en_attente"
    assert corps["prochaine_revision"] is not None and corps["extraits"] == []
    assert corps["created_at"].endswith("Z")
    with base_vide.connect() as connexion:
        assert (
            connexion.execute(
                text("SELECT count(*) FROM revision WHERE statut='planifiee'")
            ).scalar()
            == 1
        )
    assert uuid.UUID(identifiant) in client.app.state.gestionnaire.en_attente


def test_creer_mot_doublon(client):
    """API-T02 : « Lowkey » puis « lowkey » : un seul mot."""
    premier = client.post("/api/mots", json={"id": nouvel_id(), "terme": "Lowkey"})
    second = client.post("/api/mots", json={"id": nouvel_id(), "terme": "lowkey"})
    assert premier.status_code == 201 and second.status_code == 200
    assert second.json()["id"] == premier.json()["id"]
    assert client.get("/api/mots").json()["total"] == 1


def test_creer_mot_recree(client, creer_mot):
    mot = creer_mot("vibe")
    assert client.delete(f"/api/mots/{mot['id']}").status_code == 204
    reponse = client.post("/api/mots", json={"id": nouvel_id(), "terme": "vibe"})
    assert reponse.status_code == 201 and reponse.json()["id"] != mot["id"]
    assert client.get(f"/api/mots/{mot['id']}").status_code == 404


def test_creer_mot_invalide(client):
    for terme in ("", "a b c d e f g", "2024", "!!!", "x" * 101):
        reponse = client.post("/api/mots", json={"id": nouvel_id(), "terme": terme})
        assert reponse.status_code == 422, terme
        corps = reponse.json()
        assert corps["code"] == "terme_invalide" and corps["message"]
        assert set(corps) == {"code", "message", "details"}


def test_corps_trop_grand(client):
    """API-T04 : un corps de 100 Ko est refusé."""
    reponse = client.post(
        "/api/mots",
        content=b'{"id":"x","terme":"' + b"a" * 100_000 + b'"}',
        headers={"content-type": "application/json"},
    )
    assert reponse.status_code == 413 and reponse.json()["code"] == "requete_trop_grande"


def test_liste_filtre_tri_recherche(client, creer_mot, base_vide):
    for terme in ("lowkey", "ain't", "break up", "gonna", "vibe", "café"):
        creer_mot(terme)
    with base_vide.begin() as connexion:
        connexion.execute(text("UPDATE mot SET niveau='acquis' WHERE terme_normalise='ain''t'"))
        connexion.execute(
            text("UPDATE mot SET traduction_fr='ambiance' WHERE terme_normalise='vibe'")
        )
    corps = client.get("/api/mots", params={"niveau": "acquis"}).json()
    assert [m["terme"] for m in corps["items"]] == ["ain't"]
    alpha = client.get("/api/mots", params={"tri": "alpha"}).json()["items"]
    assert [m["terme_normalise"] for m in alpha] == sorted(m["terme_normalise"] for m in alpha)
    assert client.get("/api/mots", params={"q": "AMBI"}).json()["items"][0]["terme"] == "vibe"
    assert client.get("/api/mots", params={"q": "cafe"}).json()["total"] == 1
    assert client.get("/api/mots", params={"tri": "inconnu"}).json()["code"] == "parametre_invalide"
    assert client.get("/api/mots", params={"tri": "prochaine_revision"}).status_code == 200


def test_liste_pagination(client, base_vide):
    with base_vide.begin() as connexion:
        connexion.execute(
            text(
                "INSERT INTO mot (id, terme, terme_normalise) SELECT gen_random_uuid(), 'w' || g, "
                "'w' || g FROM generate_series(1, 120) g"
            )
        )
    pages = [client.get("/api/mots", params={"page": p, "taille": 50}).json() for p in (1, 2, 3)]
    assert [len(p["items"]) for p in pages] == [50, 50, 20]
    assert all(p["total"] == 120 for p in pages)
    ids = {m["id"] for p in pages for m in p["items"]}
    assert len(ids) == 120


def test_detail_et_extraits(client, creer_mot, base_vide):
    mot = creer_mot("lowkey")
    with base_vide.begin() as connexion:
        a, m = uuid.uuid4(), uuid.uuid4()
        connexion.execute(text("INSERT INTO artiste (id, nom) VALUES (:a, 'Artiste A')"), {"a": a})
        connexion.execute(
            text("INSERT INTO morceau (id, artiste_id, titre) VALUES (:m, :a, 'Titre T')"),
            {"m": m, "a": a},
        )
        connexion.execute(
            text(
                "INSERT INTO extrait (id, mot_id, morceau_id, texte, surbrillance_debut, "
                "surbrillance_fin, hors_liste) VALUES (:e, :mot, :m, :t, 2, 8, true)"
            ),
            {
                "e": uuid.uuid4(),
                "mot": mot["id"],
                "m": m,
                "t": "I lowkey miss you\nBut I'm never saying that",
            },
        )
    detail = client.get(f"/api/mots/{mot['id']}").json()
    extrait = detail["extraits"][0]
    assert extrait["morceau"] == {"titre": "Titre T", "artiste": "Artiste A", "url_genius": None}
    assert extrait["hors_liste"] is True and (
        extrait["surbrillance_debut"],
        extrait["surbrillance_fin"],
    ) == (2, 8)
    assert client.get(f"/api/mots/{mot['id']}/extraits").json()[0]["texte"].startswith("I lowkey")
    assert client.get(f"/api/mots/{uuid.uuid4()}").json()["code"] == "mot_introuvable"


def test_supprimer_idempotent(client, creer_mot):
    mot = creer_mot("gonna")
    assert client.delete(f"/api/mots/{mot['id']}").status_code == 204
    assert client.delete(f"/api/mots/{mot['id']}").status_code == 204
    assert client.get("/api/mots").json()["total"] == 0


def test_rechercher_extraits(client, creer_mot, base_vide, compteur):
    mot = creer_mot("vibe")
    with base_vide.begin() as connexion:
        connexion.execute(
            text(
                "UPDATE mot SET statut_enrichissement='partiel', "
                "traduction_fr='ambiance' WHERE id=:id"
            ),
            {"id": mot["id"]},
        )
    client.app.state.gestionnaire.en_attente.clear()
    reponse = client.post(f"/api/mots/{mot['id']}/rechercher-extraits")
    assert reponse.status_code == 202
    assert reponse.json()["statut_enrichissement"] == "en_attente"
    compteur.limites["musixmatch"] = 0
    with base_vide.begin() as connexion:
        connexion.execute(
            text("UPDATE mot SET statut_enrichissement='partiel' WHERE id=:id"), {"id": mot["id"]}
        )
    client.app.state.gestionnaire.en_attente.clear()
    reponse = client.post(f"/api/mots/{mot['id']}/rechercher-extraits")
    assert reponse.status_code == 429 and reponse.json()["code"] == "quota_depasse"


def _repondre(client, revision_id, qualite=4, op_id=None, **extra):
    return client.post(
        f"/api/revisions/{revision_id}/reponse",
        json={"op_id": op_id or nouvel_id(), "qualite": qualite, **extra},
    )


def test_revisions_dues_et_reponse(client, creer_mot):
    mot = creer_mot("lowkey")
    dues = client.get("/api/revisions/dues").json()
    assert dues["total_dus"] == 1 and dues["items"][0]["mot_id"] == mot["id"]
    assert dues["items"][0]["indice"] is None and dues["items"][0]["terme"] == "lowkey"
    revision_id = dues["items"][0]["id"]
    op_id = nouvel_id()
    premiere = _repondre(client, revision_id, 4, op_id)
    assert premiere.status_code == 200
    corps = premiere.json()
    assert corps["statut"] == "applique" and corps["intervalle_jours"] == 1
    assert corps["repetitions"] == 1 and corps["niveau"] == "en_cours"
    # REV-T02 / API-T03 : même op_id, un seul calcul
    rejeu = _repondre(client, revision_id, 4, op_id).json()
    assert rejeu["statut"] == "deja_applique" and rejeu["prochaine_date"] == corps["prochaine_date"]
    # API-28 : autre op_id sur une révision faite
    conflit = _repondre(client, revision_id, 4)
    assert conflit.status_code == 409 and conflit.json()["code"] == "revision_deja_repondue"
    fin = client.get("/api/revisions/dues").json()
    assert fin.get("total_dus") == 0, fin


def test_reponse_ne_savais_pas(client, creer_mot):
    """REV-T06 : « Je ne savais pas » : le mot revient demain, nb_echecs + 1."""
    mot = creer_mot("ain't")
    revision_id = client.get("/api/revisions/dues").json()["items"][0]["id"]
    corps = _repondre(client, revision_id, 1).json()
    assert corps["intervalle_jours"] == 1
    detail = client.get(f"/api/mots/{mot['id']}").json()
    assert detail["nb_echecs"] == 1 and detail["niveau"] == "nouveau"
    demain = (
        date.fromisoformat(client.get("/api/revisions/dues").json()["jour"]) + timedelta(days=1)
    ).isoformat()
    assert client.get("/api/revisions/dues", params={"date": demain}).json()["total_dus"] == 1


def test_reponse_invalide(client, creer_mot):
    creer_mot("lowkey")
    revision_id = client.get("/api/revisions/dues").json()["items"][0]["id"]
    reponse = client.post(f"/api/revisions/{revision_id}/reponse", json={"op_id": nouvel_id()})
    assert reponse.status_code == 422 and reponse.json()["code"] == "reponse_invalide"
    reponse = client.post(
        f"/api/revisions/{revision_id}/reponse",
        json={"op_id": nouvel_id(), "qualite": 4, "repondu_le": "2026-10-12T08:00:00"},
    )
    assert reponse.status_code == 422  # SCH-02 : date sans fuseau refusée


def test_dues_tri_limite(client, base_vide):
    """30 révisions dues, mots_par_session 20 : 20 renvoyées, plus anciennes d'abord."""
    with base_vide.begin() as connexion:
        connexion.execute(
            text(
                """
            INSERT INTO mot (id, terme, terme_normalise)
            SELECT gen_random_uuid(), 'w' || g, 'w' || g FROM generate_series(1, 30) g;
            INSERT INTO revision (id, mot_id, date_prevue, statut, mode)
            SELECT gen_random_uuid(), id, DATE '2026-09-01' + (row_number() OVER ())::int,
                   'planifiee', 'rappel' FROM mot;
        """
            )
        )
    corps = client.get("/api/revisions/dues", params={"date": "2026-12-31"}).json()
    assert corps["total_dus"] == 30 and len(corps["items"]) == 20
    dates = [i["date_prevue"] for i in corps["items"]]
    assert dates == sorted(dates)


def test_dues_heure_changement_jour(client, creer_mot):
    """REV-T04 : X-Fuseau est pris en compte pour le jour local."""
    creer_mot("lowkey", **{"X-Fuseau": "Pacific/Kiritimati"})
    corps = client.get("/api/revisions/dues", headers={"X-Fuseau": "Pacific/Kiritimati"}).json()
    assert corps["total_dus"] == 1


def test_exercice_et_evaluation(client, creer_mot, base_vide, services):
    mot = creer_mot("lowkey")
    with base_vide.begin() as connexion:
        connexion.execute(
            text("UPDATE mot SET traduction_fr='discrètement ; plutôt' WHERE id=:i"),
            {"i": mot["id"]},
        )
    services.ollama.reponses = [
        '{"en": "I\'m lowkey happy to see you.", '
        '"fr": "Je suis discrètement content de te voir."}'
    ]
    exercice = client.post("/api/exercices", json={"mot_id": mot["id"]})
    assert exercice.status_code == 200, exercice.text
    corps = exercice.json()
    assert corps["phrase_fr"] == "Je suis discrètement content de te voir."
    services.ollama.reponses = [
        '```json\n{"verdict": "correct", "explication": "Bonne ' 'traduction."}\n```'
    ]
    evaluation = client.post(
        f"/api/exercices/{corps['id']}/evaluer", json={"reponse": "I am lowkey happy to see you."}
    ).json()
    assert evaluation == {
        "verdict": "correct",
        "explication": "Bonne traduction.",
        "verdict_repli": False,
        "reference_en": "I'm lowkey happy to see you.",
    }
    # Le mot de l'utilisateur est attendu dans la réponse : sans lui, au mieux « proche ».
    services.ollama.reponses = ['{"verdict": "correct", "explication": "Bien."}']
    sans_mot = client.post(
        f"/api/exercices/{corps['id']}/evaluer", json={"reponse": "I'm quietly happy to see you."}
    ).json()
    assert sans_mot["verdict"] == "proche" and "lowkey" in sans_mot["explication"]
    resultat = _repondre(client, corps["id"], None, verdict="correct")
    assert resultat.status_code == 200 and resultat.json()["repetitions"] == 1
    trop_long = client.post(f"/api/exercices/{corps['id']}/evaluer", json={"reponse": "x" * 301})
    assert trop_long.status_code == 422


def test_exercice_ia_indisponible(client, creer_mot, base_vide, services):
    mot = creer_mot("lowkey")
    with base_vide.begin() as connexion:
        connexion.execute(
            text("UPDATE mot SET traduction_fr='discrètement' WHERE id=:i"), {"i": mot["id"]}
        )
    services.ollama.panne = True
    reponse = client.post("/api/exercices", json={"mot_id": mot["id"]})
    assert reponse.status_code == 503 and reponse.json()["code"] == "ia_indisponible"


def test_artistes(client, services):
    services.genius.artistes = [
        ArtisteExterne("Drake", 130, None, "https://img/drake.jpg"),
        ArtisteExterne("Drake Bell", 131, None, None),
    ]
    resultats = client.get("/api/artistes/recherche", params={"q": "drak"}).json()
    assert [r["nom"] for r in resultats] == ["Drake", "Drake Bell"]
    appels = services.compteur.appels["genius"]
    client.get("/api/artistes/recherche", params={"q": "drak"})
    assert services.compteur.appels["genius"] == appels  # cache 24 h
    assert client.get("/api/artistes/recherche", params={"q": "d"}).status_code == 422
    services.genius.panne = True
    panne = client.get("/api/artistes/recherche", params={"q": "zzz"})
    assert panne.status_code == 503 and panne.json()["code"] == "service_indisponible"
    services.genius.panne = False
    assert len(client.get("/api/artistes/suggestions").json()) == 15

    liste = {"artistes": [{"genius_id": 130, "nom": "Drake"}, {"nom": "Adele"}]}
    assert client.put("/api/artistes-preferes", json=liste).status_code == 204
    preferes = client.get("/api/artistes-preferes").json()
    assert [(a["nom"], a["rang"]) for a in preferes] == [("Drake", 1), ("Adele", 2)]
    client.put("/api/artistes-preferes", json={"artistes": [{"nom": "Adele"}]})
    assert [a["nom"] for a in client.get("/api/artistes-preferes").json()] == ["Adele"]
    trop = {"artistes": [{"nom": f"A{i}"} for i in range(31)]}
    assert client.put("/api/artistes-preferes", json=trop).status_code == 422


def test_reglages(client):
    corps = client.get("/api/reglages").json()
    assert corps == {
        "frequence_rappels": "quotidien",
        "heure_rappel": "19:00",
        "heures_rappel_sup": [],
        "intervalle_notifications_min": 120,
        "notifications_debut": "09:00",
        "notifications_fin": "21:00",
        "mots_par_session": 20,
        "mode_revision": "rappel",
        "heure_changement_jour": "04:00",
        "sync_wifi_seulement": False,
    }
    nouveau = {**corps, "heure_rappel": "20:30", "mots_par_session": 10}
    assert client.put("/api/reglages", json=nouveau).status_code == 204
    assert client.get("/api/reglages").json()["heure_rappel"] == "20:30"
    assert client.put("/api/reglages", json={**corps, "mots_par_session": 200}).status_code == 422
    # Fréquences ajoutées et rappels supplémentaires dans la journée (2 au plus).
    plusieurs = {
        **corps,
        "frequence_rappels": "hebdomadaire",
        "heures_rappel_sup": ["08:00", "12:30"],
    }
    assert client.put("/api/reglages", json=plusieurs).status_code == 204
    relu = client.get("/api/reglages").json()
    assert relu["frequence_rappels"] == "hebdomadaire"
    assert relu["heures_rappel_sup"] == ["08:00", "12:30"]
    trois = {**corps, "heures_rappel_sup": ["08:00", "12:00", "15:00"]}
    assert client.put("/api/reglages", json=trois).status_code == 422
    assert (
        client.put("/api/reglages", json={**corps, "heures_rappel_sup": ["25:00"]}).status_code
        == 422
    )
    toutes_les_30 = {**corps, "intervalle_notifications_min": 30, "notifications_debut": "08:30"}
    assert client.put("/api/reglages", json=toutes_les_30).status_code == 204
    relu = client.get("/api/reglages").json()
    assert (relu["intervalle_notifications_min"], relu["notifications_debut"]) == (30, "08:30")
    mauvais = {**corps, "intervalle_notifications_min": 45}
    assert client.put("/api/reglages", json=mauvais).status_code == 422


def test_quotas_et_journaux(client):
    assert "apis" in client.get("/api/quotas").json()
    assert "items" in client.get("/api/logs/erreurs").json()
