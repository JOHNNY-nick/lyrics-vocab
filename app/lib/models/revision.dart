import '../services/sm2.dart';
import 'extrait.dart';
import 'json.dart';

/// Révision planifiée ou faite (17.4, 40.1).
class Revision {
  const Revision({
    required this.id,
    required this.motId,
    required this.datePrevue,
    this.repetitions = 0,
    this.facilite = 2.5,
    this.intervalleJours = 0,
    this.statut = 'planifiee',
    this.mode = 'rappel',
    this.qualite,
    this.verdict,
    this.reponseUtilisateur,
    this.reponduLe,
    this.opId,
    this.phraseSource,
    this.referenceEn,
    this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String motId;
  final DateTime datePrevue;
  final int repetitions;
  final double facilite;
  final int intervalleJours;
  final String statut;
  final String mode;
  final int? qualite;
  final String? verdict;
  final String? reponseUtilisateur;
  final DateTime? reponduLe;
  final String? opId;
  final String? phraseSource;
  final String? referenceEn;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  bool get planifiee => statut == 'planifiee' && deletedAt == null;
  EtatRevision get etat =>
      EtatRevision(repetitions: repetitions, facilite: facilite, intervalleJours: intervalleJours);

  factory Revision.fromJson(Map<String, dynamic> json) => Revision(
    id: json['id'] as String,
    motId: json['mot_id'] as String,
    datePrevue: lireJour(json['date_prevue'])!,
    repetitions: lireEntier(json['repetitions']),
    facilite: lireReel(json['facilite'], 2.5),
    intervalleJours: lireEntier(json['intervalle_jours']),
    statut: json['statut'] as String? ?? 'planifiee',
    mode: json['mode'] as String? ?? 'rappel',
    qualite: json['qualite'] == null ? null : lireEntier(json['qualite']),
    verdict: json['verdict'] as String?,
    reponseUtilisateur: json['reponse_utilisateur'] as String?,
    reponduLe: lireInstant(json['repondu_le']),
    opId: json['op_id'] as String?,
    phraseSource: json['phrase_source'] as String?,
    referenceEn: json['reference_en'] as String?,
    createdAt: lireInstant(json['created_at']),
    deletedAt: lireInstant(json['deleted_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'mot_id': motId,
    'date_prevue': ecrireJour(datePrevue),
    'repetitions': repetitions,
    'facilite': facilite,
    'intervalle_jours': intervalleJours,
    'statut': statut,
    'mode': mode,
    'qualite': qualite,
    'verdict': verdict,
    'reponse_utilisateur': reponseUtilisateur,
    'repondu_le': ecrireInstant(reponduLe),
    'op_id': opId,
    'phrase_source': phraseSource,
    'reference_en': referenceEn,
    'created_at': ecrireInstant(createdAt),
    'deleted_at': ecrireInstant(deletedAt),
  };

  Revision copyWith({
    String? motId,
    String? statut,
    int? qualite,
    String? verdict,
    String? reponseUtilisateur,
    DateTime? reponduLe,
    String? opId,
  }) => Revision(
    id: id,
    motId: motId ?? this.motId,
    datePrevue: datePrevue,
    repetitions: repetitions,
    facilite: facilite,
    intervalleJours: intervalleJours,
    statut: statut ?? this.statut,
    mode: mode,
    qualite: qualite ?? this.qualite,
    verdict: verdict ?? this.verdict,
    reponseUtilisateur: reponseUtilisateur ?? this.reponseUtilisateur,
    reponduLe: reponduLe ?? this.reponduLe,
    opId: opId ?? this.opId,
    phraseSource: phraseSource,
    referenceEn: referenceEn,
    createdAt: createdAt,
    deletedAt: deletedAt,
  );
}

/// Révision due, avec l'indice et les données révélées (18.4).
class RevisionDue {
  const RevisionDue({
    required this.id,
    required this.motId,
    required this.mode,
    required this.datePrevue,
    required this.terme,
    this.traductionFr,
    this.indice,
    this.explication,
    this.sourceExplication,
    this.extrait,
  });

  final String id;
  final String motId;
  final String mode;
  final DateTime datePrevue;
  final String terme;
  final String? traductionFr;
  final String? indice;
  final String? explication;
  final String? sourceExplication;
  final Extrait? extrait;

  factory RevisionDue.fromJson(Map<String, dynamic> json) => RevisionDue(
    id: json['id'] as String,
    motId: json['mot_id'] as String,
    mode: json['mode'] as String? ?? 'rappel',
    datePrevue: lireJour(json['date_prevue'])!,
    terme: json['terme'] as String,
    traductionFr: json['traduction_fr'] as String?,
    indice: json['indice'] as String?,
    explication: json['explication'] as String?,
    sourceExplication: json['source_explication'] as String?,
    extrait: json['extrait'] == null
        ? null
        : Extrait.fromJson(json['extrait'] as Map<String, dynamic>, motId: json['mot_id'] as String),
  );
}

/// Liste des révisions dues (18.4).
class RevisionsDues {
  const RevisionsDues({
    required this.totalDus,
    required this.jour,
    required this.items,
    this.prochaineDate,
    this.serie = 0,
  });

  final int totalDus;
  final DateTime jour;
  final List<RevisionDue> items;
  final DateTime? prochaineDate;
  final int serie;

  factory RevisionsDues.fromJson(Map<String, dynamic> json) => RevisionsDues(
    totalDus: lireEntier(json['total_dus']),
    jour: lireJour(json['jour'])!,
    prochaineDate: lireJour(json['prochaine_date']),
    serie: lireEntier(json['serie']),
    items: (json['items'] as List<dynamic>)
        .map((e) => RevisionDue.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Résultat d'une réponse (18.4).
class ResultatReponse {
  const ResultatReponse({
    required this.statut,
    required this.prochaineDate,
    required this.intervalleJours,
    required this.facilite,
    required this.repetitions,
    required this.niveau,
  });

  final String statut;
  final DateTime prochaineDate;
  final int intervalleJours;
  final double facilite;
  final int repetitions;
  final String niveau;

  factory ResultatReponse.fromJson(Map<String, dynamic> json) => ResultatReponse(
    statut: json['statut'] as String,
    prochaineDate: lireJour(json['prochaine_date'])!,
    intervalleJours: lireEntier(json['intervalle_jours']),
    facilite: lireReel(json['facilite']),
    repetitions: lireEntier(json['repetitions']),
    niveau: json['niveau'] as String,
  );
}

/// Exercice de production (18.5).
class Exercice {
  const Exercice({required this.id, required this.phraseFr});
  final String id;
  final String phraseFr;

  factory Exercice.fromJson(Map<String, dynamic> json) =>
      Exercice(id: json['id'] as String, phraseFr: json['phrase_fr'] as String);
}

/// Verdict de l'exercice (18.5).
class Verdict {
  const Verdict({
    required this.verdict,
    required this.explication,
    required this.verdictRepli,
    this.referenceEn,
  });
  final String verdict;
  final String explication;
  final bool verdictRepli;
  final String? referenceEn;

  factory Verdict.fromJson(Map<String, dynamic> json) => Verdict(
    verdict: json['verdict'] as String,
    explication: json['explication'] as String,
    verdictRepli: json['verdict_repli'] as bool? ?? false,
    referenceEn: json['reference_en'] as String?,
  );
}
