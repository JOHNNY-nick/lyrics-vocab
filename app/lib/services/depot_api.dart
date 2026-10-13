// PWA : lecture et écriture directes par l'API, sans file d'actions (SYN-05, PWA-04).
import 'package:uuid/uuid.dart';

import '../models/divers.dart';
import '../models/mot.dart';
import '../models/revision.dart';
import 'api_client.dart';
import 'artistes_secours.dart';
import 'depot_donnees.dart';

class DepotApi implements DepotDonnees {
  DepotApi(this.api);
  final ApiClient api;
  static const _uuid = Uuid();

  @override
  bool get horsLignePossible => false;

  @override
  Future<PageMots> listerMots({
    String? niveau,
    String? q,
    String tri = 'created_desc',
    int page = 1,
    int taille = 50,
  }) => api.listerMots(niveau: niveau, q: q, tri: tri, page: page, taille: taille);

  @override
  Future<Mot?> obtenirMot(String id) async {
    try {
      return await api.obtenirMot(id);
    } on ErreurApi catch (e) {
      if (e.code == 'mot_introuvable') return null;
      rethrow;
    }
  }

  @override
  Future<ResultatCreation> creerMot(String terme) => api.creerMot(_uuid.v4(), terme);

  @override
  Future<void> supprimerMot(String id) => api.supprimerMot(id);

  @override
  Future<void> relancerEnrichissement(String id) => api.rechercherExtraits(id);

  @override
  Future<List<Mot>> derniersMots(int nombre) async => (await api.listerMots(taille: nombre)).items;

  @override
  Future<RevisionsDues> revisionsDues() => api.revisionsDues();

  @override
  Future<void> repondre(RevisionDue revision, ReponseCarte reponse) async {
    await api.repondre(
      revision.id,
      opId: _uuid.v4(),
      qualite: reponse.qualite,
      verdict: reponse.verdict,
      reponse: reponse.reponse,
      reponduLe: DateTime.now(),
    );
  }

  @override
  Future<Exercice> creerExercice(String motId) => api.creerExercice(motId);

  @override
  Future<Verdict> evaluerExercice(String id, String reponse) => api.evaluerExercice(id, reponse);

  @override
  Future<List<Artiste>> artistesPreferes() => api.artistesPreferes();

  @override
  Future<void> enregistrerArtistes(List<Artiste> artistes) => api.enregistrerArtistes(artistes);

  @override
  Future<List<Artiste>> rechercherArtistes(String q) => api.rechercherArtistes(q);

  @override
  Future<List<Artiste>> suggestions() async {
    try {
      return await api.suggestions();
    } catch (_) {
      return artistesSecours; // liste de secours embarquée (H.3, écran 1)
    }
  }

  @override
  Future<Reglages> reglages() => api.obtenirReglages();

  @override
  Future<void> enregistrerReglages(Reglages reglages) => api.enregistrerReglages(reglages);

  @override
  Future<Map<String, dynamic>> exporter() async {
    final mots = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final resultat = await api.listerMots(page: page, taille: 200);
      for (final resume in resultat.items) {
        final detail = await api.obtenirMot(resume.id);
        mots.add({...detail.toJson(), 'extraits': detail.extraits.map((e) => e.toJson()).toList()});
      }
      if (!resultat.aSuite) break;
      page++;
    }
    return {'mots': mots, 'exporte_le': DateTime.now().toUtc().toIso8601String()};
  }
}
