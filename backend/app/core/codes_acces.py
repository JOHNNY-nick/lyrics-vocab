"""Accès par le tunnel Cloudflare (trycloudflare) : un code d'invitation par ami.

Une requête arrivée par le tunnel porte l'en-tête Cf-Ray (ajouté par Cloudflare, impossible à
retirer) ; son en-tête Tailscale-User-Login, lui, n'est pas fiable (il traverse le tunnel tel
quel). Ces requêtes doivent donc présenter un code d'invitation (en-tête X-Code-Acces) : le
code désigne le compte, donc la base, de l'ami. Les codes sont créés par
scripts/inviter.py et stockés hachés (SHA-256) dans un fichier JSON hors du dépôt.
"""

import hashlib
import json
import os
from pathlib import Path

from starlette.types import ASGIApp, Receive, Scope, Send

EN_TETE_TUNNEL = "cf-ray"
EN_TETE_CODE = "x-code-acces"
# Sans code : seulement de quoi savoir que le serveur répond et installer l'application.
CHEMINS_LIBRES = ("/api/health",)
PREFIXES_PROTEGES = ("/api/", "/docs", "/openapi.json")


def empreinte(code: str) -> str:
    return hashlib.sha256(code.strip().upper().encode()).hexdigest()


class CodesAcces:
    """Fichier {empreinte du code: compte}, relu quand il change."""

    def __init__(self, fichier: str | None):
        self.fichier = Path(fichier) if fichier else None
        self._date: float | None = None
        self._codes: dict[str, str] = {}

    def compte(self, code: str | None) -> str | None:
        if not code or self.fichier is None:
            return None
        try:
            date = os.path.getmtime(self.fichier)
        except OSError:
            return None
        if date != self._date:
            try:
                self._codes = json.loads(self.fichier.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                self._codes = {}
            self._date = date
        return self._codes.get(empreinte(code))


def entetes(scope: Scope) -> dict[str, str]:
    return {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope["headers"]}


def par_tunnel(valeurs: dict[str, str]) -> bool:
    return EN_TETE_TUNNEL in valeurs


class AccesTunnelMiddleware:
    """Refuse l'API aux requêtes du tunnel sans code d'invitation valide (401)."""

    def __init__(self, app: ASGIApp, codes: CodesAcces) -> None:
        self.app = app
        self.codes = codes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        chemin = scope["path"]
        valeurs = entetes(scope)
        if (
            par_tunnel(valeurs)
            and chemin.startswith(PREFIXES_PROTEGES)
            and chemin not in CHEMINS_LIBRES
            and self.codes.compte(valeurs.get(EN_TETE_CODE)) is None
        ):
            corps = json.dumps(
                {
                    "code": "code_acces_requis",
                    "message": "Code d'invitation requis ou invalide.",
                    "details": {},
                }
            ).encode()
            await send(
                {
                    "type": "http.response.start",
                    "status": 401,
                    "headers": [
                        (b"content-type", b"application/json"),
                        (b"content-length", str(len(corps)).encode()),
                    ],
                }
            )
            await send({"type": "http.response.body", "body": corps})
            return
        await self.app(scope, receive, send)
