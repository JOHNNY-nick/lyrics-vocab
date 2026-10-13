"""Refus du modèle : jamais enregistrés comme traduction ou explication."""

from app.services.ai_explainer import est_refus
from app.services.ai_traduction import nettoyer_traduction


def test_refus_detectes():
    assert est_refus("Je suis désolé, mais je ne peux pas répondre à cette demande")
    assert est_refus("I'm sorry, I can't help with that.")
    assert not est_refus("putain ; merde")
    assert not est_refus("Argot : exprime la colère ou la surprise.")


def test_traduction_refusee():
    assert (
        nettoyer_traduction("Je suis désolé, mais je ne peux pas répondre à cette demande") is None
    )
    assert nettoyer_traduction("putain") == "putain"
    assert nettoyer_traduction("foutu ; foutu") == "foutu"
    assert nettoyer_traduction("discrètement ; plutôt") == "discrètement ; plutôt"


def test_secours_mots_grossiers(services):
    import asyncio

    from app.services import ai_explainer
    from app.services.ai_traduction import traduire_par_ia

    refus = "Je suis désolé, mais je ne peux pas répondre à cette demande."
    services.ollama.reponses = [refus, refus, refus]
    assert asyncio.run(traduire_par_ia(services.ollama, "Fuck", None)).startswith("putain")
    explication = asyncio.run(ai_explainer.expliquer(services.ollama, "fuck", None))
    assert explication.texte.startswith("Argot")
