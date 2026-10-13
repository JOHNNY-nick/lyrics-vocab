"""Page et API d'administration des utilisateurs (/admin), réservées au propriétaire.

Accès : requêtes locales (127.0.0.1, sans en-tête de compte) ou appareils du propriétaire
par Tailscale. Toujours refusé par le tunnel Cloudflare (même avec un code) et aux amis.
"""

import asyncio
from pathlib import Path

from fastapi import APIRouter, Depends, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from app.core.codes_acces import EN_TETE_TUNNEL
from app.core.errors import ErreurApi
from app.core.locataires import compte
from app.services.gestion_utilisateurs import GestionUtilisateurs

PAGE = Path(__file__).resolve().parents[1] / "admin" / "index.html"

routeur = APIRouter(tags=["administration"])


class AccesAdminRefuse(ErreurApi):
    code, statut_http = "acces_admin_refuse", 403
    message_defaut = "Cette page est réservée au propriétaire du PC."


def proprietaire(request: Request) -> None:
    """Refuse tout ce qui n'est pas le propriétaire (dépendance des routes)."""
    if EN_TETE_TUNNEL in request.headers:
        raise AccesAdminRefuse()
    login = compte(request)
    attendu = request.app.state.parametres.proprietaire_login.strip().lower()
    if login is not None and login != attendu:
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
    return {
        "utilisateurs": [ligne.en_dict() for ligne in lignes],
        "tunnel": tunnel,
        "apk": f"{tunnel}/apk/lyrics-vocab.apk" if tunnel else None,
    }


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
    # Le serveur oublie la base supprimée (connexions, tâches de fond).
    await asyncio.to_thread(request.app.state.locataires.tous)
    return {"supprime": entree.compte}
