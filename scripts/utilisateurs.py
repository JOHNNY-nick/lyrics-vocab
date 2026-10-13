"""Gestion des utilisateurs de Lyrics & Vocab (amis invités sur ce PC).

Usage (depuis backend/, environnement virtuel actif) :
  python ../scripts/utilisateurs.py liste
  python ../scripts/utilisateurs.py inviter Prénom      -> code d'invitation (accès par le tunnel)
  python ../scripts/utilisateurs.py retirer Prénom      -> bloque l'accès, garde ses données
  python ../scripts/utilisateurs.py supprimer Prénom    -> bloque l'accès ET efface sa bibliothèque

« Prénom » désigne un ami invité par code ; pour un ami venu par Tailscale, donner son compte
(adresse e-mail). Les codes n'expirent pas : ils restent valides jusqu'à « retirer ».
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from sqlalchemy import create_engine, text  # noqa: E402
from sqlalchemy.engine import make_url  # noqa: E402

from app.core.codes_acces import (  # noqa: E402
    compte_invite,
    ecrire_codes,
    empreinte,
    lire_codes,
    nouveau_code,
)
from app.core.config import obtenir_parametres  # noqa: E402
from app.core.locataires import SUFFIXE, base_du_compte  # noqa: E402


class Gestion:
    def __init__(self) -> None:
        self.p = obtenir_parametres()
        if not self.p.codes_acces_fichier:
            sys.exit("CODES_ACCES_FICHIER n'est pas renseigné dans backend/.env.")
        self.url = make_url(self.p.database_url)
        self.principale = self.url.database
        self.proprietaire = self.p.proprietaire_login.strip().lower()

    # --- Données ---------------------------------------------------------------------------

    def codes(self) -> dict[str, str]:
        return lire_codes(self.p.codes_acces_fichier)

    def registre(self) -> dict:
        fichier = self.p.registre_utilisateurs_fichier
        if fichier and Path(fichier).exists():
            return json.loads(Path(fichier).read_text(encoding="utf-8"))
        return {}

    def ecrire_registre(self, registre: dict) -> None:
        fichier = self.p.registre_utilisateurs_fichier
        if fichier:
            Path(fichier).write_text(
                json.dumps(registre, indent=2, ensure_ascii=False), encoding="utf-8"
            )

    def moteur(self, base: str):
        url = self.url.set(database=base).render_as_string(hide_password=False)
        return create_engine(url, isolation_level="AUTOCOMMIT")

    def bases(self) -> list[str]:
        moteur = self.moteur("postgres")
        try:
            with moteur.connect() as c:
                return list(
                    c.execute(
                        text("SELECT datname FROM pg_database WHERE datname LIKE :m ORDER BY 1"),
                        {"m": f"{self.principale}{SUFFIXE}%"},
                    ).scalars()
                )
        finally:
            moteur.dispose()

    def statistiques(self, base: str) -> tuple[int, int, str]:
        moteur = self.moteur(base)
        try:
            with moteur.connect() as c:
                mots = c.execute(text("SELECT count(*) FROM mot WHERE deleted_at IS NULL")).scalar()
                faites = c.execute(
                    text("SELECT count(*) FROM revision WHERE statut = 'faite'")
                ).scalar()
                derniere = c.execute(
                    text(
                        "SELECT max(t) FROM (SELECT max(updated_at) t FROM mot "
                        "UNION ALL SELECT max(updated_at) FROM revision) x"
                    )
                ).scalar()
        finally:
            moteur.dispose()
        return mots or 0, faites or 0, derniere.strftime("%d/%m/%Y %H:%M") if derniere else "—"

    def compte_de(self, nom: str) -> str:
        """Prénom (ami invité par code) ou adresse e-mail (ami venu par Tailscale)."""
        return nom.strip().lower() if "@" in nom else compte_invite(nom)

    def comptes_connus(self) -> dict[str, str]:
        """{base: compte} d'après le registre et les codes existants."""
        connus = {b: v.get("compte", "") for b, v in self.registre().items()}
        for compte in set(self.codes().values()):
            if compte != self.proprietaire:
                connus.setdefault(base_du_compte(self.principale, compte), compte)
        return connus

    # --- Commandes -------------------------------------------------------------------------

    def liste(self) -> None:
        codes = set(self.codes().values())
        connus = self.comptes_connus()
        lignes = [("Toi (propriétaire)", "Tailscale", self.principale)]
        for base in self.bases():
            compte = connus.get(base, "")
            if compte.startswith("invite:"):
                nom = compte.split(":", 1)[1].capitalize()
                acces = "code d'invitation" if compte in codes else "aucun (accès retiré)"
            elif compte:
                nom, acces = compte, "Tailscale"
            else:
                nom, acces = "inconnu", "?"
            lignes.append((nom, acces, base))
        # Amis invités qui ne se sont pas encore connectés (pas encore de base).
        for compte in sorted(codes):
            if compte.startswith("invite:") and base_du_compte(self.principale, compte) not in [
                b for _, _, b in lignes
            ]:
                lignes.append((compte.split(":", 1)[1].capitalize(), "code d'invitation", None))
        print(f"{'Utilisateur':<22} {'Accès':<22} {'Mots':>5} {'Révisions':>9}  Dernière activité")
        for nom, acces, base in lignes:
            if base:
                mots, faites, derniere = self.statistiques(base)
            else:
                mots, faites, derniere = 0, 0, "pas encore connecté"
            print(f"{nom:<22} {acces:<22} {mots:>5} {faites:>9}  {derniere}")
        if self.proprietaire in codes:
            print("\n(Tu as aussi un code pour passer toi-même par le tunnel.)")

    def inviter(self, nom: str) -> None:
        compte = self.proprietaire if nom == "--moi" else self.compte_de(nom)
        codes = self.codes()
        code = nouveau_code()
        codes[empreinte(code)] = compte
        ecrire_codes(self.p.codes_acces_fichier, codes)
        print(f"Code d'invitation pour {nom} : {code}")
        print("Il reste valide jusqu'à « retirer » (pas d'expiration).")

    def retirer(self, nom: str, silencieux: bool = False) -> None:
        compte = self.compte_de(nom)
        codes = self.codes()
        restants = {k: v for k, v in codes.items() if v != compte}
        ecrire_codes(self.p.codes_acces_fichier, restants)
        if not silencieux:
            if len(restants) < len(codes):
                print(f"Accès de {nom} retiré (ses mots restent sur le PC).")
            elif "@" in nom:
                print(
                    f"{nom} passe par Tailscale : révoque le partage dans la console Tailscale "
                    "(https://login.tailscale.com/admin/machines → desktop-jd3qf3s → Share)."
                )
            else:
                print(f"Aucun code trouvé pour {nom}.")

    def supprimer(self, nom: str, confirme: bool) -> None:
        compte = self.compte_de(nom)
        if compte == self.proprietaire:
            sys.exit("Impossible de supprimer ta propre bibliothèque.")
        base = base_du_compte(self.principale, compte)
        if not confirme:
            reponse = input(
                f"Effacer définitivement la bibliothèque de {nom} ? Tape son nom pour confirmer : "
            )
            if reponse.strip().lower() != nom.strip().lower():
                sys.exit("Annulé.")
        self.retirer(nom, silencieux=True)
        moteur = self.moteur("postgres")
        try:
            with moteur.connect() as c:
                c.execute(text(f'DROP DATABASE IF EXISTS "{base}" WITH (FORCE)'))
        finally:
            moteur.dispose()
        registre = self.registre()
        registre.pop(base, None)
        self.ecrire_registre(registre)
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
    gestion = Gestion()
    if args.commande == "liste":
        gestion.liste()
    elif args.commande == "inviter":
        gestion.inviter(args.nom)
    elif args.commande == "retirer":
        gestion.retirer(args.nom)
    else:
        gestion.supprimer(args.nom, args.oui)


if __name__ == "__main__":
    main()
