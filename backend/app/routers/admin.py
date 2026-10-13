"""Page et API d'administration des utilisateurs (/admin), sur ce PC uniquement.

Accès : seulement les requêtes faites sur le PC lui-même (http://127.0.0.1:8000/admin).
Refusé par Tailscale (même depuis les appareils du propriétaire) et par le tunnel Cloudflare :
ces requêtes arrivent avec l'adresse de l'appareil distant (en-têtes X-Forwarded-For) et un
en-tête Tailscale-User-Login ou Cf-Ray.
"""

import asyncio
from pathlib import Path

from fastapi import APIRouter, Depends, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from app.core.codes_acces import EN_TETE_TUNNEL
from app.core.errors import ErreurApi
from app.core.locataires import EN_TETE_COMPTE
from app.services.gestion_utilisateurs import GestionUtilisateurs

PAGE = Path(__file__).resolve().parents[1] / "admin" / "index.html"

routeur = APIRouter(tags=["administration"])


class AccesAdminRefuse(ErreurApi):
    code, statut_http = "acces_admin_refuse", 403
    message_defaut = "Cette page ne s'ouvre que sur le PC lui-même : http://127.0.0.1:8000/admin"


# « testclient » : client des tests automatiques (jamais vu en production).
HOTES_LOCAUX = {"127.0.0.1", "::1", "localhost", "testclient"}


def proprietaire(request: Request) -> None:
    """Refuse toute requête qui ne vient pas du PC lui-même (dépendance des routes)."""
    distante = EN_TETE_TUNNEL in request.headers or EN_TETE_COMPTE in request.headers
    hote = request.client.host if request.client else None
    if distante or hote not in HOTES_LOCAUX:
        raise AccesAdminRefuse()


def gestion(request: Request) -> GestionUtilisateurs:
    return GestionUtilisateurs(request.app.state.parametres)


class Invitation(BaseModel):
    prenom: str = Field(min_length=1, max_length=40)


class Cible(BaseModel):
    compte: str = Field(min_length=1, max_length=320)


class Suppression(Cible):
    confirmation: str = Field(min_length=1, max_length=320)


@routeur.get("/admin", include_in_schema=False, dependencies=[Depends(proprietaire)])
def page() -> FileResponse:
    return FileResponse(PAGE, headers={"Cache-Control": "no-cache"})


@routeur.get("/api/admin/utilisateurs", dependencies=[Depends(proprietaire)])
async def utilisateurs(request: Request, g: GestionUtilisateurs = Depends(gestion)) -> dict:
    lignes = await asyncio.to_thread(g.liste)
    parametres = request.app.state.parametres
    tunnel = None
    fichier = Path(parametres.log_dir or ".").parent / "tunnel" / "adresse.txt"
    if fichier.exists():
        tunnel = fichier.read_text(encoding="utf-8-sig").strip() or None
    connexions = request.app.state.locataires.connexions
    utilisateurs = []
    for ligne in lignes:
        fiche = connexions.fiche(ligne.base) if ligne.base else {}
        utilisateurs.append(
            {**ligne.en_dict(), "connexion": fiche.get("derniere"), "voie": fiche.get("voie")}
        )
    return {
        "utilisateurs": utilisateurs,
        "tunnel": tunnel,
        "apk": f"{tunnel}/apk/lyrics-vocab.apk" if tunnel else None,
    }


@routeur.get("/api/admin/utilisateur", dependencies=[Depends(proprietaire)])
async def utilisateur(
    compte: str, request: Request, g: GestionUtilisateurs = Depends(gestion)
) -> dict:
    """Fiche complète : compte, connexions, bibliothèque, révisions, réglages, appareils."""
    details = await asyncio.to_thread(g.details, compte)
    details["connexions"] = request.app.state.locataires.connexions.fiche(details["base"])
    return details


@routeur.post("/api/admin/invitations", dependencies=[Depends(proprietaire)])
async def inviter(entree: Invitation, g: GestionUtilisateurs = Depends(gestion)) -> dict:
    code = await asyncio.to_thread(g.inviter, entree.prenom)
    return {"prenom": entree.prenom.strip(), "code": code}


@routeur.post("/api/admin/retraits", dependencies=[Depends(proprietaire)])
async def retirer(entree: Cible, g: GestionUtilisateurs = Depends(gestion)) -> dict:
    return {"codes_retires": await asyncio.to_thread(g.retirer, entree.compte)}


@routeur.post("/api/admin/suppressions", dependencies=[Depends(proprietaire)])
async def supprimer(
    entree: Suppression, request: Request, g: GestionUtilisateurs = Depends(gestion)
) -> dict:
    nom = entree.compte.split(":", 1)[-1]
    if entree.confirmation.strip().lower() != nom.strip().lower():
        raise ErreurApi(
            "Le nom tapé ne correspond pas.",
            code="confirmation_invalide",
            statut_http=422,
        )
    await asyncio.to_thread(g.supprimer, entree.compte)
    request.app.state.locataires.connexions.oublier(g.base_de(entree.compte))
    # Le serveur oublie la base supprimée (connexions, tâches de fond).
    await asyncio.to_thread(request.app.state.locataires.tous)
    return {"supprime": entree.compte}
