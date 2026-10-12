"""Pipeline d'enrichissement d'un mot et tâches de fond (D.1, 39.1, ENR-01 à ENR-08)."""

import asyncio
import time
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from sqlalchemy import or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Parametres
from app.core.errors import ErreurApi, IaIndisponible, QuotaDepasse, ServiceIndisponible
from app.core.logging import journaliser
from app.models import Artiste, Extrait, Morceau, Mot
from app.services import ai_explainer, artistes
from app.services.ai_traduction import traduire_par_ia
from app.services.deepl_client import DeeplClient
from app.services.deezer_client import DeezerClient
from app.services.extraction import ExtraitDecoupe, extraire
from app.services.genius_client import GeniusClient
from app.services.lrclib_client import LrclibClient
from app.services.musixmatch_client import MusixmatchClient
from app.services.ollama_client import OllamaClient
from app.services.types_externes import MorceauExterne

EXTRAITS_MAX = 3
REPLI_DUREE_MAX_S = 10
LONGUEUR_MAX_TRADUCTION = 200
NOUVELLE_RECHERCHE_JOURS = 7
DELAI_RELANCE_IA_S = 60
REPRISES_PAR_SYNC = 20
STATUTS_FINAUX = ("ok", "partiel", "echec")


@dataclass
class Services:
    """Dépendances de l'enrichissement, injectées pour les tests (COD-03)."""

    parametres: Parametres
    fabrique: sessionmaker[Session]
    # Source de paroles : Musixmatch si une clé est configurée, sinon LRCLIB (sans clé).
    paroles: MusixmatchClient | LrclibClient
    # Recherche d'artistes : Genius si un jeton est configuré, sinon Deezer (sans clé).
    genius: GeniusClient | DeezerClient
    deepl: DeeplClient
    ollama: OllamaClient
    compteur: object
    dormir: object = field(default=asyncio.sleep)


@dataclass
class Trouvaille:
    """Extrait trouvé et son origine."""

    extrait: ExtraitDecoupe
    morceau: MorceauExterne
    artiste_id: uuid.UUID | None
    hors_liste: bool


@dataclass
class Recherche:
    """Résultat d'une recherche d'extraits."""

    trouvailles: list[Trouvaille] = field(default_factory=list)
    code_erreur: str | None = None


def _code(exc: Exception, service: str) -> str:
    if isinstance(exc, QuotaDepasse):
        return f"{service}_quota"
    if isinstance(exc, (asyncio.TimeoutError, TimeoutError)):
        return "delai_depasse"
    return f"{service}_indisponible"


async def _chercher_dans(
    services: Services,
    recherche: Recherche,
    terme: str,
    morceaux: list[tuple[MorceauExterne, uuid.UUID | None]],
    hors_liste: bool,
    echeance: float,
) -> bool:
    """Parcourt les morceaux ; retourne faux si la source est indisponible ou épuisée."""
    for morceau, artiste_id in morceaux:
        if len(recherche.trouvailles) >= EXTRAITS_MAX or time.monotonic() > echeance:
            return True
        if any(
            t.morceau.musixmatch_track_id == morceau.musixmatch_track_id
            for t in recherche.trouvailles
        ):
            continue
        try:
            texte = await services.paroles.texte_de(morceau)
        except (ServiceIndisponible, QuotaDepasse) as exc:
            recherche.code_erreur = _code(exc, services.paroles.service)
            return False
        extrait = extraire(texte, terme) if texte else None
        del texte  # MAT-16 : le texte complet n'est pas conservé
        morceau.texte = None
        if extrait is not None:
            recherche.trouvailles.append(Trouvaille(extrait, morceau, artiste_id, hors_liste))
        await services.dormir(services.parametres.pause_entre_appels_ms / 1000)
    return True


