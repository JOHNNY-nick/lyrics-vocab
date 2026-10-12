// Outils de test : faux serveur HTTP pour dio et environnement de test (QUAL-03).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lyrics_vocab/services/api_client.dart';

typedef Gestionnaire = (int, Object?) Function(RequestOptions requete, Map<String, dynamic>? corps);

/// Adaptateur dio qui répond sans réseau.
class FauxServeur implements HttpClientAdapter {
  FauxServeur(this.gestionnaire);
  Gestionnaire gestionnaire;
  final requetes = <RequestOptions>[];
  bool coupe = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requetes.add(options);
    if (coupe) {
      throw DioException.connectionError(requestOptions: options, reason: 'coupé');
    }
    Map<String, dynamic>? corps;
    if (options.data != null) {
      corps = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(options.data as Map);
    }
    final (statut, reponse) = gestionnaire(options, corps);
    return ResponseBody.fromString(
      reponse == null ? '' : jsonEncode(reponse),
      statut,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient apiDeTest(FauxServeur serveur) {
  final dio = Dio()..httpClientAdapter = serveur;
  return ApiClient(
    dio,
    () => 'https://pc.test/api',
    fuseau: () => 'Europe/Paris',
    appareilId: () => 'android-test',
  );
}

Map<String, dynamic> santeOk({String versionMin = '1.0.0'}) => {
  'status': 'ok',
  'version': '1.0.0',
  'version_client_min': versionMin,
  'base': 'ok',
  'ollama': 'ok',
  'curseur': 0,
};
