// Android : hors-ligne d'abord ; lecture et écriture dans le cache, puis file d'actions
// (SYN-01, SYN-02, AND-08 à AND-11, 19.5).
import 'package:uuid/uuid.dart';

import '../models/divers.dart';
import '../models/mot.dart';
import '../models/revision.dart';
import '../strings.dart';
import 'api_client.dart';
import 'artistes_secours.dart';
import 'calendrier.dart';
import 'depot_donnees.dart';
import 'extraction.dart';
import 'local_cache.dart';
import 'normalisation.dart';
import 'sm2.dart';

/// Exception levée quand une validation locale refuse le terme.
class TermeInvalideException implements Exception {
  const TermeInvalideException(this.message);
  final String message;
}

class DepotLocal implements DepotDonnees {
  DepotLocal({
    required this.cache,
    required this.api,
    required this.declencherSync,
    required this.serveurJoignable,
    DateTime Function()? horloge,
  }) : _horloge = horloge ?? DateTime.now;

  final LocalCache cache;
  final ApiClient api;

  /// Lance un cycle de synchronisation (après chaque action, SYN-07).
  final void Function() declencherSync;

  /// Vrai si le PC répond (état de connexion courant).
  final bool Function() serveurJoignable;
  final DateTime Function() _horloge;
  static const _uuid = Uuid();

  @override
  bool get horsLignePossible => true;

  DateTime get _jour => jourLocal(_horloge(), cache.reglages().heureChangementJour);

  Future<OperationSync> _enfiler(String type, Map<String, dynamic> donnees) => cache.ajouterOperation(
    OperationSync(opId: _uuid.v4(), type: type, donnees: donnees, creeLe: _horloge().toUtc()),
  );

  /// Fonction qui exige le PC : on tente toujours l'appel (l'état de connexion peut ne pas être
  /// encore connu) ; une erreur réseau devient HorsLigneException (AND-11).
  Future<T> _enLigne<T>(Future<T> Function() appel) async {
    try {
      return await appel();
    } on ReseauException {
      throw const HorsLigneException();
    }
  }

  @override
  Future<PageMots> listerMots({
    String? niveau,
    String? q,
    String tri = 'created_desc',
    int page = 1,
    int taille = 50,
  }) async {
    final tous = cache.motsFiltres(niveau: niveau, q: q, tri: tri);
    final debut = (page - 1) * taille;
    final items = debut >= tous.length
        ? <Mot>[]
        : tous.sublist(debut, (debut + taille).clamp(0, tous.length));
    return PageMots(items: items, total: tous.length, page: page, taille: taille);
  }

  @override
  Future<Mot?> obtenirMot(String id) async => cache.mot(id);

  @override
  Future<ResultatCreation> creerMot(String terme) async {
    final validation = validerTerme(terme, messageVide: S.termeVide, messageTropLong: S.termeTropLong);
    if (!validation.valide) throw TermeInvalideException(validation.erreur!);
    final existant = cache.motParTerme(validation.normalise!);
    if (existant != null) return ResultatCreation(cache.mot(existant.id)!, dejaPresent: true);
    final maintenant = _horloge().toUtc();
    final mot = Mot(
      id: _uuid.v4(),
      terme: terme.trim(),
      termeNormalise: validation.normalise!,
      createdAt: maintenant,
      updatedAt: maintenant,
    );
    final revision = Revision(id: _uuid.v4(), motId: mot.id, datePrevue: _jour, createdAt: maintenant);
    await cache.ecrireMot(mot);
    await cache.ecrireRevision(revision);
    await _enfiler('mot.creer', {
      'id': mot.id,
      'terme': mot.terme,
      'cree_le': formatUtc(maintenant),
      'revision_id': revision.id,
    });
    declencherSync();
    return ResultatCreation(cache.mot(mot.id)!, dejaPresent: false);
  }

  @override
  Future<void> supprimerMot(String id) async {
    await cache.supprimerMot(id);
    await _enfiler('mot.supprimer', {'id': id});
    declencherSync();
  }

  @override
  Future<void> relancerEnrichissement(String id) async {
    await _enLigne(() => api.rechercherExtraits(id));
    declencherSync();
  }

  @override
  Future<List<Mot>> derniersMots(int nombre) async => cache.motsFiltres().take(nombre).toList();

  /// Révisions du jour calculées localement (AND-10).
  @override
  Future<RevisionsDues> revisionsDues() async {
    final reglages = cache.reglages();
    final jour = _jour;
    final dues = cache.revisionsPlanifiees().where((r) => !r.datePrevue.isAfter(jour)).toList()
      ..sort((a, b) {
        final c = a.datePrevue.compareTo(b.datePrevue);
        return c != 0 ? c : (a.createdAt ?? jour).compareTo(b.createdAt ?? jour);
      });
    final items = <RevisionDue>[];
    for (final r in dues.take(reglages.motsParSession)) {
      final mot = cache.mot(r.motId);
      if (mot == null) continue;
      final extrait = mot.extraits.isEmpty ? null : mot.extraits.first;
      items.add(
        RevisionDue(
          id: r.id,
          motId: mot.id,
          mode: r.mode,
          datePrevue: r.datePrevue,
          terme: mot.terme,
          traductionFr: mot.traductionFr,
          indice: extrait == null
              ? null
              : masquerMot(extrait.texte, extrait.surbrillanceDebut, extrait.surbrillanceFin),
          explication: mot.explication,
          sourceExplication: mot.sourceExplication,
          exemples: mot.exemples,
          extrait: extrait,
        ),
      );
    }
    final futures = cache.revisionsPlanifiees().where((r) => r.datePrevue.isAfter(jour)).toList()
      ..sort((a, b) => a.datePrevue.compareTo(b.datePrevue));
    return RevisionsDues(
      totalDus: dues.length,
      jour: jour,
      items: items,
      prochaineDate: futures.isEmpty ? null : futures.first.datePrevue,
      serie: serieJours(jour),
    );
  }

