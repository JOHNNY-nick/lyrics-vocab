// Synchronisation client : file d'actions, push, pull par curseur (G.4, 40.3, CLI-01 à CLI-05).
import 'dart:async';
import 'dart:math';

import '../models/divers.dart';
import '../models/extrait.dart';
import '../models/mot.dart';
import '../models/revision.dart';
import 'api_client.dart';
import 'local_cache.dart';

const tailleLot = 50;
const taillePage = 200;
const tentativesMaxParCycle = 10;
const attenteMaxS = 60;
const alea = 0.2;

/// Version de l'application, comparée à version_client_min du serveur (CL-32, AND-18).
const versionApplication = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

enum TypeReseau { aucun, wifi, mobile, autre }

enum ResultatSync { ignore, wifiSeulement, horsLigne, pcInjoignable, termine, erreur, clientTropAncien }

/// Compare deux versions « a.b.c » ; négatif si a < b.
int comparerVersions(String a, String b) {
  List<int> parts(String v) => v.split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < max(pa.length, pb.length); i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Attente progressive 1, 2, 4, 8 s… plafonnée à 60 s, avec ±20 % d'aléa (ALG-09).
Duration attenteProgressive(int tentative, {Random? aleatoire}) {
  final base = min(attenteMaxS, 1 << min(tentative, 6)).toDouble();
  final facteur = 1 + ((aleatoire ?? Random()).nextDouble() * 2 - 1) * alea;
  return Duration(milliseconds: (base * facteur * 1000).round());
}

class SyncService {
  SyncService({
    required this.api,
    required this.cache,
    required this.appareilId,
    required this.typeReseau,
    this.apresSync,
    this.surEtat,
    this.decouvrir,
    Random? aleatoire,
  }) : _aleatoire = aleatoire ?? Random();

  final ApiClient api;
  final LocalCache cache;
  final String Function() appareilId;
  final Future<TypeReseau> Function() typeReseau;

  /// Appelé après chaque cycle réussi (notifications, rafraîchissement de l'interface).
  Future<void> Function()? apresSync;

  /// Appelé à chaque changement d'état de connexion.
  void Function(EtatConnexion etat, ResultatSync? resultat)? surEtat;
  final Random _aleatoire;

  bool _verrou = false;
  int _echecsConsecutifs = 0;
  Timer? _reessai;
  EtatConnexion etat = EtatConnexion.aVerifier;
  Sante? derniereSante;

  /// Cherche l'adresse publiée du PC ; vrai si une nouvelle adresse a été enregistrée.
  final Future<bool> Function()? decouvrir;

  bool get enCours => _verrou;

  void _changer(EtatConnexion nouvel, [ResultatSync? resultat]) {
    etat = nouvel;
    surEtat?.call(nouvel, resultat);
  }

  /// Un cycle complet ; un seul à la fois (SYN-03).
  Future<ResultatSync> synchroniser({bool manuel = false}) async {
    if (_verrou) return ResultatSync.ignore;
    _verrou = true; // posé avant toute attente : un seul cycle à la fois
    try {
      final reseau = await typeReseau();
      if (reseau == TypeReseau.aucun) {
        _changer(EtatConnexion.horsLigne, ResultatSync.horsLigne);
        return ResultatSync.horsLigne;
      }
      if (!manuel && reseau == TypeReseau.mobile && cache.reglages().syncWifiSeulement) {
        return ResultatSync.wifiSeulement; // SYN-09
      }
      _changer(EtatConnexion.synchronisation);
      var sante = await api.sante();
      if (sante == null && decouvrir != null && await decouvrir!()) sante = await api.sante();
      if (sante == null) {
        _planifierReessai();
        _changer(EtatConnexion.pcInjoignable, ResultatSync.pcInjoignable);
        return ResultatSync.pcInjoignable;
      }
      derniereSante = sante;
      if (comparerVersions(versionApplication, sante.versionClientMin) < 0) {
        _changer(EtatConnexion.enLigne, ResultatSync.clientTropAncien);
        return ResultatSync.clientTropAncien;
      }
      if (await api.codeRefuse()) {
        _changer(EtatConnexion.codeAccesRequis, ResultatSync.erreur);
        return ResultatSync.erreur;
      }
      await _envoyer();
      await _recevoir();
      await cache.fixerMeta(Meta.derniereSync, DateTime.now().toUtc().toIso8601String());
      _echecsConsecutifs = 0;
      _reessai?.cancel();
      _changer(EtatConnexion.enLigne, ResultatSync.termine);
      if (apresSync != null) await apresSync!();
      return ResultatSync.termine;
    } on ReseauException {
      _planifierReessai();
      _changer(EtatConnexion.pcInjoignable, ResultatSync.pcInjoignable);
      return ResultatSync.pcInjoignable;
    } on ServeurIndisponibleException {
      _planifierReessai();
      _changer(EtatConnexion.pcInjoignable, ResultatSync.erreur);
      return ResultatSync.erreur;
    } finally {
      _verrou = false;
    }
  }

  /// Nouvelle tentative progressive, au plus 10 d'affilée, puis attente du prochain déclencheur.
  void _planifierReessai() {
    _echecsConsecutifs++;
    _reessai?.cancel();
    if (_echecsConsecutifs > tentativesMaxParCycle) return;
    _reessai = Timer(attenteProgressive(_echecsConsecutifs - 1, aleatoire: _aleatoire), () => synchroniser());
  }

  void annulerReessai() => _reessai?.cancel();

  /// Envoi par lots de 50 ; une opération n'est retirée qu'après un accusé (SYN-12, CLI-01).
  Future<void> _envoyer() async {
    String? premierPrecedent;
    while (true) {
      final file = cache.file();
      if (file.isEmpty) return;
      if (file.first.opId == premierPrecedent) return; // sécurité : aucune progression
      premierPrecedent = file.first.opId;
      final lot = file.take(tailleLot).toList();
      final resultats = await api.push(appareilId(), lot);
      final parId = {for (final op in lot) op.opId: op};
      for (final resultat in resultats) {
        final op = parId[resultat.opId];
        if (op == null) continue;
        if (resultat.acquitte) {
          await cache.retirerOperation(op.opId);
          await _apresAccuse(op, resultat);
        } else if (resultat.statut == 'rejete') {
          await cache.deplacerVersAExaminer(op, resultat.code, resultat.message); // SYN-13
        }
      }
    }
  }

  /// Fusion d'un mot créé hors-ligne sur un mot existant (20.7, CLI-03).
  Future<void> _apresAccuse(OperationSync op, ResultatOperation resultat) async {
    if (op.type != 'mot.creer') return;
    final donnees = resultat.donnees;
    if (donnees == null || donnees['fusion'] != true) return;
    final local = donnees['id_local'] as String;
    final conserve = donnees['mot_id'] as String;
    for (final attente in cache.file()) {
      if (attente.donnees['mot_id'] == local || attente.donnees['id'] == local) {
        final nouvelles = Map<String, dynamic>.from(attente.donnees);
        if (nouvelles['mot_id'] == local) nouvelles['mot_id'] = conserve;
        if (nouvelles['id'] == local) nouvelles['id'] = conserve;
        await cache.remplacerOperation(attente.copyWith(donnees: nouvelles));
      }
    }
    await cache.supprimerMot(local);
  }

  /// Réception par pages ; le curseur n'est enregistré qu'après la page appliquée (SYN-20).
  Future<void> _recevoir({bool reprise = false}) async {
    var curseur = cache.curseur;
    try {
      while (true) {
        final page = await api.pull(curseur, limite: taillePage);
        await appliquerChangements(page.changements);
        curseur = page.curseur;
        await cache.fixerCurseur(curseur);
        if (!page.aSuite) break;
      }
    } on ErreurApi catch (e) {
      if (e.code == 'curseur_invalide' && !reprise) {
        await cache.fixerCurseur(0); // CL-25 : synchronisation complète
        await _recevoir(reprise: true);
        return;
      }
      rethrow;
    }
  }

  /// Le serveur fait foi : les objets locaux sont remplacés (CLI-02).
  Future<void> appliquerChangements(Map<String, List<Map<String, dynamic>>> changements) async {
    for (final ligne in changements['mots'] ?? const <Map<String, dynamic>>[]) {
      final mot = Mot.fromJson(ligne);
      if (mot.deletedAt != null) {
        await cache.supprimerMot(mot.id);
      } else {
        await cache.ecrireMot(mot);
      }
    }
    for (final ligne in changements['extraits'] ?? const <Map<String, dynamic>>[]) {
      final extrait = Extrait.fromJson(ligne);
      if (extrait.deletedAt != null) {
        await cache.supprimerExtrait(extrait.id);
      } else {
        await cache.ecrireExtrait(extrait);
      }
    }
    for (final ligne in changements['revisions'] ?? const <Map<String, dynamic>>[]) {
      final revision = Revision.fromJson(ligne);
      if (revision.deletedAt != null) {
        await cache.supprimerRevision(revision.id);
        continue;
      }
      if (revision.planifiee) {
        for (final autre in cache.revisions()) {
          if (autre.motId == revision.motId && autre.planifiee && autre.id != revision.id) {
            await cache.supprimerRevision(autre.id); // une seule planifiée par mot (REV-01)
          }
        }
      }
      await cache.ecrireRevision(revision);
    }
    for (final ligne in changements['reglages'] ?? const <Map<String, dynamic>>[]) {
      await cache.ecrireReglages(Reglages.fromJson(ligne));
    }
    for (final ligne in changements['artistes'] ?? const <Map<String, dynamic>>[]) {
      final artiste = Artiste.fromJson(ligne);
      if (artiste.deletedAt != null) {
        await cache.supprimerArtiste(artiste.id!);
        continue;
      }
      for (final local in cache.artistesPreferes()) {
        if (local.id == null && local.cle == artiste.cle) await cache.supprimerArtiste(local.cle);
      }
      await cache.ecrireArtisteCle(artiste.id!, artiste);
    }
  }
}
