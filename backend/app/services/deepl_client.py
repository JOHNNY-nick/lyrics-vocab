"""Client DeepL (38.3) : traduction EN → FR et FR → EN."""

from app.core.errors import QuotaDepasse
from app.services.types_externes import ClientExterne, RefusService, verifier_statut_http

ADRESSE_DEEPL_GRATUIT = "https://api-free.deepl.com/v2/translate"
ADRESSE_DEEPL_PRO = "https://api.deepl.com/v2/translate"
SUFFIXE_CLE_GRATUITE = ":fx"
STATUT_QUOTA = 456
STATUTS_INDISPONIBLES = (401, 403)


class DeeplClient(ClientExterne):
    """Accès à l'API DeepL ; seul le texte à traduire est envoyé (SEC-04)."""

    service = "deepl"
    code_indisponible = "deepl_indisponible"

    def __init__(self, cle: str | None, *args, adresse: str | None = None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.cle = cle
        if adresse is None:
            gratuite = not cle or cle.endswith(SUFFIXE_CLE_GRATUITE)
            adresse = ADRESSE_DEEPL_GRATUIT if gratuite else ADRESSE_DEEPL_PRO
        self.adresse = adresse

    @property
    def configure(self) -> bool:
        """Vrai si une clé est renseignée."""
        return bool(self.cle)

    async def traduire(
        self, texte: str, contexte: str | None = None, source: str = "EN", cible: str = "FR"
    ) -> str | None:
        """Traduction du texte ; None si DeepL renvoie une traduction vide (CL-12)."""
        if not self.cle:
            raise self._indisponible()
        corps: dict = {"text": [texte], "source_lang": source, "target_lang": cible}
        if contexte:
            corps["context"] = contexte

        async def appel() -> str | None:
            reponse = await self.http.post(
                self.adresse, json=corps, headers={"Authorization": f"DeepL-Auth-Key {self.cle}"}
            )
            if reponse.status_code == STATUT_QUOTA:
                raise QuotaDepasse(details={"api": self.service})
            verifier_statut_http(reponse)
            if reponse.status_code in STATUTS_INDISPONIBLES:
                raise RefusService(f"HTTP {reponse.status_code}")
            reponse.raise_for_status()
            traductions = reponse.json().get("translations", [])
            if not traductions:
                return None
            resultat = (traductions[0].get("text") or "").strip()
            return resultat or None

        return await self.appeler("translate", appel, caracteres=len(texte))
