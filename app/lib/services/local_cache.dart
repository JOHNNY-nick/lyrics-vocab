// Stockage local (22.3, 40.2) : boîtes Hive sur Android, mémoire pour les tests et le web.
import 'package:hive/hive.dart';

import '../models/divers.dart';
import '../models/extrait.dart';
import '../models/mot.dart';
import '../models/revision.dart';
import 'normalisation.dart';

const versionSchemaLocal = 1;

/// Boîtes de 22.3.
class Boites {
  static const mots = 'mots';
  static const extraits = 'extraits';
  static const revisions = 'revisions';
  static const artistes = 'artistes';
  static const reglages = 'reglages';
  static const fileActions = 'file_actions';
  static const aExaminer = 'a_examiner';
  static const meta = 'meta';
  static const toutes = [mots, extraits, revisions, artistes, reglages, fileActions, aExaminer, meta];
  static const donnees = [mots, extraits, revisions, artistes, reglages];
}

/// Clés fixes de la boîte meta.
class Meta {
  static const curseur = 'curseur';
  static const appareilId = 'appareil_id';
  static const adresseServeur = 'adresse_serveur';
  static const derniereSync = 'derniere_sync';
  static const versionSchema = 'version_schema_local';
  static const onboardingFait = 'onboarding_fait';
  static const compteurFile = 'compteur_file';
  static const optionFacile = 'option_facile';
}

/// Une boîte clé → objet JSON.
abstract class Magasin {
  Map<String, dynamic>? lire(String cle);
  Iterable<String> get cles;
  Future<void> ecrire(String cle, Map<String, dynamic> valeur);
  Future<void> supprimer(String cle);
  Future<void> vider();
}

class MagasinMemoire implements Magasin {
  final _donnees = <String, Map<String, dynamic>>{};

  @override
  Map<String, dynamic>? lire(String cle) => _donnees[cle];
  @override
  Iterable<String> get cles => _donnees.keys.toList();
  @override
  Future<void> ecrire(String cle, Map<String, dynamic> valeur) async => _donnees[cle] = valeur;
  @override
  Future<void> supprimer(String cle) async => _donnees.remove(cle);
  @override
  Future<void> vider() async => _donnees.clear();
}

class MagasinHive implements Magasin {
  MagasinHive(this.boite);
  final Box<dynamic> boite;

  @override
  Map<String, dynamic>? lire(String cle) {
    final valeur = boite.get(cle);
    return valeur == null ? null : _versJson(valeur) as Map<String, dynamic>;
  }

  static Object? _versJson(Object? valeur) {
    if (valeur is Map) {
      return valeur.map((k, v) => MapEntry(k.toString(), _versJson(v)));
    }
    if (valeur is List) return valeur.map(_versJson).toList();
    return valeur;
  }

  @override
  Iterable<String> get cles => boite.keys.map((k) => k.toString()).toList();
  @override
  Future<void> ecrire(String cle, Map<String, dynamic> valeur) => boite.put(cle, valeur);
  @override
  Future<void> supprimer(String cle) => boite.delete(cle);
  @override
  Future<void> vider() async => boite.clear();
}

typedef OuvrirMagasin = Future<Magasin> Function(String nom);

Future<Magasin> ouvrirMagasinHive(String nom) async => MagasinHive(await Hive.openBox<dynamic>(nom));

Future<Magasin> ouvrirMagasinMemoire(String nom) async => MagasinMemoire();

/// Cache local : index en mémoire, écriture immédiate dans les boîtes (FLU-08).
class LocalCache {
  LocalCache(this._ouvrir);

  final OuvrirMagasin _ouvrir;
  final Map<String, Magasin> _boites = {};
  final Map<String, Mot> _mots = {};
  final Map<String, Extrait> _extraits = {};
  final Map<String, Revision> _revisions = {};
  final Map<String, Artiste> _artistes = {};

  /// Vrai si la base locale vient d'être (ré)initialisée et doit être resynchronisée.
  bool reinitialise = false;

  Magasin _b(String nom) => _boites[nom]!;

  /// Ouvre les boîtes et vérifie la version de schéma (FLU-05).
  Future<void> ouvrir() async {
    for (final nom in Boites.toutes) {
      _boites[nom] = await _ouvrir(nom);
    }
    final version = _b(Boites.meta).lire(Meta.versionSchema)?['v'] as int?;
    if (version != versionSchemaLocal) {
      if (version != null) await viderDonnees();
      await _b(Boites.meta).ecrire(Meta.versionSchema, {'v': versionSchemaLocal});
      reinitialise = true;
    }
    _charger();
    if (_mots.isEmpty && curseur == 0) reinitialise = true;
  }

