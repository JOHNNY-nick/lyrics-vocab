"""Gestion des utilisateurs invités : liste, codes d'invitation, retrait, suppression.

Partagé par la page /admin (app/routers/admin.py) et la commande scripts/utilisateurs.py.
Un ami invité par code a le compte « invite:<prénom> » ; un ami venu par Tailscale, son
adresse e-mail. Chaque compte a sa base (app/core/locataires.py).
"""

import json
from dataclasses import asdict, dataclass
from pathlib import Path

from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

from app.core.codes_acces import (
    compte_invite,
    ecrire_codes,
    empreinte,
    lire_codes,
    nouveau_code,
)
from app.core.config import Parametres
from app.core.errors import ErreurApi
from app.core.locataires import SUFFIXE, base_du_compte

LONGUEUR_PRENOM_MAX = 40


class GestionImpossible(ErreurApi):
    code, statut_http = "gestion_impossible", 422
    message_defaut = "Opération impossible."


@dataclass
class Utilisateur:
    """Ligne de la liste des utilisateurs."""

    nom: str
    compte: str
    acces: str  # proprietaire, code, tailscale, retire, inconnu
    mots: int
    revisions: int
    derniere_activite: str | None
    connecte: bool
    base: str | None = None

    def en_dict(self) -> dict:
        return asdict(self)


def nom_affiche(compte: str) -> str:
    return compte.split(":", 1)[1].capitalize() if compte.startswith("invite:") else compte


