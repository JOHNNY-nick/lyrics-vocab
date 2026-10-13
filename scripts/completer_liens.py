"""Complète le lien « Écouter la chanson » des morceaux enregistrés sans lien.

Usage (depuis backend/, environnement virtuel actif) : python ../scripts/completer_liens.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

import httpx  # noqa: E402
from sqlalchemy import select  # noqa: E402

from app.core.config import obtenir_parametres  # noqa: E402
from app.core.database import creer_fabrique, creer_moteur  # noqa: E402
from app.main import construire_services  # noqa: E402
from app.models import Artiste, Morceau  # noqa: E402


async def main() -> None:
    parametres = obtenir_parametres()
    fabrique = creer_fabrique(creer_moteur(parametres.database_url))
    async with httpx.AsyncClient(timeout=parametres.http_timeout_s) as http:
        services = construire_services(parametres, fabrique, http)
        with fabrique() as session:
            lignes = session.execute(
                select(Morceau, Artiste.nom)
                .join(Artiste, Artiste.id == Morceau.artiste_id)
                .where(Morceau.url_genius.is_(None))
            ).all()
            completes = 0
            for morceau, artiste in lignes:
                try:
                    lien = await services.genius.lien_morceau(morceau.titre, artiste)
                except Exception:
                    lien = None
                if lien:
                    morceau.url_genius = lien
                    completes += 1
                print(f"{artiste} — {morceau.titre} : {lien or 'non trouvé'}")
            session.commit()
    print(f"{completes} liens ajoutés sur {len(lignes)} morceaux.")


if __name__ == "__main__":
    asyncio.run(main())