async def _rechercher_preferes(
    services: Services, recherche: Recherche, terme: str, echeance: float
) -> bool:
    with services.fabrique() as session:
        preferes = [(a.id, a.nom, a.musixmatch_id) for a in artistes.preferes(session)]
    for artiste_id, nom, musixmatch_id in preferes:
        if len(recherche.trouvailles) >= EXTRAITS_MAX or time.monotonic() > echeance:
            break
        try:
            morceaux, identifiant = await services.paroles.morceaux_artiste(
                nom, musixmatch_id, services.parametres.morceaux_par_artiste
            )
        except (ServiceIndisponible, QuotaDepasse) as exc:
            recherche.code_erreur = _code(exc, services.paroles.service)
            return False
        if identifiant is not None and identifiant != musixmatch_id:
            with services.fabrique() as session:
                ligne = session.get(Artiste, artiste_id)
                if ligne is not None:
                    ligne.musixmatch_id = identifiant
                    session.commit()
        if not await _chercher_dans(
            services, recherche, terme, [(m, artiste_id) for m in morceaux], False, echeance
        ):
            return False
    return True


async def chercher_extraits(services: Services, terme: str) -> Recherche:
    """Artistes préférés par rang, puis repli hors liste (D.2 à D.5, MAT-05)."""
    recherche = Recherche()
    with services.fabrique() as session:
        a_des_preferes = bool(artistes.preferes(session))
    debut = time.monotonic()
    disponible = True
    if a_des_preferes:
        echeance = debut + services.parametres.recherche_duree_max_s
        try:
            disponible = await asyncio.wait_for(
                _rechercher_preferes(services, recherche, terme, echeance),
                timeout=services.parametres.recherche_duree_max_s,
            )
        except TimeoutError:
            recherche.code_erreur = recherche.code_erreur or "delai_depasse"
    if disponible and not recherche.trouvailles:
        echeance = time.monotonic() + REPLI_DUREE_MAX_S
        try:
            morceaux = await services.paroles.rechercher_morceaux_par_texte(
                terme, services.parametres.morceaux_repli
            )
            await asyncio.wait_for(
                _chercher_dans(
                    services, recherche, terme, [(m, None) for m in morceaux], True, echeance
                ),
                timeout=REPLI_DUREE_MAX_S,
            )
        except (ServiceIndisponible, QuotaDepasse) as exc:
            recherche.code_erreur = _code(exc, services.paroles.service)
        except TimeoutError:
            recherche.code_erreur = recherche.code_erreur or "delai_depasse"
    if not recherche.trouvailles and recherche.code_erreur is None:
        recherche.code_erreur = "aucun_extrait"
    return recherche


async def traduire(
    services: Services, terme: str, contexte: str | None
) -> tuple[str | None, str | None]:
    """Traduction EN → FR par DeepL, à défaut par l'IA locale ; (traduction, code d'erreur)."""
    code: str | None = None
    if services.deepl.configure:
        try:
            for _ in range(2):  # CL-12 : une traduction vide est retentée une fois
                traduction = await services.deepl.traduire(terme, contexte)
                if traduction:
                    return traduction[:LONGUEUR_MAX_TRADUCTION], None
            code = "deepl_indisponible"
        except (ServiceIndisponible, QuotaDepasse) as exc:
            code = _code(exc, "deepl")
    try:
        if await services.ollama.disponible():
            traduction = await traduire_par_ia(services.ollama, terme, contexte)
            if traduction:
                return traduction[:LONGUEUR_MAX_TRADUCTION], None
    except ErreurApi:
        pass
    return None, code or "traduction_indisponible"


