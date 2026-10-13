"""Notifications d'un mot au hasard à intervalle régulier (voir DECISIONS.md).

Les créneaux tombent sur une grille fixe (début de la plage + k × intervalle) et le mot de
chaque créneau est tiré de façon déterministe : le PC et le téléphone, qui appliquent la même
règle (services/notifications_service.dart), montrent le même mot au même moment.
"""

import asyncio
import subprocess
import sys
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.core.config import DOSSIER_BACKEND
from app.core.logging import journaliser
from app.models import Mot
from app.services import reglages
from app.services.enrichissement import Services

INTERVALLES_MIN = (0, 30, 60, 120, 180, 240, 360)  # 0 : désactivé
ORIGINE = date(2000, 1, 1)
MULTIPLICATEUR = 2654435761
LONGUEUR_TEXTE_MAX = 180
RETARD_TOLERE = timedelta(minutes=2)
VERIFICATION_S = 30
SCRIPT = DOSSIER_BACKEND.parent / "scripts" / "notifier.ps1"


def creneaux_du_jour(jour: date, debut: time, fin: time, intervalle: int) -> list[datetime]:
    """Créneaux de la plage horaire ; une fin avant le début va jusqu'à minuit."""
    if intervalle <= 0:
        return []
    depart = datetime.combine(jour, debut)
    limite = datetime.combine(jour, fin) if fin > debut else datetime.combine(jour, time.max)
    creneaux, t = [], depart
    while t < limite:
        creneaux.append(t)
        t += timedelta(minutes=intervalle)
    return creneaux


def cle(creneau: datetime) -> int:
    """Minutes depuis le 1er janvier 2000 en heure locale (identique en Dart)."""
    return (creneau.date() - ORIGINE).days * 1440 + creneau.hour * 60 + creneau.minute


def indice_mot(cle_creneau: int, intervalle: int, nombre: int) -> int:
    """Mot du créneau ; jamais le même que celui du créneau précédent."""
    if nombre <= 1:
        return 0

    def brut(c: int) -> int:
        return ((c * MULTIPLICATEUR) % 2**32) % nombre

    i = brut(cle_creneau)
    return (i + 1) % nombre if i == brut(cle_creneau - intervalle) else i


def texte_notification(mot: Mot) -> tuple[str, str]:
    """Titre « terme — traduction » et explication (ou traduction) raccourcie."""
    titre = f"{mot.terme} — {mot.traduction_fr}" if mot.traduction_fr else mot.terme
    texte = (mot.explication if mot.source_explication == "ia" else None) or ""
    if len(texte) > LONGUEUR_TEXTE_MAX:
        texte = texte[: LONGUEUR_TEXTE_MAX - 1].rstrip() + "…"
    return titre, texte


def mots_notifiables(session) -> list[Mot]:
    """Mots traduits, dans l'ordre de leur identifiant (même ordre sur le téléphone)."""
    mots = session.scalars(
        select(Mot).where(Mot.deleted_at.is_(None), Mot.traduction_fr.is_not(None))
    ).all()
    return sorted(mots, key=lambda m: str(m.id))


@dataclass
class Notification:
    creneau: datetime
    mot_id: str
    titre: str
    texte: str


def notification_due(session, maintenant: datetime) -> Notification | None:
    """Notification du créneau en cours (arrivé il y a moins de 2 min), sinon None."""
    reglage = reglages.obtenir(session)
    intervalle = reglage.intervalle_notifications_min
    for creneau in creneaux_du_jour(
        maintenant.date(), reglage.notifications_debut, reglage.notifications_fin, intervalle
    ):
        if creneau <= maintenant < creneau + RETARD_TOLERE:
            mots = mots_notifiables(session)
            if not mots:
                return None
            mot = mots[indice_mot(cle(creneau), intervalle, len(mots))]
            titre, texte = texte_notification(mot)
            return Notification(creneau, str(mot.id), titre, texte)
    return None


def afficher(notification: Notification, url_application: str) -> None:
    """Notification Windows (script PowerShell), sans fenêtre de console."""
    subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(SCRIPT),
            "-Titre",
            notification.titre,
            "-Texte",
            notification.texte,
            "-MotId",
            notification.mot_id,
            "-UrlApp",
            url_application,
        ],
        check=False,
        timeout=30,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )


async def boucle(services: Services) -> None:
    """Vérifie toutes les 30 s s'il faut notifier ; un créneau n'est notifié qu'une fois."""
    parametres = services.parametres
    if not parametres.notifications_pc or sys.platform != "win32" or not Path(SCRIPT).exists():
        return
    fuseau = ZoneInfo(parametres.fuseau_pc)
    deja: datetime | None = None
    while True:
        try:
            maintenant = datetime.now(fuseau).replace(tzinfo=None)
            with services.fabrique() as session:
                notification = notification_due(session, maintenant)
            if notification is not None and notification.creneau != deja:
                deja = notification.creneau
                await asyncio.to_thread(afficher, notification, parametres.url_application)
                journaliser("notification_pc", mot_id=notification.mot_id)
        except Exception as exc:
            journaliser("notification_pc_echec", "avertissement", erreur=type(exc).__name__)
        await asyncio.sleep(VERIFICATION_S)
