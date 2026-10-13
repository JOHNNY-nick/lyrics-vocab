// Construction de l'environnement selon la plateforme (CLI-07, CLI-08, FLU-07).
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'models/divers.dart';
import 'providers/providers.dart';
import 'services/api_client.dart';
import 'services/connectivite_service.dart';
import 'services/depot_api.dart';
import 'services/depot_local.dart';
import 'services/local_cache.dart';
import 'services/notifications_service.dart';
import 'services/dictee_service.dart';
import 'services/prononciation_service.dart';
import 'services/plateforme.dart';
import 'services/sync_service.dart';

const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// appareil_id : préfixe android ou pwa puis 4 caractères aléatoires, conservé (FLU-07).
Future<String> appareilIdDepuis(Magasin prefs, {required bool mobile}) async {
  final existant = prefs.lire(Meta.appareilId)?['v'] as String?;
  if (existant != null) return existant;
  final aleatoire = Random.secure();
  final suffixe = List.generate(4, (_) => _alphabet[aleatoire.nextInt(_alphabet.length)]).join();
  final id = '${mobile ? 'android' : 'pwa'}-$suffixe';
  await prefs.ecrire(Meta.appareilId, {'v': id});
  return id;
}

Future<String> _fuseau() async {
  try {
    return await FlutterTimezone.getLocalTimezone();
  } catch (_) {
    return '';
  }
}

Future<Environnement> construireEnvironnement(Magasin prefs) async {
  final mobile = !kIsWeb;
  final appareilId = await appareilIdDepuis(prefs, mobile: mobile);
  final fuseau = await _fuseau();

  if (!mobile) {
    // PWA servie par FastAPI sur la même origine que l'API (PWA-02).
    final adresse = adresseCompilee.isNotEmpty ? adresseCompilee : originePage();
    final api = ApiClient(Dio(), () => adresse, fuseau: () => fuseau, appareilId: () => appareilId);
    return Environnement(
      mobile: false,
      api: api,
      depot: DepotApi(api),
      connectivite: ConnectiviteNeutre(),
      notifications: NotificationsNeutres(),
      prononciation: PrononciationAppareil(),
      dictee: DicteeAppareil(),
    );
  }

  final cache = LocalCache(ouvrirMagasinHive);
  await cache.ouvrir();
  String adresse() => (cache.meta(Meta.adresseServeur) as String?) ?? adresseCompilee;
  final api = ApiClient(Dio(), adresse, fuseau: () => fuseau, appareilId: () => appareilId);
  final connectivite = ConnectiviteAndroid();
  final notifications = NotificationsAndroid(fuseau);
  final sync = SyncService(
    api: api,
    cache: cache,
    appareilId: () => appareilId,
    typeReseau: connectivite.type,
  );
  final depot = DepotLocal(
    cache: cache,
    api: api,
    declencherSync: () {
      // SYN-07 : après chaque action si le PC est joignable.
      if (sync.etat == EtatConnexion.enLigne) sync.synchroniser();
    },
    serveurJoignable: () => sync.etat == EtatConnexion.enLigne || sync.etat == EtatConnexion.synchronisation,
  );
  return Environnement(
    mobile: true,
    api: api,
    depot: depot,
    cache: cache,
    sync: sync,
    connectivite: connectivite,
    notifications: notifications,
    adresseModifiable: true,
    prononciation: PrononciationAppareil(),
    dictee: DicteeAppareil(),
  );
}