  /// Jours consécutifs avec au moins une révision faite.
  int serieJours(DateTime jour) {
    final heure = cache.reglages().heureChangementJour;
    final faits = cache
        .revisions()
        .where((r) => r.statut == 'faite' && r.reponduLe != null)
        .map((r) => formatDate(jourLocal(r.reponduLe!, heure)))
        .toSet();
    var curseur = faits.contains(formatDate(jour)) ? jour : jour.subtract(const Duration(days: 1));
    var serie = 0;
    while (faits.contains(formatDate(curseur))) {
      serie++;
      curseur = DateTime.utc(curseur.year, curseur.month, curseur.day - 1);
    }
    return serie;
  }

  /// SM-2 calculé sur le téléphone, puis recalculé par le serveur (REV-03, 19.5).
  @override
  Future<void> repondre(RevisionDue due, ReponseCarte reponse) async {
    final revision = cache.revision(due.id);
    final mot = cache.motBrut(due.motId);
    if (revision == null || !revision.planifiee || mot == null) return; // REV-18
    final note = reponse.qualite ?? Notes.verdicts[reponse.verdict] ?? Notes.neSavaisPas;
    final maintenant = _horloge().toUtc();
    final jour = _jour;
    final etat = appliquerSm2(revision.etat, note);
    final suivante = Revision(
      id: _uuid.v4(),
      motId: mot.id,
      datePrevue: datePrevue(jour, etat.intervalleJours),
      repetitions: etat.repetitions,
      facilite: etat.facilite,
      intervalleJours: etat.intervalleJours,
      createdAt: maintenant,
    );
    final opId = _uuid.v4();
    // FLU-06 : la réponse n'est enregistrée qu'après l'écriture dans le cache ET dans la file.
    await cache.ecrireRevision(
      revision.copyWith(
        statut: 'faite',
        qualite: note,
        reponduLe: maintenant,
        opId: opId,
        verdict: reponse.verdict,
        reponseUtilisateur: reponse.reponse,
      ),
    );
    await cache.ecrireRevision(suivante);
    await cache.ecrireMot(
      mot.copyWith(
        niveau: niveauDepuisEtat(etat, note, niveauActuel: mot.niveau),
        nbEchecs: note < noteReussiteMin ? mot.nbEchecs + 1 : mot.nbEchecs,
      ),
    );
    try {
      await cache.ajouterOperation(
        OperationSync(
          opId: opId,
          type: 'revision.repondre',
          creeLe: maintenant,
          donnees: {
            'revision_id': revision.id,
            'mot_id': mot.id,
            if (reponse.qualite != null) 'qualite': reponse.qualite,
            if (reponse.verdict != null) 'verdict': reponse.verdict,
            if (reponse.reponse != null) 'reponse': reponse.reponse,
            'repondu_le': formatUtc(maintenant),
            'nouvelle_revision_id': suivante.id,
          },
        ),
      );
    } catch (_) {
      // CL-23 : jamais à moitié enregistrée.
      await cache.ecrireRevision(revision);
      await cache.supprimerRevision(suivante.id);
      await cache.ecrireMot(mot);
      rethrow;
    }
    declencherSync();
  }

  @override
  Future<Exercice> creerExercice(String motId) {
    return _enLigne(() => api.creerExercice(motId));
  }

  @override
  Future<Verdict> evaluerExercice(String id, String reponse) {
    return _enLigne(() => api.evaluerExercice(id, reponse));
  }

  @override
  Future<List<Artiste>> artistesPreferes() async => cache.artistesPreferes();

  @override
  Future<void> enregistrerArtistes(List<Artiste> artistes) async {
    await cache.remplacerPreferes(artistes);
    await _enfiler('artistes.modifier', {'artistes': artistes.map((a) => a.toEntree()).toList()});
    declencherSync();
  }

  @override
  Future<List<Artiste>> rechercherArtistes(String q) {
    return _enLigne(() => api.rechercherArtistes(q));
  }

  @override
  Future<List<Artiste>> suggestions() async {
    try {
      return await api.suggestions();
    } catch (_) {
      return artistesSecours;
    }
  }

  @override
  Future<Reglages> reglages() async => cache.reglages();

  @override
  Future<void> enregistrerReglages(Reglages reglages) async {
    final differences = reglages.difference(cache.reglages());
    await cache.ecrireReglages(reglages);
    if (differences.isEmpty) return;
    await _enfiler('reglage.modifier', differences);
    declencherSync();
  }

  @override
  Future<Map<String, dynamic>> exporter() async => {
    'mots': cache
        .motsFiltres()
        .map((m) => {...m.toJson(), 'extraits': cache.extraitsDe(m.id).map((e) => e.toJson()).toList()})
        .toList(),
    'exporte_le': _horloge().toUtc().toIso8601String(),
  };
}
