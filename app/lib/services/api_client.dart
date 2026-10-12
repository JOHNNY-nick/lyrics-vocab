// Client HTTP unique (dio) avec intercepteurs et erreurs typées (FLU-02, 40.2).
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../models/divers.dart';
import '../models/mot.dart';
import '../models/revision.dart';

const delaiRequete = Duration(seconds: 15);
const delaiSante = Duration(seconds: 3);

/// Adresse de l'API lue à la compilation (PWA-03) : --dart-define=API_BASE_URL=…
const adresseCompilee = String.fromEnvironment('API_BASE_URL');

/// Ajoute /api si l'adresse ne le contient pas (« http://localhost:8000 » ou « …/api »).
String normaliserAdresse(String adresse) {
  var a = adresse.trim();
  while (a.endsWith('/')) {
    a = a.substring(0, a.length - 1);
  }
  return a.endsWith('/api') ? a : '$a/api';
}

/// Pas de réseau ou délai dépassé.
class ReseauException implements Exception {
  const ReseauException([this.detail]);
  final String? detail;
  @override
  String toString() => 'ReseauException($detail)';
}

/// Serveur en erreur 5xx ou 503.
class ServeurIndisponibleException implements Exception {
  const ServeurIndisponibleException([this.code, this.message]);
  final String? code;
  final String? message;
  @override
  String toString() => 'ServeurIndisponibleException($code)';
}

/// Erreur applicative au format {code, message, details} (C.1).
class ErreurApi implements Exception {
  const ErreurApi(this.code, this.message, {this.statut});
  final String code;
  final String message;
  final int? statut;
  @override
  String toString() => 'ErreurApi($code, $message)';
}

/// Fonction hors ligne demandée sans serveur.
class HorsLigneException implements Exception {
  const HorsLigneException();
}

