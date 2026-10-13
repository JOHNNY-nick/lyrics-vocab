"""Génère les phrases d'exemple des mots enregistrés qui n'en ont pas encore.

Usage (depuis backend/, environnement virtuel actif) : python ../scripts/completer_exemples.py
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
from app.models import Extrait, Mot  # noqa: E402
from app.services.ai_exemples import generer_exemples  # noqa: E402


async def main() -> None:
    parametres = obtenir_parametres()
    fabrique = creer_fabrique(creer_moteur(parametres.database_url))
    async with httpx.AsyncClient(timeout=parametres.http_timeout_s) as http:
        services = construire_services(parametres, fabrique, http)
        with fabrique() as session:
            a_completer = session.scalars(
                select(Mot).where(
                    Mot.deleted_at.is_(None),
                    Mot.exemples.is_(None),
                    Mot.traduction_fr.is_not(None),
                )
            ).all()
            completes = 0
            for mot in a_completer:
                extrait = session.scalar(
                    select(Extrait.texte)
                    .where(Extrait.mot_id == mot.id, Extrait.deleted_at.is_(None))
                    .order_by(Extrait.created_at)
                    .limit(1)
                )
                try:
                    exemples = await generer_exemples(
                        services.ollama, mot.terme, mot.traduction_fr, extrait
                    )
                except Exception:
                    exemples = None
                if exemples:
                    mot.exemples = exemples
                    session.commit()
                    completes += 1
                print(f"{mot.terme} : {len(exemples or [])} phrase(s)")
    print(f"{completes} mots complétés sur {len(a_completer)}.")


if __name__ == "__main__":
    asyncio.run(main())
