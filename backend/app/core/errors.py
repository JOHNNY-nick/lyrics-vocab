"""Exceptions typées et conversion en réponses d'erreur à un seul endroit (T-06, API-07, COD-04)."""

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import identifiant_correlation, journaliser


class ErreurApi(Exception):
    """Erreur applicative avec un code stable et un message en français."""

    code = "erreur_interne"
    statut_http = 500
    message_defaut = "Une erreur inattendue est survenue."

    def __init__(
        self,
        message: str | None = None,
        details: dict[str, Any] | None = None,
        code: str | None = None,
        statut_http: int | None = None,
    ) -> None:
        self.message = message or self.message_defaut
        self.details = details or {}
        if code:
            self.code = code
        if statut_http:
            self.statut_http = statut_http
        super().__init__(self.message)

    def corps(self) -> dict[str, Any]:
        """Corps JSON de l'erreur : {code, message, details}."""
        return {"code": self.code, "message": self.message, "details": self.details}


class TermeInvalide(ErreurApi):
    code, statut_http = "terme_invalide", 422
    message_defaut = "Saisis un mot ou une expression de 1 à 6 mots."


class MotIntrouvable(ErreurApi):
    code, statut_http = "mot_introuvable", 404
    message_defaut = "Ce mot est introuvable."


class RevisionIntrouvable(ErreurApi):
    code, statut_http = "revision_introuvable", 404
    message_defaut = "Cette révision est introuvable."


class RevisionDejaRepondue(ErreurApi):
    code, statut_http = "revision_deja_repondue", 409
    message_defaut = "Cette révision a déjà reçu une réponse."


class QuotaDepasse(ErreurApi):
    code, statut_http = "quota_depasse", 429
    message_defaut = "Limite journalière atteinte pour ce service. Réessaie demain."


class LimiteRequetes(ErreurApi):
    code, statut_http = "limite_requetes", 429
    message_defaut = "Trop de requêtes en peu de temps. Patiente une minute."


class ServiceIndisponible(ErreurApi):
    code, statut_http = "service_indisponible", 503
    message_defaut = "Le service externe ne répond pas pour le moment."


class IaIndisponible(ErreurApi):
    code, statut_http = "ia_indisponible", 503
    message_defaut = "L'exercice n'est pas disponible pour le moment."


class OperationInconnue(ErreurApi):
    code, statut_http = "operation_inconnue", 400
    message_defaut = "Type d'opération de synchronisation inconnu."


class CurseurInvalide(ErreurApi):
    code, statut_http = "curseur_invalide", 400
    message_defaut = "Curseur de synchronisation inconnu du serveur."


class ParametreInvalide(ErreurApi):
    code, statut_http = "parametre_invalide", 422
    message_defaut = "Un paramètre de la requête est invalide."


class ReponseInvalide(ErreurApi):
    code, statut_http = "reponse_invalide", 422
    message_defaut = "Indique une note ou un verdict pour cette réponse."


class RequeteTropGrande(ErreurApi):
    code, statut_http = "requete_trop_grande", 413
    message_defaut = "La requête est trop volumineuse."


class BaseIndisponible(ErreurApi):
    code, statut_http = "base_indisponible", 503
    message_defaut = "La base de données ne répond pas."


def reponse_erreur(erreur: ErreurApi) -> JSONResponse:
    """Construit la réponse JSON d'une erreur applicative."""
    return JSONResponse(status_code=erreur.statut_http, content=erreur.corps())


def _champs_en_erreur(exc: RequestValidationError) -> list[str]:
    champs = []
    for erreur in exc.errors():
        emplacement = [str(x) for x in erreur.get("loc", ()) if x not in ("body", "query", "path")]
        if emplacement:
            champs.append(".".join(emplacement))
    return champs


def installer_gestionnaires(app: FastAPI) -> None:
    """Convertit ErreurApi, les erreurs de validation et les exceptions imprévues."""

    @app.exception_handler(ErreurApi)
    async def _erreur_api(_: Request, exc: ErreurApi) -> JSONResponse:
        if exc.statut_http >= 500:
            journaliser("erreur_api", "erreur", code=exc.code)
        return reponse_erreur(exc)

    @app.exception_handler(RequestValidationError)
    async def _validation(request: Request, exc: RequestValidationError) -> JSONResponse:
        champs = _champs_en_erreur(exc)
        if any(c.split(".")[0] == "terme" for c in champs):
            erreur: ErreurApi = TermeInvalide(details={"champ": "terme"})
        elif request.url.path.endswith("/reponse") and any(
            c.split(".")[0] in ("qualite", "verdict") for c in champs
        ):
            erreur = ReponseInvalide(details={"champs": champs})
        else:
            erreur = ParametreInvalide(details={"champs": champs})
        return reponse_erreur(erreur)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        codes = {
            400: ("requete_invalide", "La requête est mal formée."),
            404: ("introuvable", "Ressource introuvable."),
            405: ("methode_non_autorisee", "Méthode non autorisée."),
        }
        code, message = codes.get(exc.status_code, ("erreur_http", "Requête refusée."))
        return JSONResponse(
            status_code=exc.status_code, content={"code": code, "message": message, "details": {}}
        )

    @app.exception_handler(Exception)
    async def _imprevue(_: Request, exc: Exception) -> JSONResponse:
        journaliser(
            "erreur_interne",
            "erreur",
            type_exception=type(exc).__name__,
            correlation=identifiant_correlation.get(),
        )
        return JSONResponse(
            status_code=500,
            content={
                "code": "erreur_interne",
                "message": "Une erreur inattendue est survenue. Réessaie plus tard.",
                "details": {"correlation_id": identifiant_correlation.get()},
            },
        )