class ApiClient {
  ApiClient(this.dio, this.adresse, {required this.fuseau, required this.appareilId}) {
    dio.options
      ..connectTimeout = delaiRequete
      ..receiveTimeout = delaiRequete
      ..sendTimeout = delaiRequete
      ..responseType = ResponseType.json;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, gestionnaire) {
          options.headers['X-Request-Id'] = const Uuid().v4();
          final nomFuseau = fuseau();
          if (nomFuseau.isNotEmpty) options.headers['X-Fuseau'] = nomFuseau;
          final appareil = appareilId();
          if (appareil.isNotEmpty) options.headers['X-Appareil-Id'] = appareil;
          gestionnaire.next(options);
        },
      ),
    );
  }

  final Dio dio;

  /// Adresse de base lue à chaque appel (réglage « Adresse du serveur », AND-05).
  final String Function() adresse;
  final String Function() fuseau;
  final String Function() appareilId;

  String _url(String chemin) => '${normaliserAdresse(adresse())}$chemin';

  Exception _traduire(DioException erreur) {
    final reponse = erreur.response;
    if (reponse == null) return ReseauException(erreur.type.name);
    final corps = reponse.data;
    final statut = reponse.statusCode ?? 0;
    if (corps is Map && corps['code'] is String) {
      if (statut == 503 || statut >= 500) {
        return ServeurIndisponibleException(corps['code'] as String, corps['message'] as String?);
      }
      return ErreurApi(corps['code'] as String, (corps['message'] as String?) ?? '', statut: statut);
    }
    if (statut >= 500) return ServeurIndisponibleException();
    if (statut == 408) return const ReseauException('408');
    return ErreurApi('erreur_http', 'HTTP $statut', statut: statut);
  }

  Future<Response<dynamic>> _requete(
    String methode,
    String chemin, {
    Object? corps,
    Map<String, dynamic>? parametres,
    Duration? delai,
  }) async {
    try {
      return await dio.request<dynamic>(
        _url(chemin),
        data: corps,
        queryParameters: parametres,
        options: Options(
          method: methode,
          sendTimeout: delai,
          receiveTimeout: delai,
          contentType: corps == null ? null : Headers.jsonContentType,
        ),
      );
    } on DioException catch (erreur) {
      throw _traduire(erreur);
    }
  }

  Map<String, dynamic> _carte(Response<dynamic> r) => Map<String, dynamic>.from(r.data as Map);
  List<dynamic> _liste(Response<dynamic> r) => r.data as List<dynamic>;

  /// Vrai si /api/health répond en moins de 3 s (SYN-06).
  Future<Sante?> sante({String? adresseTest}) async {
    try {
      final url = adresseTest == null ? _url('/health') : '${normaliserAdresse(adresseTest)}/health';
      final reponse = await dio.get<dynamic>(
        url,
        options: Options(sendTimeout: delaiSante, receiveTimeout: delaiSante),
      );
      if (reponse.statusCode == 200 && reponse.data is Map) {
        return Sante.fromJson(Map<String, dynamic>.from(reponse.data as Map));
      }
      return null;
    } on DioException {
      return null;
    }
  }

  Future<ResultatCreation> creerMot(String id, String terme) async {
    final reponse = await _requete('POST', '/mots', corps: {'id': id, 'terme': terme});
    return ResultatCreation(Mot.fromJson(_carte(reponse)), dejaPresent: reponse.statusCode == 200);
  }

  Future<PageMots> listerMots({
    String? niveau,
    String? q,
    String tri = 'created_desc',
    int page = 1,
    int taille = 50,
  }) async {
    final reponse = await _requete(
      'GET',
      '/mots',
      parametres: {
        if (niveau != null) 'niveau': niveau,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'tri': tri,
        'page': page,
        'taille': taille,
      },
    );
    return PageMots.fromJson(_carte(reponse));
  }

  Future<Mot> obtenirMot(String id) async => Mot.fromJson(_carte(await _requete('GET', '/mots/$id')));

  Future<void> supprimerMot(String id) => _requete('DELETE', '/mots/$id');

  Future<Mot> rechercherExtraits(String id) async =>
      Mot.fromJson(_carte(await _requete('POST', '/mots/$id/rechercher-extraits')));

  Future<RevisionsDues> revisionsDues({DateTime? jour}) async {
    final reponse = await _requete(
      'GET',
      '/revisions/dues',
      parametres: {
        if (jour != null)
          'date':
              '${jour.year}-${jour.month.toString().padLeft(2, '0')}-'
              '${jour.day.toString().padLeft(2, '0')}',
      },
    );
    return RevisionsDues.fromJson(_carte(reponse));
  }

  Future<ResultatReponse> repondre(
    String revisionId, {
    required String opId,
    int? qualite,
    String? verdict,
    String? reponse,
    DateTime? reponduLe,
  }) async {
    final r = await _requete(
      'POST',
      '/revisions/$revisionId/reponse',
      corps: {
        'op_id': opId,
        if (qualite != null) 'qualite': qualite,
        if (verdict != null) 'verdict': verdict,
        if (reponse != null) 'reponse': reponse,
        if (reponduLe != null) 'repondu_le': reponduLe.toUtc().toIso8601String(),
      },
    );
    return ResultatReponse.fromJson(_carte(r));
  }

  Future<Exercice> creerExercice(String motId) async =>
      Exercice.fromJson(_carte(await _requete('POST', '/exercices', corps: {'mot_id': motId})));

  Future<Verdict> evaluerExercice(String id, String reponse) async =>
      Verdict.fromJson(_carte(await _requete('POST', '/exercices/$id/evaluer', corps: {'reponse': reponse})));

  Future<List<Artiste>> rechercherArtistes(String q) async => _liste(
    await _requete('GET', '/artistes/recherche', parametres: {'q': q}),
  ).map((e) => Artiste.fromJson(Map<String, dynamic>.from(e as Map))).toList();

  Future<List<Artiste>> suggestions() async => _liste(
    await _requete('GET', '/artistes/suggestions'),
  ).map((e) => Artiste.fromJson(Map<String, dynamic>.from(e as Map))).toList();

  Future<List<Artiste>> artistesPreferes() async => _liste(
    await _requete('GET', '/artistes-preferes'),
  ).map((e) => Artiste.fromJson(Map<String, dynamic>.from(e as Map))).toList();

  Future<void> enregistrerArtistes(List<Artiste> artistes) =>
      _requete('PUT', '/artistes-preferes', corps: {'artistes': artistes.map((a) => a.toEntree()).toList()});

  Future<Reglages> obtenirReglages() async => Reglages.fromJson(_carte(await _requete('GET', '/reglages')));

  Future<void> enregistrerReglages(Reglages r) => _requete('PUT', '/reglages', corps: r.toJson());

  Future<List<ResultatOperation>> push(String appareilId, List<OperationSync> operations) async {
    final reponse = await _requete(
      'POST',
      '/sync/push',
      corps: {'appareil_id': appareilId, 'operations': operations.map((o) => o.versServeur()).toList()},
    );
    return (_carte(reponse)['resultats'] as List<dynamic>)
        .map((e) => ResultatOperation.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<PageChangements> pull(int since, {int limite = 200}) async => PageChangements.fromJson(
    _carte(await _requete('GET', '/sync/pull', parametres: {'since': since, 'limite': limite})),
  );

  Future<Map<String, dynamic>> quotas() async => _carte(await _requete('GET', '/quotas'));

  Future<List<Map<String, dynamic>>> erreursRecentes() async =>
      ((_carte(await _requete('GET', '/logs/erreurs', parametres: {'limite': 20}))['items']) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}
