"""Configuration du backend lue depuis le fichier .env (T-02, CFG-01)."""

from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DOSSIER_BACKEND = Path(__file__).resolve().parents[2]

NOMS_SECRETS = ("database_url", "musixmatch_api_key", "genius_token", "deepl_api_key")


class Parametres(BaseSettings):
    """Paramètres de l'application : annexe 2 et tableau 26.2."""

    model_config = SettingsConfigDict(
        env_file=DOSSIER_BACKEND / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # Annexe 2
    database_url: str = Field(min_length=1)
    musixmatch_api_key: str | None = None
    genius_token: str | None = None
    deepl_api_key: str | None = None
    ollama_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "llama3.1:8b"
    static_dir: str | None = None
    apk_dir: str | None = None
    log_dir: str = "C:/lyrics-vocab/logs"
    backup_dir: str = "C:/lyrics-vocab/sauvegardes"
    quota_musixmatch_jour: int = 2000
    quota_genius_jour: int = 1000
    quota_deepl_mois: int = 500000
    fuseau_pc: str = "Europe/Paris"
    # Notifications Windows d'un mot au hasard (PC de l'utilisateur) et adresse de la PWA
    # ouverte au clic (voir scripts/notifier.ps1).
    notifications_pc: bool = False
    # Compte Tailscale du propriétaire : s'il est renseigné, chaque autre compte Tailscale
    # (amis avec qui le PC est partagé) a sa propre base (voir app/core/locataires.py).
    proprietaire_login: str = ""
    url_application: str = ""
    mode: str = "production"

    # Tableau 26.2
    enrichissement_parallele: int = 2
    enrichissement_reprise_min: int = 10
    recherche_duree_max_s: int = 30
    morceaux_par_artiste: int = 25
    morceaux_repli: int = 10
    http_timeout_s: int = 10
    ia_timeout_s: int = 30
    ia_max_jetons: int = 150
    quota_alerte_pct: int = 80
    disjoncteur_echecs: int = 5
    disjoncteur_pause_min: int = 5
    limite_requetes_min: int = 60
    sync_page: int = 200
    sync_lot: int = 50
    journal_taille_mo: int = 10
    journal_fichiers: int = 14
    sauvegarde_jours: int = 14
    niveau_acquis_jours: int = 21
    intervalle_max_jours: int = 365

    # Paramètres internes (constantes nommées, COD-02)
    pause_entre_appels_ms: int = 200
    attente_base_s: int = 60
    corps_max_ko: int = 64
    corps_max_push_ko: int = 512
    version_client_min: str = "1.0.0"
    verifier_migrations: bool = True

    @field_validator("database_url")
    @classmethod
    def _url_sqlalchemy(cls, valeur: str) -> str:
        """Utilise le pilote psycopg 3 quand l'URL ne précise pas de pilote."""
        if valeur.startswith("postgresql://"):
            return "postgresql+psycopg://" + valeur[len("postgresql://") :]
        if valeur.startswith("postgres://"):
            return "postgresql+psycopg://" + valeur[len("postgres://") :]
        return valeur

    @property
    def en_developpement(self) -> bool:
        """Vrai en mode développement (CORS localhost autorisé, API-11)."""
        return self.mode.lower() in ("dev", "developpement", "development")

    def valeurs_secretes(self) -> list[str]:
        """Liste des valeurs secrètes renseignées, pour les filtrer des journaux."""
        valeurs = []
        for nom in NOMS_SECRETS:
            valeur = getattr(self, nom)
            if valeur:
                valeurs.append(valeur)
                if "@" in valeur and "://" in valeur:
                    identifiants = valeur.split("://", 1)[1].split("@", 1)[0]
                    if ":" in identifiants:
                        valeurs.append(identifiants.split(":", 1)[1])
        return [v for v in valeurs if len(v) >= 4]

    def configuration_publique(self) -> dict:
        """Configuration effective sans les secrets (CFG-02)."""
        donnees = self.model_dump()
        for nom in NOMS_SECRETS:
            donnees[nom] = "renseigné" if donnees.get(nom) else "absent"
        return donnees


@lru_cache
def obtenir_parametres() -> Parametres:
    """Retourne l'instance unique des paramètres (mise en cache)."""
    return Parametres()  # type: ignore[call-arg]