  void _charger() {
    try {
      _mots
        ..clear()
        ..addEntries(_b(Boites.mots).cles.map((c) => MapEntry(c, Mot.fromJson(_b(Boites.mots).lire(c)!))));
      _extraits
        ..clear()
        ..addEntries(
          _b(Boites.extraits).cles.map((c) => MapEntry(c, Extrait.fromJson(_b(Boites.extraits).lire(c)!))),
        );
      _revisions
        ..clear()
        ..addEntries(
          _b(Boites.revisions).cles.map((c) => MapEntry(c, Revision.fromJson(_b(Boites.revisions).lire(c)!))),
        );
      _artistes
        ..clear()
        ..addEntries(
          _b(Boites.artistes).cles.map((c) => MapEntry(c, Artiste.fromJson(_b(Boites.artistes).lire(c)!))),
        );
    } catch (_) {
      // AND-12 : base locale corrompue : on repart de zéro, la synchronisation la remplira.
      _mots.clear();
      _extraits.clear();
      _revisions.clear();
      _artistes.clear();
      reinitialise = true;
    }
  }

  // --- Mots -------------------------------------------------------------------------------

  Mot? mot(String id) {
    final m = _mots[id];
    if (m == null || m.deletedAt != null) return null;
    return m.copyWith(extraits: extraitsDe(id), prochaineRevision: revisionPlanifiee(id)?.datePrevue);
  }

  /// Mot brut tel que stocké (sans extraits ni prochaine révision calculés).
  Mot? motBrut(String id) => _mots[id];

  List<Mot> tousMots() => _mots.values
      .where((m) => m.deletedAt == null)
      .map((m) => m.copyWith(prochaineRevision: revisionPlanifiee(m.id)?.datePrevue))
      .toList();

  Mot? motParTerme(String termeNormalise) {
    for (final m in _mots.values) {
      if (m.deletedAt == null && m.termeNormalise == termeNormalise) return m;
    }
    return null;
  }

  Future<void> ecrireMot(Mot mot) async {
    final propre = mot.copyWith(extraits: const []);
    _mots[mot.id] = propre;
    await _b(Boites.mots).ecrire(mot.id, propre.toJson());
  }

  Future<void> supprimerMot(String id) async {
    _mots.remove(id);
    await _b(Boites.mots).supprimer(id);
    for (final e in _extraits.values.where((e) => e.motId == id).toList()) {
      await supprimerExtrait(e.id);
    }
    for (final r in _revisions.values.where((r) => r.motId == id).toList()) {
      await supprimerRevision(r.id);
    }
  }

