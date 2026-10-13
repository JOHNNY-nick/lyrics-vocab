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
        '{"en": "I gave up smoking.", "fr": "J\'ai arrêté de fumer."}',
    ]
    fr, en = asyncio.run(ai_exercise.generer_exercice(services.ollama, "give up", "abandonner"))
    # Troisième essai : « gave up » est une forme de « give up » ; synonyme accepté en secours.
    assert (fr, en) == ("J'ai arrêté de fumer.", "I gave up smoking.")


def test_phrases_deja_vues_evitees(services):
    services.ollama.reponses = ['{"en": "Hello there!", "fr": "Bonjour à toi !"}']
    asyncio.run(
        ai_exercise.generer_exercice(services.ollama, "hello", "bonjour", ["Hello, how are you?"])
    )
    assert "Hello, how are you?" in services.ollama.prompts[-1]


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
