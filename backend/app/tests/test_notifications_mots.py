"""Notifications d'un mot au hasard à intervalle régulier."""

import uuid
from datetime import date, datetime, time

from app.services import mots
from app.services import notifications_mots as nm


def test_creneaux_grille_fixe():
    jour = date(2026, 10, 13)
    creneaux = nm.creneaux_du_jour(jour, time(9, 0), time(21, 0), 120)
    assert [c.hour for c in creneaux] == [9, 11, 13, 15, 17, 19]
    assert len(nm.creneaux_du_jour(jour, time(9, 0), time(10, 0), 30)) == 2
    assert nm.creneaux_du_jour(jour, time(9, 0), time(21, 0), 0) == []
    # Fin avant le début : jusqu'à minuit.
    assert [c.hour for c in nm.creneaux_du_jour(jour, time(22, 0), time(1, 0), 60)] == [22, 23]


def test_cle_et_tirage_identiques_au_telephone():
    # Mêmes valeurs dans le test Dart (logique_test.dart) : PC et téléphone tirent le même mot.
    assert nm.cle(datetime(2026, 10, 13, 9, 0)) == 14086620
    assert nm.indice_mot(14086620, 120, 9) == 6
    assert nm.indice_mot(123, 60, 1) == 0


def test_notification_due_avec_mot_et_explication(fabrique):
    with fabrique() as session:
        mot, _ = mots.creer_mot(session, uuid.uuid4(), "lowkey", date.today(), None)
        mot.traduction_fr = "discrètement"
        mot.explication = "Argot : « un peu », « en secret »."
        mot.source_explication = "ia"
        session.commit()
        a_l_heure = nm.notification_due(session, datetime(2026, 10, 13, 11, 1))
        assert a_l_heure is not None and a_l_heure.mot_id == str(mot.id)
        assert a_l_heure.titre == "lowkey — discrètement"
        assert a_l_heure.texte.startswith("Argot")
        assert nm.notification_due(session, datetime(2026, 10, 13, 11, 5)) is None  # trop tard
        assert nm.notification_due(session, datetime(2026, 10, 13, 22, 0)) is None  # hors plage
