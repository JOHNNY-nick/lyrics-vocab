"""Plusieurs utilisateurs : une base PostgreSQL par compte Tailscale (voir DECISIONS.md).

`tailscale serve` ajoute à chaque requête l'en-tête Tailscale-User-Login (compte de
l'appareil, impossible à falsifier : la valeur envoyée par le client est remplacée) et le
backend n'écoute que 127.0.0.1. Le propriétaire (PROPRIETAIRE_LOGIN, ou une requête sans
en-tête : scripts locaux) utilise la base d'origine ; chaque autre compte obtient sa propre
base, créée et migrée à sa première requête. Requêtes, synchronisation et tâches de fond
restent donc inchangées : seule la base change.
"""

import asyncio
import hashlib
import json
import threading
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from pathlib import Path

from alembic import command
from alembic.config import Config
from fastapi import Request
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session, sessionmaker

from app.core.codes_acces import EN_TETE_CODE, EN_TETE_TUNNEL
from app.core.config import DOSSIER_BACKEND, Parametres
from app.core.database import creer_fabrique, creer_moteur
from app.core.logging import journaliser
from app.services.enrichissement import GestionnaireEnrichissement, Services

EN_TETE_COMPTE = "tailscale-user-login"
SUFFIXE = "_u_"
COMPTE_ANONYME = "tunnel:anonyme"
CONNEXIONS_AMI = 1
CONNEXIONS_AMI_SUP = 4


@dataclass
class Locataire:
    """Base d'un utilisateur et ses services."""

    base: str
    fabrique: sessionmaker[Session]
    services: Services
    gestionnaire: GestionnaireEnrichissement


def compte(request: Request) -> str | None:
    """Compte de la requête (minuscules) : celui du code d'invitation pour le tunnel
    Cloudflare (l'en-tête Tailscale y est ignoré, il n'est pas fiable), sinon le compte
    Tailscale ; None pour une requête locale."""
    if EN_TETE_TUNNEL in request.headers:
        codes = getattr(request.app.state, "codes_acces", None)
        trouve = codes.compte(request.headers.get(EN_TETE_CODE)) if codes else None
        return trouve.strip().lower() if trouve else COMPTE_ANONYME
    valeur = request.headers.get(EN_TETE_COMPTE)
    return valeur.strip().lower()[:320] if valeur and valeur.strip() else None


def base_du_compte(principale: str, login: str) -> str:
    """Nom de la base d'un compte (autre que le propriétaire)."""
    empreinte = hashlib.sha256(login.strip().lower().encode()).hexdigest()[:12]
    return f"{principale}{SUFFIXE}{empreinte}"


def inscrire(fichier: str | None, base: str, login: str) -> None:
    """Note le compte d'une base dans le registre (les noms de base sont des empreintes)."""
    if not fichier:
        return
    chemin = Path(fichier)
    try:
        registre = json.loads(chemin.read_text(encoding="utf-8")) if chemin.exists() else {}
    except (OSError, ValueError):
        registre = {}
    if base in registre:
        return
    registre[base] = {"compte": login, "cree_le": datetime.now(UTC).isoformat(timespec="seconds")}
    chemin.parent.mkdir(parents=True, exist_ok=True)
    chemin.write_text(json.dumps(registre, indent=2, ensure_ascii=False), encoding="utf-8")


def config_alembic(url: str) -> Config:
    config = Config(str(DOSSIER_BACKEND / "alembic.ini"))
    config.set_main_option("script_location", str(DOSSIER_BACKEND / "migrations"))
    config.set_main_option("sqlalchemy.url", url.replace("%", "%%"))
    return config


JOURS_GARDES = 30


