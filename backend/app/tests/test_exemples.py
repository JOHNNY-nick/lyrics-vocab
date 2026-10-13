"""Phrases d'exemple générées par l'IA (validation de la sortie)."""

from app.services.ai_exemples import valider_exemples


def test_exemples_valides_avec_bloc_de_code():
    brut = """```json
[{"en": "She crafts jewelry by hand.", "fr": "Elle fabrique des bijoux à la main."},
 {"en": "Writing is a craft.", "fr": "L'écriture est un art."}]
```"""
    assert valider_exemples(brut, "craft") == [
        {
            "en": "She crafts jewelry by hand.",
            "fr": "Elle fabrique des bijoux à la main.",
        },
        {"en": "Writing is a craft.", "fr": "L'écriture est un art."},
    ]


def test_exemple_sans_le_mot_ecarte():
    brut = '[{"en": "I love you.", "fr": "Je t\'aime."}, {"en": "Hello there!", "fr": "Salut !"}]'
    assert valider_exemples(brut, "hello") == [{"en": "Hello there!", "fr": "Salut !"}]


def test_sortie_invalide():
    assert valider_exemples("Voici deux phrases : ...", "craft") is None
    assert valider_exemples('[{"en": "", "fr": "x"}]', "craft") is None
    assert valider_exemples('{"en": "craft", "fr": "art"}', "craft") is None