def _enregistrer_extraits(session: Session, mot: Mot, recherche: Recherche) -> int:
    """Morceaux (upsert), artistes de repli et extraits ; un extrait par morceau (MAT-03)."""
    existants = set(
        session.scalars(
            select(Extrait.morceau_id).where(Extrait.mot_id == mot.id, Extrait.deleted_at.is_(None))
        ).all()
    )
    ajoutes = 0
    for trouvaille in recherche.trouvailles[:EXTRAITS_MAX]:
        artiste_id = trouvaille.artiste_id
        if artiste_id is None:
            artiste = artistes.obtenir_ou_creer(
                session,
                trouvaille.morceau.artiste_nom or "Artiste inconnu",
                musixmatch_id=trouvaille.morceau.musixmatch_artist_id,
            )
            artiste_id = artiste.id
        session.execute(
            insert(Morceau)
            .values(
                id=uuid.uuid4(),
                artiste_id=artiste_id,
                titre=trouvaille.morceau.titre or "Titre inconnu",
                musixmatch_track_id=trouvaille.morceau.musixmatch_track_id,
            )
            .on_conflict_do_nothing(constraint="morceau_artiste_id_musixmatch_track_id_key")
        )
        morceau_id = session.scalar(
            select(Morceau.id).where(
                Morceau.artiste_id == artiste_id,
                Morceau.musixmatch_track_id == trouvaille.morceau.musixmatch_track_id,
            )
        )
        if morceau_id is None or morceau_id in existants:
            continue
        existants.add(morceau_id)
        session.add(
            Extrait(
                id=uuid.uuid4(),
                mot_id=mot.id,
                morceau_id=morceau_id,
                texte=trouvaille.extrait.texte,
                surbrillance_debut=trouvaille.extrait.debut,
                surbrillance_fin=trouvaille.extrait.fin,
                hors_liste=trouvaille.hors_liste,
            )
        )
        ajoutes += 1
    return ajoutes


def _premier_extrait(session: Session, mot_id: uuid.UUID) -> str | None:
    return session.scalar(
        select(Extrait.texte)
        .where(Extrait.mot_id == mot_id, Extrait.deleted_at.is_(None))
        .order_by(Extrait.created_at)
        .limit(1)
    )


