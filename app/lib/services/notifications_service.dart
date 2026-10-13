// Rappels locaux Android (partie J, 40.4) ; version neutre sur le web (NOT-10).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/divers.dart';
import '../models/revision.dart';
import 'calendrier.dart';
import 'extraction.dart';
import 'local_cache.dart';

const joursPlanifies = 14;
const chargeRevisions = 'revisions';
const canalId = 'rappels';
const canalNom = 'Rappels de révision';
const longueurIndiceMax = 90;

/// Un rappel à programmer.
class RappelPlanifie {
  const RappelPlanifie({required this.quand, required this.nombre, required this.corps, this.motId});
  final DateTime quand; // heure murale locale
  final int nombre;
  final String corps;
  final String? motId;
}

/// Calcule les rappels des 14 prochains jours (logique pure, NOT-03, NOT-04, NOT-08).
List<RappelPlanifie> planifierRappels({
  required DateTime maintenantLocal,
  required Reglages reglages,
  required List<Revision> planifiees,
  required String? Function(String motId) indice,
  bool inclureAujourdhui = true,
}) {
  final pas = joursEntreRappels[reglages.frequenceRappels];
  if (pas == null) return const [];
  final rappels = <RappelPlanifie>[];
  for (var j = 0; j < joursPlanifies; j += pas) {
    // Après une révision, plus de rappel aujourd'hui, sauf si l'utilisateur en a demandé
    // plusieurs par jour : les suivants restent, s'il reste des mots à réviser.
    if (!inclureAujourdhui && j == 0 && reglages.heuresRappelSup.isEmpty) continue;
    for (final heure in reglages.heuresRappel) {
      final (h, m) = lireHeure(heure);
      final quand = DateTime(maintenantLocal.year, maintenantLocal.month, maintenantLocal.day + j, h, m);
      if (!quand.isAfter(maintenantLocal)) continue;
      final rappel = _rappel(quand, reglages, planifiees, indice);
      if (rappel != null) rappels.add(rappel);
    }
  }
  return rappels;
}

/// Jours entre deux journées de rappel, par fréquence (absente : rappels désactivés).
const joursEntreRappels = {'quotidien': 1, 'tous_les_2_jours': 2, 'tous_les_3_jours': 3, 'hebdomadaire': 7};

RappelPlanifie? _rappel(
  DateTime quand,
  Reglages reglages,
  List<Revision> planifiees,
  String? Function(String motId) indice,
) {
  final jour = jourLocalDepuisHeureLocale(quand, reglages.heureChangementJour);
  final dues = planifiees.where((r) => !r.datePrevue.isAfter(jour)).toList()
    ..sort((a, b) => a.datePrevue.compareTo(b.datePrevue));
  if (dues.isEmpty) return null;
  final premier = dues.first;
  var corps = indice(premier.motId) ?? 'Un mot t\'attend.';
  if (corps.length > longueurIndiceMax) corps = '${corps.substring(0, longueurIndiceMax)}…';
  return RappelPlanifie(
    quand: quand,
    nombre: dues.length,
    corps: corps.replaceAll('\n', ' / '),
    motId: dues.length == 1 ? premier.motId : null,
  );
}

String titreRappel(int n) => n == 1 ? '1 mot à réviser' : '$n mots à réviser';

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
  Future<String?> chargeAuLancement() async => null;
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
    String? indice(String motId) {
      final mot = cache.mot(motId);
      if (mot == null) return null;
      if (mot.extraits.isEmpty) return mot.terme.replaceAll(RegExp(r'\S'), '_');
      final e = mot.extraits.first;
      return masquerMot(e.texte, e.surbrillanceDebut, e.surbrillanceFin); // NOT-13
    }

    final rappels = planifierRappels(
      maintenantLocal: DateTime.now(),
      reglages: cache.reglages(),
      planifiees: cache.revisionsPlanifiees(),
      indice: indice,
      inclureAujourdhui: inclureAujourdhui,
    );
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        canalId,
        canalNom,
        channelDescription: 'Mots à réviser du jour',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
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
      try {
        await _plugin.zonedSchedule(
          i + 1,
          titreRappel(r.nombre),
          r.corps,
          quand,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: r.motId == null ? chargeRevisions : 'mot:${r.motId}',
        );
      } catch (e) {
        debugPrint('Rappel non programmé : $e');
      }
    }
  }

  @override
  Stream<String> get appuis => _appuis.stream;
}
