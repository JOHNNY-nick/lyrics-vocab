import 'json.dart';

/// Artiste préféré ou suggéré (40.1).
class Artiste {
  const Artiste({
    this.id,
    required this.nom,
    this.geniusId,
    this.imageUrl,
    this.estPrefere = false,
    this.rang,
    this.deletedAt,
  });

  final String? id;
  final String nom;
  final int? geniusId;
  final String? imageUrl;
  final bool estPrefere;
  final int? rang;
  final DateTime? deletedAt;

  /// Clé d'identité : identifiant Genius, sinon nom en minuscules.
  String get cle => geniusId != null ? 'g$geniusId' : 'n${nom.toLowerCase()}';

  /// Initiales : première lettre des deux premiers mots (43.6, point 7).
  String get initiales {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return '?';
    final lettres = mots.take(2).map((m) => String.fromCharCode(m.runes.first).toUpperCase());
    return mots.length == 1 ? lettres.first : lettres.join();
  }

  factory Artiste.fromJson(Map<String, dynamic> json) => Artiste(
    id: json['id'] as String?,
    nom: json['nom'] as String,
    geniusId: json['genius_id'] == null ? null : lireEntier(json['genius_id']),
    imageUrl: json['image_url'] as String?,
    estPrefere: json['est_prefere'] as bool? ?? false,
    rang: json['rang'] == null ? null : lireEntier(json['rang']),
    deletedAt: lireInstant(json['deleted_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'genius_id': geniusId,
    'image_url': imageUrl,
    'est_prefere': estPrefere,
    'rang': rang,
    'deleted_at': ecrireInstant(deletedAt),
  };

  /// Forme attendue par PUT /api/artistes-preferes.
  Map<String, dynamic> toEntree() => {'genius_id': geniusId, 'nom': nom, 'image_url': imageUrl};

  Artiste copyWith({bool? estPrefere, int? rang}) => Artiste(
    id: id,
    nom: nom,
    geniusId: geniusId,
    imageUrl: imageUrl,
    estPrefere: estPrefere ?? this.estPrefere,
    rang: rang ?? this.rang,
  );
}

/// Réglages (18.6, 40.1).
class Reglages {
  const Reglages({
    this.frequenceRappels = 'quotidien',
    this.heureRappel = '19:00',
    this.heuresRappelSup = const [],
    this.intervalleNotificationsMin = 120,
    this.notificationsDebut = '09:00',
    this.notificationsFin = '21:00',
    this.motsParSession = 20,
    this.modeRevision = 'rappel',
    this.heureChangementJour = '04:00',
    this.syncWifiSeulement = false,
  });

  final String frequenceRappels;
  final String heureRappel;

  /// Rappels supplémentaires dans la journée (« HH:MM », 2 au plus).
  final List<String> heuresRappelSup;

  /// Notification d'un mot au hasard toutes les N minutes dans la plage (0 : désactivées).
  final int intervalleNotificationsMin;
  final String notificationsDebut;
  final String notificationsFin;
  final int motsParSession;

  /// Toutes les heures de rappel de la journée, dans l'ordre.
  List<String> get heuresRappel => {heureRappel, ...heuresRappelSup}.toList()..sort();
  final String modeRevision;
  final String heureChangementJour;
  final bool syncWifiSeulement;

  factory Reglages.fromJson(Map<String, dynamic> json) => Reglages(
    frequenceRappels: json['frequence_rappels'] as String? ?? 'quotidien',
    heureRappel: (json['heure_rappel'] as String? ?? '19:00').substring(0, 5),
    intervalleNotificationsMin: lireEntier(json['intervalle_notifications_min'], 120),
    notificationsDebut: (json['notifications_debut'] as String? ?? '09:00').substring(0, 5),
    notificationsFin: (json['notifications_fin'] as String? ?? '21:00').substring(0, 5),
    heuresRappelSup: [
      for (final h in json['heures_rappel_sup'] as List<dynamic>? ?? const []) (h as String).substring(0, 5),
    ],
    motsParSession: lireEntier(json['mots_par_session'], 20),
    modeRevision: json['mode_revision'] as String? ?? 'rappel',
    heureChangementJour: (json['heure_changement_jour'] as String? ?? '04:00').substring(0, 5),
    syncWifiSeulement: json['sync_wifi_seulement'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'frequence_rappels': frequenceRappels,
    'heure_rappel': heureRappel,
    'heures_rappel_sup': heuresRappelSup,
    'intervalle_notifications_min': intervalleNotificationsMin,
    'notifications_debut': notificationsDebut,
    'notifications_fin': notificationsFin,
    'mots_par_session': motsParSession,
    'mode_revision': modeRevision,
    'heure_changement_jour': heureChangementJour,
    'sync_wifi_seulement': syncWifiSeulement,
  };

  /// Champs qui diffèrent de [autre] (opération reglage.modifier).
  Map<String, dynamic> difference(Reglages autre) {
    final a = toJson();
    final b = autre.toJson();
    return {
      for (final cle in a.keys)
        if ('${a[cle]}' != '${b[cle]}') cle: a[cle], // les listes se comparent par contenu
    };
  }

  Reglages copyWith({
    String? frequenceRappels,
    String? heureRappel,
    List<String>? heuresRappelSup,
    int? intervalleNotificationsMin,
    String? notificationsDebut,
    String? notificationsFin,
    int? motsParSession,
    String? modeRevision,
    String? heureChangementJour,
    bool? syncWifiSeulement,
  }) => Reglages(
    frequenceRappels: frequenceRappels ?? this.frequenceRappels,
    heureRappel: heureRappel ?? this.heureRappel,
    heuresRappelSup: heuresRappelSup ?? this.heuresRappelSup,
    intervalleNotificationsMin: intervalleNotificationsMin ?? this.intervalleNotificationsMin,
    notificationsDebut: notificationsDebut ?? this.notificationsDebut,
    notificationsFin: notificationsFin ?? this.notificationsFin,
    motsParSession: motsParSession ?? this.motsParSession,
    modeRevision: modeRevision ?? this.modeRevision,
    heureChangementJour: heureChangementJour ?? this.heureChangementJour,
    syncWifiSeulement: syncWifiSeulement ?? this.syncWifiSeulement,
  );
}

/// Opération de la file d'actions (40.1, 22.3).
class OperationSync {
  const OperationSync({
    required this.opId,
    required this.type,
    required this.donnees,
    required this.creeLe,
    this.tentatives = 0,
    this.compteur = 0,
    this.code,
    this.message,
  });

  final String opId;
  final String type;
  final Map<String, dynamic> donnees;
  final DateTime creeLe;
  final int tentatives;
  final int compteur;
  final String? code;
  final String? message;

  factory OperationSync.fromJson(Map<String, dynamic> json) => OperationSync(
    opId: json['op_id'] as String,
    type: json['type'] as String,
    donnees: Map<String, dynamic>.from(json['donnees'] as Map),
    creeLe: lireInstant(json['cree_le']) ?? DateTime.now().toUtc(),
    tentatives: lireEntier(json['tentatives']),
    compteur: lireEntier(json['compteur']),
    code: json['code'] as String?,
    message: json['message'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'op_id': opId,
    'type': type,
    'donnees': donnees,
    'cree_le': ecrireInstant(creeLe),
    'tentatives': tentatives,
    'compteur': compteur,
    'code': code,
    'message': message,
  };

  /// Forme envoyée à POST /api/sync/push.
  Map<String, dynamic> versServeur() => {'op_id': opId, 'type': type, 'donnees': donnees};

  OperationSync copyWith({Map<String, dynamic>? donnees, int? tentatives, String? code, String? message}) =>
      OperationSync(
        opId: opId,
        type: type,
        donnees: donnees ?? this.donnees,
        creeLe: creeLe,
        tentatives: tentatives ?? this.tentatives,
        compteur: compteur,
        code: code ?? this.code,
        message: message ?? this.message,
      );
}

/// États de la connexion (19.3).
enum EtatConnexion { horsLigne, aVerifier, pcInjoignable, enLigne, synchronisation, codeAccesRequis }

/// État du serveur renvoyé par /api/health.
class Sante {
  const Sante({
    required this.version,
    required this.versionClientMin,
    required this.ollama,
    this.curseur,
    this.apk,
    this.derniereSauvegarde,
    this.alerteSauvegarde = false,
  });
  final String version;
  final String versionClientMin;
  final String ollama;
  final int? curseur;
  final Map<String, dynamic>? apk;
  final String? derniereSauvegarde;
  final bool alerteSauvegarde;

  factory Sante.fromJson(Map<String, dynamic> json) => Sante(
    version: json['version'] as String? ?? '',
    versionClientMin: json['version_client_min'] as String? ?? '0.0.0',
    ollama: json['ollama'] as String? ?? 'inconnu',
    curseur: json['curseur'] == null ? null : lireEntier(json['curseur']),
    apk: json['apk'] as Map<String, dynamic>?,
    derniereSauvegarde: json['derniere_sauvegarde'] as String?,
    alerteSauvegarde: json['alerte_sauvegarde'] as bool? ?? false,
  );
}

/// Résultats d'un push (G.4).
class ResultatOperation {
  const ResultatOperation({required this.opId, required this.statut, this.code, this.message, this.donnees});
  final String opId;
  final String statut;
  final String? code;
  final String? message;
  final Map<String, dynamic>? donnees;

  bool get acquitte => statut == 'applique' || statut == 'deja_applique';

  factory ResultatOperation.fromJson(Map<String, dynamic> json) => ResultatOperation(
    opId: json['op_id'] as String,
    statut: json['statut'] as String,
    code: json['code'] as String?,
    message: json['message'] as String?,
    donnees: json['donnees'] as Map<String, dynamic>?,
  );
}

/// Page du pull (G.4).
class PageChangements {
  const PageChangements({required this.curseur, required this.aSuite, required this.changements});
  final int curseur;
  final bool aSuite;
  final Map<String, List<Map<String, dynamic>>> changements;

  factory PageChangements.fromJson(Map<String, dynamic> json) => PageChangements(
    curseur: lireEntier(json['curseur']),
    aSuite: json['a_suite'] as bool? ?? false,
    changements: (json['changements'] as Map<String, dynamic>).map(
      (cle, valeur) => MapEntry(cle, (valeur as List<dynamic>).cast<Map<String, dynamic>>()),
    ),
  );
}
