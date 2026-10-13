// Rappels locaux Android (partie J, 40.4) ; version neutre sur le web (NOT-10).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/divers.dart';
import '../models/mot.dart';
import 'calendrier.dart';
import 'local_cache.dart';

const joursPlanifies = 3;
const notificationsMax = 60;
const canalId = 'mots';
const canalNom = 'Un mot de ta bibliothèque';
const longueurTexteMax = 180;
const multiplicateurTirage = 2654435761;

/// Une notification à programmer : un mot, son explication, sa fiche au toucher.
class RappelPlanifie {
  const RappelPlanifie({required this.quand, required this.titre, required this.corps, required this.motId});
  final DateTime quand; // heure murale locale
  final String titre;
  final String corps;
  final String motId;
}

/// Créneaux d'un jour : début de la plage + k × intervalle ; une fin avant le début va
/// jusqu'à minuit (même règle que backend/app/services/notifications_mots.py).
List<DateTime> creneauxDuJour(DateTime jour, String debut, String fin, int intervalle) {
  if (intervalle <= 0) return const [];
  final (hd, md) = lireHeure(debut);
  final (hf, mf) = lireHeure(fin);
  final depart = DateTime(jour.year, jour.month, jour.day, hd, md);
  var limite = DateTime(jour.year, jour.month, jour.day, hf, mf);
  if (!limite.isAfter(depart)) limite = DateTime(jour.year, jour.month, jour.day + 1);
  return [for (var t = depart; t.isBefore(limite); t = t.add(Duration(minutes: intervalle))) t];
}

/// Minutes depuis le 1er janvier 2000 en heure locale (identique au PC).
int cleCreneau(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(2000)).inDays * 1440 +
    t.hour * 60 +
    t.minute;

/// Mot du créneau, jamais le même que celui du créneau précédent (identique au PC).
int indiceMot(int cle, int intervalle, int nombre) {
  if (nombre <= 1) return 0;
  int brut(int c) => ((c * multiplicateurTirage) % 0x100000000) % nombre;
  final i = brut(cle);
  return i == brut(cle - intervalle) ? (i + 1) % nombre : i;
}

/// Notifications des 3 prochains jours (60 au plus) : un mot traduit tiré au hasard à chaque
/// créneau, avec son explication ; le toucher ouvre sa fiche.
List<RappelPlanifie> planifierRappels({
  required DateTime maintenantLocal,
  required Reglages reglages,
  required List<Mot> mots,
}) {
  final intervalle = reglages.intervalleNotificationsMin;
  final candidats = mots.where((m) => m.deletedAt == null && m.traductionFr != null).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  if (intervalle <= 0 || candidats.isEmpty) return const [];
  final rappels = <RappelPlanifie>[];
  for (var j = 0; j < joursPlanifies && rappels.length < notificationsMax; j++) {
    final jour = DateTime(maintenantLocal.year, maintenantLocal.month, maintenantLocal.day + j);
    for (final quand in creneauxDuJour(
      jour,
      reglages.notificationsDebut,
      reglages.notificationsFin,
      intervalle,
    )) {
      if (!quand.isAfter(maintenantLocal) || rappels.length >= notificationsMax) continue;
      final mot = candidats[indiceMot(cleCreneau(quand), intervalle, candidats.length)];
      var corps = (mot.explicationIA ? mot.explication! : '').replaceAll('\n', ' ');
      if (corps.length > longueurTexteMax) corps = '${corps.substring(0, longueurTexteMax - 1).trimRight()}…';
      rappels.add(
        RappelPlanifie(
          quand: quand,
          titre: mot.traductionFr == null ? mot.terme : '${mot.terme} — ${mot.traductionFr}',
          corps: corps,
          motId: mot.id,
        ),
      );
    }
  }
  return rappels;
}

abstract class ServiceNotifications {
  Future<void> initialiser();
  Future<bool> permissionAccordee();
  Future<bool> demanderPermission();
  Future<void> reprogrammer(LocalCache cache, {bool inclureAujourdhui = true});

  /// Charges des notifications touchées (« revisions » ou « mot:ID », NOT-05, NOT-12).
  Stream<String> get appuis;
  Future<String?> chargeAuLancement();
}

class NotificationsNeutres implements ServiceNotifications {
  NotificationsNeutres({this.chargeInitiale});

  /// PWA ouverte depuis une notification Windows : « mot:ID » lu dans l'adresse.
  final String? chargeInitiale;
  final _appuis = StreamController<String>.broadcast();
  @override
  Future<void> initialiser() async {}
  @override
  Future<bool> permissionAccordee() async => false;
  @override
  Future<bool> demanderPermission() async => false;
  @override
  Future<void> reprogrammer(LocalCache cache, {bool inclureAujourdhui = true}) async {}
  @override
  Stream<String> get appuis => _appuis.stream;
  @override
  Future<String?> chargeAuLancement() async => chargeInitiale;
}

class NotificationsAndroid implements ServiceNotifications {
  NotificationsAndroid(this.nomFuseau);
  final String nomFuseau;
  final _plugin = FlutterLocalNotificationsPlugin();
  final _appuis = StreamController<String>.broadcast();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialiser() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(nomFuseau));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (reponse) {
        if (reponse.payload != null) _appuis.add(reponse.payload!);
      },
    );
  }

  @override
  Future<bool> permissionAccordee() async => await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> demanderPermission() async => await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<String?> chargeAuLancement() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) return details!.notificationResponse?.payload;
    return null;
  }

  @override
  Future<void> reprogrammer(LocalCache cache, {bool inclureAujourdhui = true}) async {
    await _plugin.cancelAll();
    if (!await permissionAccordee()) return;
    final rappels = planifierRappels(
      maintenantLocal: DateTime.now(),
      reglages: cache.reglages(),
      mots: cache.tousMots(),
    );

    for (var i = 0; i < rappels.length; i++) {
      final r = rappels[i];
      final quand = tz.TZDateTime(
        tz.local,
        r.quand.year,
        r.quand.month,
        r.quand.day,
        r.quand.hour,
        r.quand.minute,
      );
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          canalId,
          canalNom,
          channelDescription: 'Un mot de ta bibliothèque et son explication',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(r.corps, contentTitle: r.titre),
        ),
      );
      try {
        await _plugin.zonedSchedule(
          i + 1,
          r.titre,
          r.corps,
          quand,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'mot:${r.motId}',
        );
      } catch (e) {
        debugPrint('Rappel non programmé : $e');
      }
    }
  }

  @override
  Stream<String> get appuis => _appuis.stream;
}
