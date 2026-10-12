"""Charge le jeu de démonstration de 20 mots (BDD-19, TEST-04, DT-03).

Usage (depuis backend/, environnement virtuel actif) :
    python ../scripts/charger_demo.py            # crée les 20 mots ; le backend les enrichit
    python ../scripts/charger_demo.py --fiches   # ajoute aussi des fiches d'exemple, sans API

Le jeu contient au moins 5 argots, 3 mots polysémiques, 3 expressions de plusieurs mots,
2 contractions et 1 mot absent de toute chanson. Avec --fiches, les extraits sont des phrases
écrites pour la démonstration (aucune parole réelle) attribuées à un artiste de démonstration.
"""

import argparse
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from app.core.config import obtenir_parametres  # noqa: E402
from app.core.database import creer_fabrique, creer_moteur  # noqa: E402
from app.models import Artiste, Extrait, Morceau  # noqa: E402
from app.services import artistes, mots, reglages  # noqa: E402
from app.services.calendrier import fuseau_valide, jour_local  # noqa: E402
from app.services.extraction import extraire  # noqa: E402

# terme, catégorie, traduction, explication, phrase de démonstration
JEU = [
    ("lowkey", "argot", "discrètement ; plutôt",
     "Argot : « lowkey » veut dire « un peu » ou « en secret ».",
     "I lowkey miss you\nBut I'm never saying that"),
    ("vibe", "argot", "ambiance", "Argot : l'ambiance ou l'énergie que dégage quelqu'un.",
     "Got a vibe that I can't explain\nDancing slow in the summer rain"),
    ("slay", "argot", "assurer, déchirer", "Argot : réussir quelque chose de façon éclatante.",
     "Walk in the room and you slay it all\nEvery head turns down the hall"),
    ("ghost", "argot", "disparaître sans prévenir",
     "Argot : couper le contact avec quelqu'un sans explication.",
     "You said you'd call but you ghost me again\nI'm done pretending we're more than friends"),
    ("salty", "argot", "amer, vexé", "Argot : être de mauvaise humeur après une déception.",
     "Don't be salty when I win\nYou knew the game when we'd begin"),
    ("cap", "argot", "mensonge", "Argot : « no cap » signifie « sans mentir ».",
     "That's a cap, I know it's a lie\nI can see it in your eye"),
    ("ain't", "contraction", "ne… pas (familier)", "Forme familière de « am not / is not ».",
     "Ain't nobody love you like I do\nAin't nobody stay this true"),
    ("gonna", "contraction", "aller (futur proche)", "Contraction familière de « going to ».",
     "I'm gonna run to you tonight\nLeave the city lights"),
    ("break up", "expression", "rompre", "Expression : mettre fin à une relation amoureuse.",
     "We might break up before the fall\nBut I still want you after all"),
    ("let go", "expression", "lâcher prise", "Expression : cesser de s'accrocher à quelque chose.",
     "Time to let go of yesterday\nWatch the old pain fade away"),
    ("ride or die", "expression", "fidèle jusqu'au bout",
     "Expression figurée : une personne loyale quoi qu'il arrive.",
     "You're my ride or die\nNever have to wonder why"),
    ("fire", "polysemique", "génial ; feu", "Ici, sens argotique : quelque chose d'excellent.",
     "This track is fire, turn it up\nWe don't ever wanna stop"),
    ("bank", "polysemique", "banque ; rive", "Ici, la rive d'une rivière.",
     "Sitting on the river bank\nThinking of the ones I thank"),
    ("crush", "polysemique", "béguin ; écraser", "Ici, une attirance amoureuse secrète.",
     "You're my crush since the first day\nToo shy to say it anyway"),
    ("hustle", "argot", "se démener", "Argot : travailler dur, souvent pour réussir.",
     "Every day I hustle, never sleep\nPromises I'm gonna keep"),
    ("throw shade", "expression", "dénigrer subtilement",
     "Expression : critiquer quelqu'un de manière indirecte.",
     "Why you throw shade on my name\nYou and I are not the same"),
    ("heartbreak", "mot", "chagrin d'amour", "Le chagrin causé par une rupture.",
     "Another heartbreak on the way\nStill I hope you're gonna stay"),
    ("spill the tea", "expression", "balancer les potins",
     "Expression argotique : révéler des ragots.",
     "Come and spill the tea tonight\nTell me everything in sight"),
    ("savage", "argot", "impitoyable, sans filtre",
     "Argot : une attitude audacieuse, sans aucune retenue.",
     "She's a savage in the game\nNothing ever stays the same"),
    ("zorglub", "absent", None, None, None),
]

ARTISTE_DEMO = "Artiste de démonstration"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fiches", action="store_true",
                        help="ajoute traductions, explications et extraits d'exemple")
    options = parser.parse_args()
    parametres = obtenir_parametres()
    fabrique = creer_fabrique(creer_moteur(parametres.database_url))
    with fabrique() as session:
        heure = reglages.obtenir(session).heure_changement_jour
        jour = jour_local(datetime.now(UTC), fuseau_valide(None, parametres.fuseau_pc), heure)
        artiste = None
        if options.fiches:
            artiste = artistes.obtenir_ou_creer(session, ARTISTE_DEMO)
        crees = 0
        for i, (terme, _, traduction, explication, phrase) in enumerate(JEU):
            mot, cree = mots.creer_mot(session, uuid.uuid4(), terme, jour)
            crees += int(cree)
            if not (options.fiches and cree):
                continue
            if traduction is None:
                mot.statut_enrichissement = "partiel"
                mot.erreur_enrichissement = "aucun_extrait"
                mot.enrichi_le = datetime.now(UTC)
                continue
            morceau = Morceau(id=uuid.uuid4(), artiste_id=artiste.id, titre=f"Chanson démo {i + 1}")
            session.add(morceau)
            session.flush()
            decoupe = extraire(phrase, mot.terme_normalise)
            if decoupe is not None:
                session.add(Extrait(id=uuid.uuid4(), mot_id=mot.id, morceau_id=morceau.id,
                                    texte=decoupe.texte, surbrillance_debut=decoupe.debut,
                                    surbrillance_fin=decoupe.fin, hors_liste=i % 4 == 3))
            mot.traduction_fr = traduction
            mot.explication = explication
            mot.source_explication = "ia"
            mot.statut_enrichissement = "ok" if decoupe else "partiel"
            mot.enrichi_le = datetime.now(UTC)
        session.commit()
        total = session.query(Artiste).count()
    print(f"{crees} mots créés sur {len(JEU)} ({total} artistes en base).")


if __name__ == "__main__":
    main()
