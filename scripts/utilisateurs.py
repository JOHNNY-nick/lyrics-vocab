"""Gestion des utilisateurs de Lyrics & Vocab (amis invités sur ce PC).

Usage (depuis backend/, environnement virtuel actif) :
  python ../scripts/utilisateurs.py liste
  python ../scripts/utilisateurs.py inviter Prénom      -> code d'invitation (accès par le tunnel)
  python ../scripts/utilisateurs.py inviter --moi       -> code pour toi
  python ../scripts/utilisateurs.py retirer Prénom      -> bloque l'accès, garde ses données
  python ../scripts/utilisateurs.py supprimer Prénom    -> bloque l'accès ET efface sa bibliothèque

« Prénom » désigne un ami invité par code ; pour un ami venu par Tailscale, donner son compte
(adresse e-mail). Les codes n'expirent pas. Même chose en page web : <adresse du PC>/admin.
"""

import argparse
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from app.core.config import obtenir_parametres  # noqa: E402
from app.core.errors import ErreurApi  # noqa: E402
from app.services.gestion_utilisateurs import GestionUtilisateurs  # noqa: E402

ACCES = {
    "proprietaire": "propriétaire",
    "code": "code d'invitation",
    "tailscale": "Tailscale",
    "retire": "aucun (accès retiré)",
    "inconnu": "?",
}


def liste(g: GestionUtilisateurs) -> None:
    print(f"{'Utilisateur':<26} {'Accès':<22} {'Mots':>5} {'Révisions':>9}  Dernière activité")
    for u in g.liste():
        if not u.connecte:
            activite = "pas encore connecté"
        elif u.derniere_activite:
            activite = datetime.fromisoformat(u.derniere_activite).strftime("%d/%m/%Y %H:%M")
        else:
            activite = "—"
        print(f"{u.nom:<26} {ACCES[u.acces]:<22} {u.mots:>5} {u.revisions:>9}  {activite}")


def retirer(g: GestionUtilisateurs, nom: str) -> None:
    if g.retirer(nom):
        print(f"Accès de {nom} retiré (ses mots restent sur le PC).")
    elif "@" in nom:
        print(
            f"{nom} passe par Tailscale : révoque le partage dans la console Tailscale "
            "(Machines → desktop-jd3qf3s → Share)."
        )
    else:
        print(f"Aucun code trouvé pour {nom}.")


def supprimer(g: GestionUtilisateurs, nom: str, confirme: bool) -> None:
    if not confirme:
        reponse = input(
            f"Effacer définitivement la bibliothèque de {nom} ? Tape son nom pour confirmer : "
        )
        if reponse.strip().lower() != nom.strip().lower():
            sys.exit("Annulé.")
    g.supprimer(nom)
    print(
        f"Bibliothèque de {nom} supprimée et accès retiré. "
        "Les sauvegardes des 14 derniers jours la contiennent encore."
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sous = parser.add_subparsers(dest="commande", required=True)
    sous.add_parser("liste", help="tous les utilisateurs, leurs mots et leur dernière activité")
    for nom, aide in (
        ("inviter", "crée un code d'invitation (« --moi » pour toi)"),
        ("retirer", "bloque l'accès, garde les données"),
        ("supprimer", "bloque l'accès et efface la bibliothèque"),
    ):
        commande = sous.add_parser(nom, help=aide)
        commande.add_argument("nom")
        if nom == "supprimer":
            commande.add_argument("--oui", action="store_true", help="sans confirmation")
    args = parser.parse_args()
    try:
        g = GestionUtilisateurs(obtenir_parametres())
        if args.commande == "liste":
            liste(g)
        elif args.commande == "inviter":
            code = g.inviter(args.nom, proprietaire=args.nom == "--moi")
            print(f"Code d'invitation pour {args.nom} : {code}")
            print("Il reste valide jusqu'à « retirer » (pas d'expiration).")
        elif args.commande == "retirer":
            retirer(g, args.nom)
        else:
            supprimer(g, args.nom, args.oui)
    except ErreurApi as erreur:
        sys.exit(erreur.message)


if __name__ == "__main__":
    main()