  /// Liste filtrée, recherchée et triée (MAQ-15 : insensible à la casse et aux accents).
  List<Mot> motsFiltres({String? niveau, String? q, String tri = 'created_desc'}) {
    final requete = q == null || q.trim().isEmpty ? null : formeComparable(q.trim());
    final resultat = tousMots().where((m) {
      if (niveau != null && m.niveau != niveau) return false;
      if (requete == null) return true;
      return formeComparable(m.terme).contains(requete) ||
          formeComparable(m.traductionFr ?? '').contains(requete);
    }).toList();
    switch (tri) {
      case 'created_asc':
        resultat.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'prochaine_revision':
        resultat.sort((a, b) {
          final da = a.prochaineRevision, db = b.prochaineRevision;
          if (da == null && db == null) return a.termeNormalise.compareTo(b.termeNormalise);
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
      case 'alpha':
        resultat.sort((a, b) => a.termeNormalise.compareTo(b.termeNormalise));
      default:
        resultat.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return resultat;
  }

  // --- Extraits ---------------------------------------------------------------------------

  List<Extrait> extraitsDe(String motId) =>
      _extraits.values.where((e) => e.motId == motId && e.deletedAt == null).toList();

  Future<void> ecrireExtrait(Extrait extrait) async {
    _extraits[extrait.id] = extrait;
    await _b(Boites.extraits).ecrire(extrait.id, extrait.toJson());
  }

  Future<void> supprimerExtrait(String id) async {
    _extraits.remove(id);
    await _b(Boites.extraits).supprimer(id);
  }

  // --- Révisions --------------------------------------------------------------------------

  Revision? revision(String id) => _revisions[id];

  List<Revision> revisions() => _revisions.values.toList();

  List<Revision> revisionsPlanifiees() => _revisions.values
      .where((r) => r.planifiee && (_mots[r.motId]?.deletedAt == null) && _mots.containsKey(r.motId))
      .toList();

  Revision? revisionPlanifiee(String motId) {
    for (final r in _revisions.values) {
      if (r.motId == motId && r.planifiee) return r;
    }
    return null;
  }

  Future<void> ecrireRevision(Revision revision) async {
    _revisions[revision.id] = revision;
    await _b(Boites.revisions).ecrire(revision.id, revision.toJson());
  }

  Future<void> supprimerRevision(String id) async {
    _revisions.remove(id);
    await _b(Boites.revisions).supprimer(id);
  }

  // --- Artistes et réglages ---------------------------------------------------------------

  List<Artiste> artistesPreferes() {
    final liste = _artistes.values.where((a) => a.estPrefere && a.deletedAt == null).toList()
      ..sort((a, b) => (a.rang ?? 1 << 30).compareTo(b.rang ?? 1 << 30));
    return liste;
  }

  Future<void> ecrireArtiste(Artiste artiste) async {
    final cle = artiste.id ?? artiste.cle;
    _artistes[cle] = artiste;
    await _b(Boites.artistes).ecrire(cle, artiste.toJson());
  }

  Future<void> supprimerArtiste(String cle) async {
    _artistes.remove(cle);
    await _b(Boites.artistes).supprimer(cle);
  }

  /// Remplace localement la liste des préférés (en attendant le pull du serveur).
  Future<void> remplacerPreferes(List<Artiste> choisis) async {
    final cles = choisis.map((a) => a.cle).toSet();
    for (final entree in _artistes.entries.toList()) {
      final a = entree.value;
      if (a.estPrefere && !cles.contains(a.cle)) {
        await ecrireArtisteCle(entree.key, a.copyWith(estPrefere: false));
      }
    }
    for (var i = 0; i < choisis.length; i++) {
      final existant = _artistes.entries.where((e) => e.value.cle == choisis[i].cle).toList();
      final cle = existant.isNotEmpty ? existant.first.key : (choisis[i].id ?? choisis[i].cle);
      await ecrireArtisteCle(cle, choisis[i].copyWith(estPrefere: true, rang: i + 1));
    }
  }

  Future<void> ecrireArtisteCle(String cle, Artiste artiste) async {
    _artistes[cle] = artiste;
    await _b(Boites.artistes).ecrire(cle, artiste.toJson());
  }

  Reglages reglages() {
    final brut = _b(Boites.reglages).lire('courant');
    return brut == null ? const Reglages() : Reglages.fromJson(brut);
  }

  Future<void> ecrireReglages(Reglages reglages) => _b(Boites.reglages).ecrire('courant', reglages.toJson());

  // --- File d'actions et liste « à examiner » ---------------------------------------------

  /// Opérations dans l'ordre de création (compteur local croissant, SYN-10).
  List<OperationSync> file() {
    final ops =
        _b(
          Boites.fileActions,
        ).cles.map((c) => OperationSync.fromJson(_b(Boites.fileActions).lire(c)!)).toList()..sort((a, b) {
          final c = a.compteur.compareTo(b.compteur);
          return c != 0 ? c : a.creeLe.compareTo(b.creeLe);
        });
    return ops;
  }

  Future<OperationSync> ajouterOperation(OperationSync op) async {
    final compteur = ((_b(Boites.meta).lire(Meta.compteurFile)?['v'] as int?) ?? 0) + 1;
    await _b(Boites.meta).ecrire(Meta.compteurFile, {'v': compteur});
    final avecCompteur = OperationSync(
      opId: op.opId,
      type: op.type,
      donnees: op.donnees,
      creeLe: op.creeLe,
      compteur: compteur,
    );
    await _b(Boites.fileActions).ecrire(compteur.toString().padLeft(12, '0'), avecCompteur.toJson());
    return avecCompteur;
  }

  String? _cleOperation(String opId) {
    for (final cle in _b(Boites.fileActions).cles) {
      if (_b(Boites.fileActions).lire(cle)?['op_id'] == opId) return cle;
    }
    return null;
  }

  Future<void> retirerOperation(String opId) async {
    final cle = _cleOperation(opId);
    if (cle != null) await _b(Boites.fileActions).supprimer(cle);
  }

  Future<void> remplacerOperation(OperationSync op) async {
    final cle = _cleOperation(op.opId);
    if (cle != null) await _b(Boites.fileActions).ecrire(cle, op.toJson());
  }

  List<OperationSync> aExaminer() =>
      _b(Boites.aExaminer).cles.map((c) => OperationSync.fromJson(_b(Boites.aExaminer).lire(c)!)).toList();

  Future<void> deplacerVersAExaminer(OperationSync op, String? code, String? message) async {
    await _b(Boites.aExaminer).ecrire(op.opId, op.copyWith(code: code, message: message).toJson());
    await retirerOperation(op.opId);
  }

  /// Remet une opération « à examiner » dans la file (bouton Réessayer).
  Future<void> reessayer(String opId) async {
    final brut = _b(Boites.aExaminer).lire(opId);
    if (brut == null) return;
    await _b(Boites.aExaminer).supprimer(opId);
    final op = OperationSync.fromJson(brut);
    await ajouterOperation(
      OperationSync(opId: op.opId, type: op.type, donnees: op.donnees, creeLe: op.creeLe),
    );
  }

  Future<void> abandonner(String opId) => _b(Boites.aExaminer).supprimer(opId);

  // --- Méta -------------------------------------------------------------------------------

  int get curseur => (_b(Boites.meta).lire(Meta.curseur)?['v'] as int?) ?? 0;

  Future<void> fixerCurseur(int valeur) => _b(Boites.meta).ecrire(Meta.curseur, {'v': valeur});

  Object? meta(String cle) => _b(Boites.meta).lire(cle)?['v'];

  Future<void> fixerMeta(String cle, Object? valeur) =>
      valeur == null ? _b(Boites.meta).supprimer(cle) : _b(Boites.meta).ecrire(cle, {'v': valeur});

  /// Vide les données (garde la file, « à examiner » et la méta), puis remet le curseur à 0.
  Future<void> viderDonnees() async {
    for (final nom in Boites.donnees) {
      await _b(nom).vider();
    }
    _mots.clear();
    _extraits.clear();
    _revisions.clear();
    _artistes.clear();
    await fixerCurseur(0);
  }
}