async def enrichir(
    services: Services, mot_id: uuid.UUID, forcer_extraits: bool = False
) -> str | None:
    """Enrichit un mot ; chaque étape tolère les pannes (ENR-04). Retourne le statut final."""
    debut = time.perf_counter()
    with services.fabrique() as session:
        mot = session.get(Mot, mot_id)
        if mot is None or mot.deleted_at is not None:
            return None
        mot.statut_enrichissement = "en_cours"
        session.commit()
        terme, terme_normalise = mot.terme, mot.terme_normalise
        traduction = mot.traduction_fr
        explication = mot.explication if mot.source_explication == "ia" else None
        erreur_precedente = mot.erreur_enrichissement
        enrichi_le = mot.enrichi_le
        extrait_existant = _premier_extrait(session, mot_id)
    journaliser("enrichissement_debut", mot_id=str(mot_id), longueur_terme=len(terme))

    erreurs: list[str] = []
    rechercher = extrait_existant is None and (
        forcer_extraits
        or erreur_precedente != "aucun_extrait"
        or enrichi_le is None
        or datetime.now(UTC) - enrichi_le > timedelta(days=NOUVELLE_RECHERCHE_JOURS)
    )
    taches = []
    taches.append(chercher_extraits(services, terme_normalise) if rechercher else _rien())
    taches.append(traduire(services, terme, extrait_existant) if not traduction else _rien())
    resultat_recherche, resultat_traduction = await asyncio.gather(*taches, return_exceptions=True)

    if isinstance(resultat_recherche, Recherche) and resultat_recherche.trouvailles:
        with services.fabrique() as session:
            mot = session.get(Mot, mot_id)
            if mot is None or mot.deleted_at is not None:
                return None  # CL-08 : aucune écriture sur un mot supprimé
            _enregistrer_extraits(session, mot, resultat_recherche)
            session.commit()
            extrait_existant = _premier_extrait(session, mot_id)
    elif isinstance(resultat_recherche, Recherche):
        erreurs.append(resultat_recherche.code_erreur or "aucun_extrait")
    elif isinstance(resultat_recherche, BaseException):
        erreurs.append(f"{services.paroles.service}_indisponible")
    elif extrait_existant is None:
        erreurs.append("aucun_extrait")

    if isinstance(resultat_traduction, tuple):
        traduction_obtenue, code = resultat_traduction
        if traduction_obtenue:
            traduction = traduction_obtenue
        elif code:
            erreurs.append(code)
    elif isinstance(resultat_traduction, BaseException):
        erreurs.append("deepl_indisponible")

    if explication is None and (traduction or extrait_existant):
        try:
            if not await services.ollama.disponible():
                raise IaIndisponible()
            resultat = await ai_explainer.expliquer(
                services.ollama, terme, extrait_existant, services.parametres.ia_max_jetons
            )
            explication = resultat.texte
            journaliser(
                "ia_explication", mot_id=str(mot_id), version_prompt=resultat.version_prompt
            )
        except ErreurApi as exc:
            erreurs.append(exc.code if exc.code == "ia_format_invalide" else "ia_indisponible")

    if traduction and extrait_existant and explication:
        statut = "ok"
    elif traduction:
        statut = "partiel"
    else:
        statut = "echec"

    with services.fabrique() as session:
        mot = session.get(Mot, mot_id)
        if mot is None or mot.deleted_at is not None:
            return None
        mot.traduction_fr = traduction
        if explication:
            mot.explication = explication
            mot.source_explication = "ia"
        elif traduction:
            mot.source_explication = "traduction_seule"
        mot.statut_enrichissement = statut
        mot.erreur_enrichissement = erreurs[0] if erreurs and statut != "ok" else None
        mot.enrichi_le = datetime.now(UTC)
        session.commit()
    journaliser(
        "enrichissement_fin",
        mot_id=str(mot_id),
        statut=statut,
        duree_ms=round((time.perf_counter() - debut) * 1000),
        etapes_reussies=[
            n
            for n, ok in (
                ("extrait", extrait_existant),
                ("traduction", traduction),
                ("explication", explication),
            )
            if ok
        ],
    )
    if statut != "ok":
        journaliser(
            "enrichissement_echec",
            "avertissement",
            mot_id=str(mot_id),
            code=erreurs[0] if erreurs else None,
        )
    return statut


async def _rien() -> None:
    return None


