"""Révisions du jour : phrases construites autour des mots de l'utilisateur."""

import asyncio

from app.services import ai_exercise


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