class Connexions:
    """Dernières connexions par base (page /admin), gardées en mémoire et enregistrées
    régulièrement dans un fichier JSON : date, voie (tunnel, Tailscale, PC), pays, appareils,
    nombre de requêtes par jour."""

    def __init__(self, fichier: str | None):
        self.fichier = Path(fichier) if fichier else None
        self._verrou = threading.Lock()
        self._modifie = False
        self.donnees: dict[str, dict] = {}
        if self.fichier and self.fichier.exists():
            try:
                self.donnees = json.loads(self.fichier.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                self.donnees = {}

    def noter(self, base: str, request: Request) -> None:
        maintenant = datetime.now(UTC)
        entetes = request.headers
        if EN_TETE_TUNNEL in entetes:
            voie = "tunnel"
        elif EN_TETE_COMPTE in entetes:
            voie = "tailscale"
        else:
            voie = "pc"
        appareil = (entetes.get("x-appareil-id") or "")[:64]
        with self._verrou:
            fiche = self.donnees.setdefault(
                base, {"premiere": maintenant.isoformat(timespec="seconds"), "jours": {}}
            )
            fiche["derniere"] = maintenant.isoformat(timespec="seconds")
            fiche["voie"] = voie
            fiche["pays"] = entetes.get("cf-ipcountry") or fiche.get("pays")
            fiche["ip"] = request.client.host if request.client else None
            if appareil:
                appareils = fiche.setdefault("appareils", {})
                appareils[appareil] = maintenant.isoformat(timespec="seconds")
            jour = maintenant.date().isoformat()
            jours = fiche.setdefault("jours", {})
            jours[jour] = jours.get(jour, 0) + 1
            for ancien in sorted(jours)[:-JOURS_GARDES]:
                del jours[ancien]
            fiche["requetes"] = fiche.get("requetes", 0) + 1
            self._modifie = True

    def fiche(self, base: str) -> dict:
        with self._verrou:
            return json.loads(json.dumps(self.donnees.get(base, {})))

    def oublier(self, base: str) -> None:
        with self._verrou:
            if self.donnees.pop(base, None) is not None:
                self._modifie = True

    def enregistrer(self) -> None:
        if not self.fichier:
            return
        with self._verrou:
            if not self._modifie:
                return
            contenu = json.dumps(self.donnees, indent=1, ensure_ascii=False)
            self._modifie = False
        self.fichier.parent.mkdir(parents=True, exist_ok=True)
        self.fichier.write_text(contenu, encoding="utf-8")


class Locataires:
    """Répartit les requêtes entre la base du propriétaire et celles des autres comptes."""

    def __init__(
        self,
        parametres: Parametres,
        principal: Locataire,
        demarrer_taches: bool,
        boucle: asyncio.AbstractEventLoop | None = None,
    ):
        self.parametres = parametres
        self.boucle = boucle
        self.principal = principal
        self.demarrer_taches = demarrer_taches
        self.url = make_url(parametres.database_url)
        self._locataires: dict[str, Locataire] = {principal.base: principal}
        self._verrou = threading.Lock()
        self.connexions = Connexions(parametres.connexions_fichier)

    @property
    def actif(self) -> bool:
        """Plusieurs utilisateurs seulement si le propriétaire est déclaré."""
        return bool(self.parametres.proprietaire_login)

    def nom_base(self, login: str | None) -> str:
        if (
            not self.actif
            or login is None
            or login == self.parametres.proprietaire_login.strip().lower()
        ):
            return self.principal.base
        return base_du_compte(self.principal.base, login)

    def pour(self, login: str | None) -> Locataire:
        """Locataire du compte ; crée et migre sa base à la première requête."""
        base = self.nom_base(login)
        locataire = self._locataires.get(base)
        if locataire is not None:
            return locataire
        with self._verrou:
            if base not in self._locataires:
                self._creer_base(base)
                self._locataires[base] = self._ouvrir(base)
                inscrire(self.parametres.registre_utilisateurs_fichier, base, login or "")
                journaliser("utilisateur_nouveau", base=base)
        return self._locataires[base]

    def depuis_requete(self, request: Request) -> Locataire:
        login = compte(request)
        if login == COMPTE_ANONYME:
            # Tunnel sans code : seul /api/health passe le filtre ; aucune base créée.
            return self.principal
        locataire = self.pour(login)
        # Base cherchée plusieurs fois par requête (session, services) : comptée une fois.
        if not getattr(request.state, "connexion_notee", False):
            request.state.connexion_notee = True
            self.connexions.noter(locataire.base, request)
        return locataire

    def tous(self) -> list[Locataire]:
        """Le propriétaire et tous les utilisateurs déjà créés (tâches de fond)."""
        with self._verrou:
            existantes = self._bases_existantes()
            for base in existantes:
                if base not in self._locataires:
                    self._locataires[base] = self._ouvrir(base)
            # Base supprimée (scripts/utilisateurs.py supprimer) : oubliée ici aussi.
            for base in [b for b in self._locataires if b != self.principal.base]:
                if base not in existantes:
                    oublie = self._locataires.pop(base)
                    oublie.fabrique.kw["bind"].dispose()
            return list(self._locataires.values())

    # --- Bases PostgreSQL ------------------------------------------------------------------

    def _url_base(self, base: str) -> str:
        return self.url.set(database=base).render_as_string(hide_password=False)

    def _administration(self):
        return create_engine(self._url_base("postgres"), isolation_level="AUTOCOMMIT")

    def _bases_existantes(self) -> list[str]:
        if not self.actif:
            return []
        moteur = self._administration()
        try:
            with moteur.connect() as connexion:
                lignes = connexion.execute(
                    text("SELECT datname FROM pg_database WHERE datname LIKE :motif"),
                    {"motif": f"{self.principal.base}{SUFFIXE}%"},
                ).scalars()
                return sorted(lignes)
        finally:
            moteur.dispose()

    def _creer_base(self, base: str) -> None:
        moteur = self._administration()
        try:
            with moteur.connect() as connexion:
                existe = connexion.execute(
                    text("SELECT 1 FROM pg_database WHERE datname = :b"), {"b": base}
                ).scalar()
                if not existe:
                    connexion.execute(text(f'CREATE DATABASE "{base}"'))
        finally:
            moteur.dispose()
        command.upgrade(config_alembic(self._url_base(base)), "head")

    def migrer_tous(self) -> None:
        """Au démarrage : les bases des utilisateurs suivent les migrations (base principale :
        « alembic upgrade head » manuel, voir README)."""
        for base in self._bases_existantes():
            command.upgrade(config_alembic(self._url_base(base)), "head")

    def _ouvrir(self, base: str) -> Locataire:
        # Une connexion gardée ouverte par ami (4 de plus au besoin) : PostgreSQL en accepte 100
        # en tout ; la base du propriétaire en garde 5.
        moteur = creer_moteur(
            self._url_base(base), pool_size=CONNEXIONS_AMI, max_overflow=CONNEXIONS_AMI_SUP
        )
        fabrique = creer_fabrique(moteur)
        services = replace(self.principal.services, fabrique=fabrique)
        gestionnaire = GestionnaireEnrichissement(services)
        if self.demarrer_taches and self.boucle is not None:
            # Les requêtes arrivent dans des fils de travail : les tâches d'enrichissement de
            # l'utilisateur démarrent dans la boucle asyncio du serveur.
            def lancer() -> None:
                gestionnaire.demarrer()
                gestionnaire.reprendre(au_demarrage=True)

            self.boucle.call_soon_threadsafe(lancer)
        return Locataire(base, fabrique, services, gestionnaire)

    def fermer_bases_de_test(self) -> None:
        """Tests : supprime les bases des utilisateurs créées pendant la session."""
        for base, locataire in list(self._locataires.items()):
            if base == self.principal.base:
                continue
            locataire.fabrique.kw["bind"].dispose()
            moteur = self._administration()
            try:
                with moteur.connect() as connexion:
                    connexion.execute(text(f'DROP DATABASE IF EXISTS "{base}" WITH (FORCE)'))
            finally:
                moteur.dispose()
            del self._locataires[base]