class GestionUtilisateurs:
    def __init__(self, parametres: Parametres) -> None:
        self.p = parametres
        if not parametres.codes_acces_fichier:
            raise GestionImpossible("CODES_ACCES_FICHIER n'est pas renseigné dans backend/.env.")
        self.url = make_url(parametres.database_url)
        self.principale = self.url.database
        self.proprietaire = parametres.proprietaire_login.strip().lower()

    # --- Données ---------------------------------------------------------------------------

    def codes(self) -> dict[str, str]:
        return lire_codes(self.p.codes_acces_fichier)

    def registre(self) -> dict:
        fichier = self.p.registre_utilisateurs_fichier
        if fichier and Path(fichier).exists():
            return json.loads(Path(fichier).read_text(encoding="utf-8"))
        return {}

    def _ecrire_registre(self, registre: dict) -> None:
        fichier = self.p.registre_utilisateurs_fichier
        if fichier:
            Path(fichier).write_text(
                json.dumps(registre, indent=2, ensure_ascii=False), encoding="utf-8"
            )

    def _moteur(self, base: str):
        url = self.url.set(database=base).render_as_string(hide_password=False)
        return create_engine(url, isolation_level="AUTOCOMMIT")

    def _bases(self) -> list[str]:
        moteur = self._moteur("postgres")
        try:
            with moteur.connect() as c:
                return list(
                    c.execute(
                        text("SELECT datname FROM pg_database WHERE datname LIKE :m ORDER BY 1"),
                        {"m": f"{self.principale}{SUFFIXE}%"},
                    ).scalars()
                )
        finally:
            moteur.dispose()

    def _statistiques(self, base: str) -> tuple[int, int, str | None]:
        moteur = self._moteur(base)
        try:
            with moteur.connect() as c:
                mots = c.execute(text("SELECT count(*) FROM mot WHERE deleted_at IS NULL")).scalar()
                faites = c.execute(
                    text("SELECT count(*) FROM revision WHERE statut = 'faite'")
                ).scalar()
                derniere = c.execute(
                    text(
                        "SELECT max(t) FROM (SELECT max(updated_at) t FROM mot "
                        "UNION ALL SELECT max(updated_at) FROM revision) x"
                    )
                ).scalar()
        finally:
            moteur.dispose()
        return mots or 0, faites or 0, derniere.isoformat() if derniere else None

    def compte_de(self, nom: str) -> str:
        """Prénom (ami invité par code) ou adresse e-mail (ami venu par Tailscale)."""
        nom = nom.strip()
        if not nom or len(nom) > LONGUEUR_PRENOM_MAX * 8:
            raise GestionImpossible("Indique un prénom.")
        return nom.lower() if "@" in nom or nom.startswith("invite:") else compte_invite(nom)

    def _comptes_connus(self) -> dict[str, str]:
        connus = {b: v.get("compte", "") for b, v in self.registre().items()}
        for compte in set(self.codes().values()):
            if compte != self.proprietaire:
                connus.setdefault(base_du_compte(self.principale, compte), compte)
        return connus

    # --- Opérations ------------------------------------------------------------------------

    def liste(self) -> list[Utilisateur]:
        codes = set(self.codes().values())
        connus = self._comptes_connus()
        mots, faites, derniere = self._statistiques(self.principale)
        lignes = [
            Utilisateur(
                "Toi",
                self.proprietaire,
                "proprietaire",
                mots,
                faites,
                derniere,
                True,
                self.principale,
            )
        ]
        vues = set()
        for base in self._bases():
            compte = connus.get(base, "")
            vues.add(base)
            if compte.startswith("invite:"):
                acces = "code" if compte in codes else "retire"
            elif compte:
                acces = "tailscale"
            else:
                acces = "inconnu"
            mots, faites, derniere = self._statistiques(base)
            nom = nom_affiche(compte) if compte else base
            lignes.append(Utilisateur(nom, compte, acces, mots, faites, derniere, True, base))
        for compte in sorted(codes):
            if compte.startswith("invite:") and base_du_compte(self.principale, compte) not in vues:
                lignes.append(Utilisateur(nom_affiche(compte), compte, "code", 0, 0, None, False))
        return lignes

    def inviter(self, nom: str, proprietaire: bool = False) -> str:
        """Nouveau code (le compte garde sa bibliothèque s'il en avait déjà une)."""
        compte = self.proprietaire if proprietaire else self.compte_de(nom)
        if "@" in compte and compte != self.proprietaire:
            raise GestionImpossible(
                "Les amis venus par Tailscale n'ont pas besoin de code : indique un prénom."
            )
        codes = self.codes()
        code = nouveau_code()
        codes[empreinte(code)] = compte
        ecrire_codes(self.p.codes_acces_fichier, codes)
        return code

    def retirer(self, nom: str) -> int:
        """Supprime les codes du compte ; retourne le nombre de codes retirés."""
        compte = self.compte_de(nom)
        codes = self.codes()
        restants = {k: v for k, v in codes.items() if v != compte}
        ecrire_codes(self.p.codes_acces_fichier, restants)
        return len(codes) - len(restants)

    def supprimer(self, nom: str) -> None:
        """Retire l'accès et efface la base du compte (irréversible, sauf sauvegardes)."""
        compte = self.compte_de(nom)
        if compte == self.proprietaire:
            raise GestionImpossible("Impossible de supprimer ta propre bibliothèque.")
        self.retirer(nom)
        base = base_du_compte(self.principale, compte)
        moteur = self._moteur("postgres")
        try:
            with moteur.connect() as c:
                c.execute(text(f'DROP DATABASE IF EXISTS "{base}" WITH (FORCE)'))
        finally:
            moteur.dispose()
        registre = self.registre()
        if registre.pop(base, None) is not None:
            self._ecrire_registre(registre)

    # --- Fiche détaillée -------------------------------------------------------------------

    def base_de(self, compte: str) -> str:
        compte = compte.strip().lower()
        return (
            self.principale
            if compte == self.proprietaire
            else base_du_compte(self.principale, compte)
        )

    def details(self, compte: str) -> dict:
        """Toutes les informations connues d'un utilisateur (page /admin)."""
        compte = compte.strip().lower()
        base = self.base_de(compte)
        if base != self.principale and base not in self._bases():
            raise GestionImpossible("Cet utilisateur ne s'est pas encore connecté.")
        codes = self.codes()
        inscription = self.registre().get(base, {})
        moteur = self._moteur(base)

        def lignes(c, sql: str, **params) -> list[dict]:
            return [dict(r._mapping) for r in c.execute(text(sql), params)]

        def un(c, sql: str, **params):
            return c.execute(text(sql), params).scalar()

        try:
            with moteur.connect() as c:
                bibliotheque = {
                    "mots": un(c, "SELECT count(*) FROM mot WHERE deleted_at IS NULL"),
                    "supprimes": un(c, "SELECT count(*) FROM mot WHERE deleted_at IS NOT NULL"),
                    "par_niveau": {
                        r["niveau"]: r["n"]
                        for r in lignes(
                            c,
                            "SELECT niveau, count(*) n FROM mot WHERE deleted_at IS NULL "
                            "GROUP BY niveau",
                        )
                    },
                    "par_statut": {
                        r["statut_enrichissement"]: r["n"]
                        for r in lignes(
                            c,
                            "SELECT statut_enrichissement, count(*) n FROM mot "
                            "WHERE deleted_at IS NULL GROUP BY statut_enrichissement",
                        )
                    },
                    "avec_explication": un(
                        c,
                        "SELECT count(*) FROM mot WHERE deleted_at IS NULL "
                        "AND source_explication = 'ia'",
                    ),
                    "avec_exemples": un(
                        c,
                        "SELECT count(*) FROM mot WHERE deleted_at IS NULL "
                        "AND exemples IS NOT NULL AND jsonb_array_length(exemples) > 0",
                    ),
                    "extraits": un(c, "SELECT count(*) FROM extrait WHERE deleted_at IS NULL"),
                    "extraits_hors_liste": un(
                        c,
                        "SELECT count(*) FROM extrait WHERE deleted_at IS NULL AND hors_liste",
                    ),
                    "premier_ajout": un(c, "SELECT min(created_at) FROM mot"),
                    "dernier_ajout": un(c, "SELECT max(created_at) FROM mot"),
                    "derniers_mots": lignes(
                        c,
                        "SELECT terme, traduction_fr, niveau, statut_enrichissement, nb_echecs, "
                        "created_at FROM mot WHERE deleted_at IS NULL "
                        "ORDER BY created_at DESC LIMIT 30",
                    ),
                    "plus_rates": lignes(
                        c,
                        "SELECT terme, traduction_fr, nb_echecs FROM mot WHERE deleted_at IS NULL "
                        "AND nb_echecs > 0 ORDER BY nb_echecs DESC, terme LIMIT 5",
                    ),
                }
                jours_revises = [
                    r["jour"]
                    for r in lignes(
                        c,
                        "SELECT DISTINCT (repondu_le AT TIME ZONE 'UTC')::date jour FROM revision "
                        "WHERE statut = 'faite' AND repondu_le IS NOT NULL ORDER BY jour DESC",
                    )
                ]
                revisions = {
                    "faites": un(c, "SELECT count(*) FROM revision WHERE statut = 'faite'"),
                    "faites_7_jours": un(
                        c,
                        "SELECT count(*) FROM revision WHERE statut = 'faite' "
                        "AND repondu_le > now() - interval '7 days'",
                    ),
                    "reussies": un(
                        c,
                        "SELECT count(*) FROM revision WHERE statut = 'faite' AND qualite >= 3",
                    ),
                    "dues": un(
                        c,
                        "SELECT count(*) FROM revision WHERE statut = 'planifiee' "
                        "AND deleted_at IS NULL AND date_prevue <= current_date",
                    ),
                    "en_retard": un(
                        c,
                        "SELECT count(*) FROM revision WHERE statut = 'planifiee' "
                        "AND deleted_at IS NULL AND date_prevue < current_date",
                    ),
                    "prochaine": un(
                        c,
                        "SELECT min(date_prevue) FROM revision WHERE statut = 'planifiee' "
                        "AND deleted_at IS NULL AND date_prevue > current_date",
                    ),
                    "par_mode": {
                        r["mode"]: r["n"]
                        for r in lignes(
                            c,
                            "SELECT mode, count(*) n FROM revision WHERE statut = 'faite' "
                            "GROUP BY mode",
                        )
                    },
                    "verdicts": {
                        r["verdict"]: r["n"]
                        for r in lignes(
                            c,
                            "SELECT verdict, count(*) n FROM revision WHERE verdict IS NOT NULL "
                            "GROUP BY verdict",
                        )
                    },
                    "derniere": un(c, "SELECT max(repondu_le) FROM revision"),
                    "jours_actifs": len(jours_revises),
                    "serie": _serie(jours_revises),
                    "dernieres_reponses": lignes(
                        c,
                        "SELECT m.terme, r.mode, r.verdict, r.qualite, r.reponse_utilisateur, "
                        "r.repondu_le FROM revision r JOIN mot m ON m.id = r.mot_id "
                        "WHERE r.statut = 'faite' ORDER BY r.repondu_le DESC NULLS LAST LIMIT 10",
                    ),
                }
                reglage = lignes(
                    c,
                    "SELECT intervalle_notifications_min, notifications_debut, notifications_fin, "
                    "mots_par_session, mode_revision, heure_changement_jour, sync_wifi_seulement, "
                    "created_at, updated_at FROM reglage LIMIT 1",
                )
                artistes = lignes(
                    c,
                    "SELECT nom, rang FROM artiste WHERE est_prefere AND deleted_at IS NULL "
                    "ORDER BY rang",
                )
                appareils = lignes(
                    c,
                    "SELECT appareil_id, count(*) operations, max(applique_le) derniere "
                    "FROM sync_op GROUP BY appareil_id ORDER BY derniere DESC",
                )
                taille = un(c, "SELECT pg_database_size(current_database())")
        finally:
            moteur.dispose()
        if compte == self.proprietaire:
            acces = "proprietaire"
        elif compte.startswith("invite:"):
            acces = "code" if compte in codes.values() else "retire"
        else:
            acces = "tailscale"
        return _json(
            {
                "nom": "Toi" if acces == "proprietaire" else nom_affiche(compte),
                "compte": compte,
                "base": base,
                "acces": acces,
                "codes_actifs": sum(1 for v in codes.values() if v == compte),
                # Bases créées avant le registre : date de création de leurs réglages.
                "cree_le": inscription.get("cree_le")
                or (reglage[0]["created_at"] if reglage else None),
                "taille_octets": taille,
                "bibliotheque": bibliotheque,
                "revisions": revisions,
                "reglages": reglage[0] if reglage else {},
                "artistes": artistes,
                "appareils_synchronises": appareils,
            }
        )


def _serie(jours: list) -> int:
    """Jours consécutifs de révision jusqu'à aujourd'hui (ou hier)."""
    from datetime import date, timedelta

    if not jours:
        return 0
    attendu = date.today()
    if jours[0] < attendu - timedelta(days=1):
        return 0
    if jours[0] == attendu - timedelta(days=1):
        attendu = jours[0]
    serie = 0
    for jour in jours:
        if jour == attendu:
            serie += 1
            attendu -= timedelta(days=1)
        elif jour < attendu:
            break
    return serie


def _json(valeur):
    """Dates et heures en texte ISO (réponse JSON)."""
    from datetime import date, datetime, time

    if isinstance(valeur, dict):
        return {k: _json(v) for k, v in valeur.items()}
    if isinstance(valeur, list):
        return [_json(v) for v in valeur]
    if isinstance(valeur, datetime | date | time):
        return valeur.isoformat()
    return valeur
