// Accès aux données choisi selon la plateforme (CLI-07, CLI-08).
import '../models/divers.dart';
import '../models/mot.dart';
import '../models/revision.dart';

/// Réponse donnée à une carte de révision.
class ReponseCarte {
  const ReponseCarte({this.qualite, this.verdict, this.reponse});
  final int? qualite;
  final String? verdict;
  final String? reponse;
}

/// Interface commune : DepotApi (PWA) et DepotLocal (Android).
abstract class DepotDonnees {
  /// Vrai si les données sont lues dans un cache local (mode hors-ligne possible).
  bool get horsLignePossible;

  Future<PageMots> listerMots({
    String? niveau,
    String? q,
    String tri = 'created_desc',
    int page = 1,
    int taille = 50,
  });
  Future<Mot?> obtenirMot(String id);
  Future<ResultatCreation> creerMot(String terme);
  Future<void> supprimerMot(String id);
  Future<void> relancerEnrichissement(String id);
  Future<List<Mot>> derniersMots(int nombre);

  Future<RevisionsDues> revisionsDues();
  Future<void> repondre(RevisionDue revision, ReponseCarte reponse);

  /// [nouvelle] : une autre phrase que celle préparée à l'avance (« Nouvelle phrase »).
  Future<Exercice> creerExercice(String motId, {bool nouvelle = false});
  Future<Verdict> evaluerExercice(String id, String reponse);

  Future<List<Artiste>> artistesPreferes();
  Future<void> enregistrerArtistes(List<Artiste> artistes);
  Future<List<Artiste>> rechercherArtistes(String q);
  Future<List<Artiste>> suggestions();

  Future<Reglages> reglages();
  Future<void> enregistrerReglages(Reglages reglages);

  /// Toutes les données exportables (S).
  Future<Map<String, dynamic>> exporter();
}
