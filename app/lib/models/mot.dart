import 'extrait.dart';
import 'json.dart';

/// Statuts finaux de l'enrichissement.
const statutsFinaux = {'ok', 'partiel', 'echec'};

/// Mot ou expression et sa fiche (18.1, 18.2, 40.1).
class Mot {
  const Mot({
    required this.id,
    required this.terme,
    required this.termeNormalise,
    this.traductionFr,
    this.explication,
    this.sourceExplication,
    this.statutEnrichissement = 'en_attente',
    this.erreurEnrichissement,
    this.niveau = 'nouveau',
    this.nbEchecs = 0,
    this.extraits = const [],
    this.prochaineRevision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String terme;
  final String termeNormalise;
  final String? traductionFr;
  final String? explication;
  final String? sourceExplication;
  final String statutEnrichissement;
  final String? erreurEnrichissement;
  final String niveau;
  final int nbEchecs;
  final List<Extrait> extraits;
  final DateTime? prochaineRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get enrichissementTermine => statutsFinaux.contains(statutEnrichissement);
  bool get explicationIA => sourceExplication == 'ia' && explication != null;

  /// Pastille « Argot » : l'explication ou la traduction l'indique (43.6, point 1).
  bool get estArgot {
    final contenu = '${explication ?? ''} ${traductionFr ?? ''}'.toLowerCase();
    if (!RegExp(r'\bargot').hasMatch(contenu)) return false;
    return !RegExp(r"(pas|n'est pas|non)\s+(de l')?argot").hasMatch(contenu);
  }

  factory Mot.fromJson(Map<String, dynamic> json) {
    final extraits = (json['extraits'] as List<dynamic>? ?? const [])
        .map((e) => Extrait.fromJson(e as Map<String, dynamic>, motId: json['id'] as String))
        .toList();
    final maintenant = DateTime.now().toUtc();
    return Mot(
      id: json['id'] as String,
      terme: json['terme'] as String,
      termeNormalise: json['terme_normalise'] as String,
      traductionFr: json['traduction_fr'] as String?,
      explication: json['explication'] as String?,
      sourceExplication: json['source_explication'] as String?,
      statutEnrichissement: (json['statut_enrichissement'] as String?) ?? 'en_attente',
      erreurEnrichissement: json['erreur_enrichissement'] as String?,
      niveau: (json['niveau'] as String?) ?? 'nouveau',
      nbEchecs: lireEntier(json['nb_echecs']),
      extraits: extraits,
      prochaineRevision: lireJour(json['prochaine_revision']),
      createdAt: lireInstant(json['created_at']) ?? maintenant,
      updatedAt: lireInstant(json['updated_at']) ?? maintenant,
      deletedAt: lireInstant(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'terme': terme,
    'terme_normalise': termeNormalise,
    'traduction_fr': traductionFr,
    'explication': explication,
    'source_explication': sourceExplication,
    'statut_enrichissement': statutEnrichissement,
    'erreur_enrichissement': erreurEnrichissement,
    'niveau': niveau,
    'nb_echecs': nbEchecs,
    'prochaine_revision': ecrireJour(prochaineRevision),
    'created_at': ecrireInstant(createdAt),
    'updated_at': ecrireInstant(updatedAt),
    'deleted_at': ecrireInstant(deletedAt),
  };

  Mot copyWith({
    String? id,
    Object? traductionFr = absent,
    Object? explication = absent,
    Object? sourceExplication = absent,
    String? statutEnrichissement,
    String? niveau,
    int? nbEchecs,
    List<Extrait>? extraits,
    Object? prochaineRevision = absent,
    DateTime? updatedAt,
    Object? deletedAt = absent,
  }) => Mot(
    id: id ?? this.id,
    terme: terme,
    termeNormalise: termeNormalise,
    traductionFr: identical(traductionFr, absent) ? this.traductionFr : traductionFr as String?,
    explication: identical(explication, absent) ? this.explication : explication as String?,
    sourceExplication: identical(sourceExplication, absent)
        ? this.sourceExplication
        : sourceExplication as String?,
    statutEnrichissement: statutEnrichissement ?? this.statutEnrichissement,
    erreurEnrichissement: erreurEnrichissement,
    niveau: niveau ?? this.niveau,
    nbEchecs: nbEchecs ?? this.nbEchecs,
    extraits: extraits ?? this.extraits,
    prochaineRevision: identical(prochaineRevision, absent)
        ? this.prochaineRevision
        : prochaineRevision as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, absent) ? this.deletedAt : deletedAt as DateTime?,
  );
}

/// Page de la liste des mots (API-10).
class PageMots {
  const PageMots({required this.items, required this.total, required this.page, required this.taille});

  final List<Mot> items;
  final int total;
  final int page;
  final int taille;

  bool get aSuite => page * taille < total;

  factory PageMots.fromJson(Map<String, dynamic> json) => PageMots(
    items: (json['items'] as List<dynamic>).map((e) => Mot.fromJson(e as Map<String, dynamic>)).toList(),
    total: lireEntier(json['total']),
    page: lireEntier(json['page'], 1),
    taille: lireEntier(json['taille'], 50),
  );
}

/// Résultat d'un ajout : le mot et s'il existait déjà (API-13).
class ResultatCreation {
  const ResultatCreation(this.mot, {required this.dejaPresent});
  final Mot mot;
  final bool dejaPresent;
}
