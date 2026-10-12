"""Intergiciels ASGI : corrélation et journal des requêtes, taille du corps, limite de débit."""

import json
import time
import uuid
from collections import defaultdict, deque
from collections.abc import Callable

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.logging import identifiant_correlation, journaliser

ENTETE_CORRELATION = "x-request-id"
ENTETE_APPAREIL = "x-appareil-id"
FENETRE_DEBIT_S = 60
CHEMINS_SANS_LIMITE = ("/api/sync/", "/api/health")


def _entete(scope: Scope, nom: str) -> str | None:
    for cle, valeur in scope.get("headers", []):
        if cle.decode("latin-1").lower() == nom:
            return valeur.decode("latin-1")
    return None


async def _repondre_json(send: Send, statut: int, corps: dict) -> None:
    contenu = json.dumps(corps, ensure_ascii=False).encode("utf-8")
    await send(
        {
            "type": "http.response.start",
            "status": statut,
            "headers": [
                (b"content-type", b"application/json; charset=utf-8"),
                (b"content-length", str(len(contenu)).encode()),
            ],
        }
    )
    await send({"type": "http.response.body", "body": contenu})


class CorrelationMiddleware:
    """X-Request-Id (généré s'il manque) repris dans les journaux et la réponse (API-09)."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        recu = _entete(scope, ENTETE_CORRELATION) or ""
        correlation = recu if 0 < len(recu) <= 64 else str(uuid.uuid4())
        jeton = identifiant_correlation.set(correlation)
        debut = time.perf_counter()
        statut = 500
        statut_envoye = False

        async def envoyer(message: Message) -> None:
            nonlocal statut, statut_envoye
            if message["type"] == "http.response.start":
                statut = message["status"]
                statut_envoye = True
                message.setdefault("headers", [])
                message["headers"] = [
                    *message["headers"],
                    (b"x-request-id", correlation.encode("latin-1")),
                ]
            await send(message)

        try:
            await self.app(scope, receive, envoyer)
        except Exception as exc:
            # API-T05 : erreur imprévue journalisée avec l'identifiant de corrélation,
            # réponse 500 sans trace de pile.
            journaliser(
                "erreur_interne", "erreur", type_exception=type(exc).__name__, chemin=scope["path"]
            )
            if statut_envoye:
                raise
            statut = 500
            await _repondre_json(
                envoyer,
                500,
                {
                    "code": "erreur_interne",
                    "message": "Une erreur inattendue est survenue. Réessaie plus tard.",
                    "details": {"correlation_id": correlation},
                },
            )
        finally:
            if scope["path"].startswith("/api/"):
                journaliser(
                    "requete_http",
                    methode=scope["method"],
                    chemin=scope["path"],
                    statut=statut,
                    duree_ms=round((time.perf_counter() - debut) * 1000),
                    appareil_id=_entete(scope, ENTETE_APPAREIL),
                )
            identifiant_correlation.reset(jeton)


class TailleCorpsMiddleware:
    """Corps limité à 64 Ko, 512 Ko pour /api/sync/push (API-06)."""

    def __init__(self, app: ASGIApp, max_ko: int, max_push_ko: int) -> None:
        self.app = app
        self.max_octets = max_ko * 1024
        self.max_push_octets = max_push_ko * 1024

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] in ("GET", "HEAD", "OPTIONS"):
            await self.app(scope, receive, send)
            return
        limite = self.max_push_octets if scope["path"] == "/api/sync/push" else self.max_octets
        annonce = _entete(scope, "content-length")
        if annonce and annonce.isdigit() and int(annonce) > limite:
            await _repondre_json(
                send,
                413,
                {
                    "code": "requete_trop_grande",
                    "message": "La requête est trop volumineuse.",
                    "details": {"limite_octets": limite},
                },
            )
            return
        recus = 0

        async def recevoir() -> Message:
            nonlocal recus
            message = await receive()
            if message["type"] == "http.request":
                recus += len(message.get("body", b""))
                if recus > limite:
                    raise _CorpsTropGrand()
            return message

        try:
            await self.app(scope, recevoir, send)
        except _CorpsTropGrand:
            await _repondre_json(
                send,
                413,
                {
                    "code": "requete_trop_grande",
                    "message": "La requête est trop volumineuse.",
                    "details": {"limite_octets": limite},
                },
            )


class _CorpsTropGrand(Exception):
    pass


class LimiteDebitMiddleware:
    """60 requêtes par minute et par appareil, hors synchronisation (SEC-12)."""

    def __init__(
        self, app: ASGIApp, limite_par_minute: int, horloge: Callable[[], float] = time.monotonic
    ) -> None:
        self.app = app
        self.limite = limite_par_minute
        self.horloge = horloge
        self.historique: dict[str, deque[float]] = defaultdict(deque)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        chemin = scope.get("path", "")
        if (
            scope["type"] != "http"
            or not chemin.startswith("/api/")
            or chemin.startswith(CHEMINS_SANS_LIMITE)
        ):
            await self.app(scope, receive, send)
            return
        client = scope.get("client") or ("inconnu", 0)
        cle = _entete(scope, ENTETE_APPAREIL) or client[0]
        maintenant = self.horloge()
        fenetre = self.historique[cle]
        while fenetre and maintenant - fenetre[0] >= FENETRE_DEBIT_S:
            fenetre.popleft()
        if len(fenetre) >= self.limite:
            await _repondre_json(
                send,
                429,
                {
                    "code": "limite_requetes",
                    "message": "Trop de requêtes en peu de temps. Patiente une minute.",
                    "details": {},
                },
            )
            return
        fenetre.append(maintenant)
        await self.app(scope, receive, send)
