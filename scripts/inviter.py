"""Codes d'invitation pour les amis qui passent par le tunnel Cloudflare.

Usage (depuis backend/, environnement virtuel actif) :
  python ../scripts/inviter.py Mangala         -> crée un code pour Mangala (sa propre bibliothèque)
  python ../scripts/inviter.py --moi           -> code donnant accès à ta bibliothèque
  python ../scripts/inviter.py --retirer Mangala
  python ../scripts/inviter.py --liste
"""

import argparse
import json
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from app.core.codes_acces import empreinte  # noqa: E402
from app.core.config import obtenir_parametres  # noqa: E402

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # sans 0/O, 1/I/L


def nouveau_code() -> str:
    corps = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return f"LV-{corps[:4]}-{corps[4:]}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("nom", nargs="?")
    parser.add_argument("--moi", action="store_true")
    parser.add_argument("--retirer")
    parser.add_argument("--liste", action="store_true")
    args = parser.parse_args()
    parametres = obtenir_parametres()
    if not parametres.codes_acces_fichier:
        sys.exit("CODES_ACCES_FICHIER n'est pas renseigné dans backend/.env.")
    fichier = Path(parametres.codes_acces_fichier)
    codes = json.loads(fichier.read_text(encoding="utf-8")) if fichier.exists() else {}

    if args.liste:
        for compte in sorted(set(codes.values())):
            print(compte)
        return
    if args.retirer:
        cible = f"invite:{args.retirer.strip().lower()}"
        codes = {k: v for k, v in codes.items() if v != cible}
        fichier.write_text(json.dumps(codes, indent=2), encoding="utf-8")
        print(f"Codes de {args.retirer} retirés.")
        return
    if args.moi:
        compte = parametres.proprietaire_login.strip().lower()
    elif args.nom:
        compte = f"invite:{args.nom.strip().lower()}"
    else:
        parser.error("indique un nom, --moi, --retirer ou --liste")
    code = nouveau_code()
    codes[empreinte(code)] = compte
    fichier.parent.mkdir(parents=True, exist_ok=True)
    fichier.write_text(json.dumps(codes, indent=2), encoding="utf-8")
    print(f"Code d'invitation pour {args.nom or 'toi'} : {code}")


if __name__ == "__main__":
    main()
