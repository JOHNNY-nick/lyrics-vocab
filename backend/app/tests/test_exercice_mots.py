"""Révisions du jour : phrases construites autour des mots de l'utilisateur."""

import asyncio
import uuid
from datetime import date

from app.models import Mot, Revision
from app.services import ai_exercise, exercices_prets, mots


def test_paire_avec_le_mot(services):
    services.ollama.reponses = [
        '{"en": "She lowkey loves jazz.", "fr": "Elle aime discrètement le jazz."}'
    ]
    fr, en = asyncio.run(
        ai_exercise.generer_exercice(services.ollama, "lowkey", "discrètement ; plutôt")
    )
    assert (fr, en) == ("Elle aime discrètement le jazz.", "She lowkey loves jazz.")


def test_paire_rejetee_si_le_mot_anglais_manque_ou_est_dans_la_phrase_francaise(services):
    services.ollama.reponses = [
        '{"en": "She quietly loves jazz.", "fr": "Elle aime discrètement le jazz."}',
        '{"en": "She lowkey loves jazz.", "fr": "Elle aime lowkey le jazz."}',
    ]
    try:
        asyncio.run(ai_exercise.generer_exercice(services.ollama, "lowkey", "discrètement"))
        raise AssertionError("aucune paire valide")
    except ai_exercise.IaIndisponible:
        pass


def test_synonyme_francais_accepte_en_secours(services):
    services.ollama.reponses = [
        '{"en": "I gave up smoking.", "fr": "J\'ai arrêté de fumer."}',
        '{"en": "I gave up smoking.", "fr": "J\'ai arrêté de fumer."}',
    ]
    fr, en = asyncio.run(ai_exercise.generer_exercice(services.ollama, "give up", "abandonner"))
    # « gave up » est une forme de « give up » ; le synonyme français est accepté en secours.
    assert (fr, en) == ("J'ai arrêté de fumer.", "I gave up smoking.")


def test_phrases_deja_vues_evitees(services):
    services.ollama.reponses = ['{"en": "Hello there!", "fr": "Bonjour à toi !"}']
    asyncio.run(
        ai_exercise.generer_exercice(services.ollama, "hello", "bonjour", ["Hello, how are you?"])
    )
    assert "Hello, how are you?" in services.ollama.prompts[-1]


def test_sens_present_conjugue_ou_derive():
    assert ai_exercise.sens_present("Elle a tendance à être en retard.", "avoir tendance à")
    assert ai_exercise.sens_present(
        "J'ai surpris ma sœur en train d'écouter clandestinement.", "écoute clandestine"
    )
    assert ai_exercise.sens_present("Le gouvernement contraindra la société.", "contraindre")
    assert not ai_exercise.sens_present("J'adore ma famille.", "amour")


def test_reponse_sans_le_mot_au_mieux_proche():
    evaluation = ai_exercise.Evaluation("correct", "Bien.", False)
    resultat = ai_exercise.garde_fou(
        evaluation, "I gave up smoking.", "I quit smoking.", terme="give up"
    )
    assert resultat.verdict == "incorrect" or resultat.verdict == "proche"
    juste = ai_exercise.garde_fou(
        evaluation, "I gave up smoking.", "I gave up smoking.", terme="give up"
    )
    assert juste.verdict == "correct"


def test_verdicts_immediats_sans_ia(services):
    services.ollama.panne = True  # l'IA n'est pas appelée
    identique = asyncio.run(
        ai_exercise.evaluer(
            services.ollama, "x", "She tends to be late.", "she tends to be late", terme="tend"
        )
    )
    assert identique.verdict == "correct" and not identique.verdict_repli
    sans_rapport = asyncio.run(
        ai_exercise.evaluer(
            services.ollama, "x", "She tends to be late.", "The cat sleeps.", terme="tend"
        )
    )
    assert sans_rapport.verdict == "incorrect" and not sans_rapport.verdict_repli
    assert services.ollama.prompts == []


def _mot_du_jour(fabrique, terme="lowkey"):
    with fabrique() as session:
        mot, _ = mots.creer_mot(session, uuid.uuid4(), terme, date.today(), None)
        mot.traduction_fr = "discrètement"
        session.commit()
        return mot.id


def test_phrases_preparees_puis_servies_sans_attendre(client, fabrique, services):
    mot_id = _mot_du_jour(fabrique)
    services.ollama.reponses = [
        '{"en": "I lowkey love it.", "fr": "Je l\'aime discrètement."}',
        '{"en": "She lowkey left.", "fr": "Elle est partie discrètement."}',
    ]
    assert asyncio.run(exercices_prets.preparer(services)) == 1
    assert asyncio.run(exercices_prets.preparer(services)) == 0  # déjà prête
    appels = len(services.ollama.prompts)
    servie = client.post("/api/exercices", json={"mot_id": str(mot_id)}).json()
    assert servie["phrase_fr"] == "Je l'aime discrètement."
    assert len(services.ollama.prompts) == appels  # aucune génération à la demande
    # « Nouvelle phrase » : une autre phrase est générée.
    autre = client.post("/api/exercices", json={"mot_id": str(mot_id), "nouvelle": True}).json()
    assert autre["phrase_fr"] == "Elle est partie discrètement."


def test_phrase_utilisee_regeneree(client, fabrique, services):
    mot_id = _mot_du_jour(fabrique)
    services.ollama.reponses = ['{"en": "I lowkey love it.", "fr": "Je l\'aime discrètement."}']
    asyncio.run(exercices_prets.preparer(services))
    with fabrique() as session:
        revision = session.query(Revision).filter(Revision.mot_id == mot_id).one()
        revision.verdict = "proche"
        session.commit()
        assert not exercices_prets.phrase_prete(revision)
        assert [m.id for _, m in exercices_prets.a_preparer(session)] == [mot_id]
        assert session.get(Mot, mot_id) is not None