class GestionnaireEnrichissement:
    """File asynchrone interne, au plus ENRICHISSEMENT_PARALLELE tâches (ENR-02, ENR-08)."""

    def __init__(self, services: Services) -> None:
        self.services = services
        self.file: asyncio.Queue[tuple[uuid.UUID, bool]] = asyncio.Queue()
        self.en_attente: set[uuid.UUID] = set()
        self.en_cours: set[uuid.UUID] = set()
        self.derniere_tentative: dict[uuid.UUID, float] = {}
        self._travailleurs: list[asyncio.Task] = []
        self._boucle: asyncio.AbstractEventLoop | None = None

    def demarrer(self) -> None:
        """Lance les travailleurs (à appeler depuis la boucle asyncio)."""
        self._boucle = asyncio.get_running_loop()
        for _ in range(max(1, self.services.parametres.enrichissement_parallele)):
            self._travailleurs.append(asyncio.create_task(self._travailler()))

    async def arreter(self) -> None:
        """Arrête les travailleurs."""
        for tache in self._travailleurs:
            tache.cancel()
        await asyncio.gather(*self._travailleurs, return_exceptions=True)
        self._travailleurs.clear()

    def soumettre(self, mot_id: uuid.UUID, forcer_extraits: bool = False) -> bool:
        """Ajoute un mot à la file absent ; appelable depuis tout thread."""
        if self.occupe(mot_id):
            return False
        self.derniere_tentative[mot_id] = time.monotonic()
        boucle = self._boucle
        try:
            courante = asyncio.get_running_loop()
        except RuntimeError:
            courante = None
        if boucle is None or courante is boucle:
            self._ajouter(mot_id, forcer_extraits)
        else:
            boucle.call_soon_threadsafe(self._ajouter, mot_id, forcer_extraits)
        return True

    def _ajouter(self, mot_id: uuid.UUID, forcer_extraits: bool) -> None:
        if mot_id in self.en_attente or mot_id in self.en_cours:
            return
        self.en_attente.add(mot_id)
        self.file.put_nowait((mot_id, forcer_extraits))

    def occupe(self, mot_id: uuid.UUID) -> bool:
        """Vrai si le mot est en file ou en cours."""
        return mot_id in self.en_attente or mot_id in self.en_cours

    async def _travailler(self) -> None:
        while True:
            mot_id, forcer = await self.file.get()
            self.en_attente.discard(mot_id)
            self.en_cours.add(mot_id)
            try:
                await enrichir(self.services, mot_id, forcer)
            except Exception as exc:  # FIA-02 : jamais de plantage du backend
                journaliser(
                    "enrichissement_echec",
                    "erreur",
                    mot_id=str(mot_id),
                    code="erreur_interne",
                    type_exception=type(exc).__name__,
                )
                self._remettre_en_attente(mot_id)
            finally:
                self.en_cours.discard(mot_id)
                self.file.task_done()

    def _remettre_en_attente(self, mot_id: uuid.UUID) -> None:
        with self.services.fabrique() as session:
            mot = session.get(Mot, mot_id)
            if mot is not None and mot.statut_enrichissement == "en_cours":
                mot.statut_enrichissement = "echec"
                session.commit()

    def reprendre(self, au_demarrage: bool = False) -> int:
        """Reprend les mots bloqués et relance les fiches incomplètes (ENR-03, 19.1, IA-22)."""
        limite = datetime.now(UTC) - timedelta(
            minutes=self.services.parametres.enrichissement_reprise_min
        )
        semaine = datetime.now(UTC) - timedelta(days=NOUVELLE_RECHERCHE_JOURS)
        with self.services.fabrique() as session:
            bloques = select(Mot.id).where(
                Mot.deleted_at.is_(None), Mot.statut_enrichissement.in_(("en_attente", "en_cours"))
            )
            if not au_demarrage:
                bloques = bloques.where(Mot.updated_at < limite)
            identifiants = list(session.scalars(bloques).all())
            if identifiants:
                for mot in session.scalars(select(Mot).where(Mot.id.in_(identifiants))):
                    mot.statut_enrichissement = "en_attente"
                session.commit()
            incomplets = session.scalars(
                select(Mot.id)
                .where(
                    Mot.deleted_at.is_(None),
                    or_(
                        Mot.statut_enrichissement == "echec",
                        (Mot.statut_enrichissement == "partiel")
                        & (Mot.erreur_enrichissement != "aucun_extrait"),
                        (Mot.statut_enrichissement == "partiel")
                        & (Mot.erreur_enrichissement == "aucun_extrait")
                        & (Mot.enrichi_le < semaine),
                    ),
                )
                .order_by(Mot.enrichi_le.asc().nulls_first())
                .limit(REPRISES_PAR_SYNC)
            ).all()
        soumis = 0
        for mot_id in [*identifiants, *incomplets]:
            soumis += int(self.soumettre(mot_id))
        return soumis

    def relancer_si_utile(self, mot: Mot) -> bool:
        """À l'ouverture d'une fiche partielle faute d'IA, redemande l'explication (IA-22)."""
        if mot.statut_enrichissement != "partiel" or mot.erreur_enrichissement not in (
            "ia_indisponible",
            "ia_format_invalide",
        ):
            return False
        if self.services.ollama.etat_en_cache() is False:
            return False
        derniere = self.derniere_tentative.get(mot.id)
        if derniere is not None and time.monotonic() - derniere < DELAI_RELANCE_IA_S:
            return False
        return self.soumettre(mot.id)
