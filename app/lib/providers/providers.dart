// Fournisseurs Riverpod (22.2). Les écrans ne lisent que ces fournisseurs (FLU-01, CLI-06).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/divers.dart';
import '../models/mot.dart';
import '../models/revision.dart';
import '../services/api_client.dart';
import '../services/connectivite_service.dart';
import '../services/depot_donnees.dart';
import '../services/local_cache.dart';
import '../services/notifications_service.dart';
import '../services/prononciation_service.dart';
import '../services/sync_service.dart';

/// Tout ce qui dépend de la plateforme, construit au démarrage (main.dart) ou par les tests.
class Environnement {
  Environnement({
    required this.mobile,
    required this.api,
    required this.depot,
    required this.connectivite,
    required this.notifications,
    this.cache,
    this.sync,
    this.adresseModifiable = false,
    ServicePrononciation? prononciation,
  }) : prononciation = prononciation ?? PrononciationNeutre();

  final bool mobile;
  final ApiClient api;
  final DepotDonnees depot;
  final ServiceConnectivite connectivite;
  final ServiceNotifications notifications;
  final LocalCache? cache;
  final SyncService? sync;
  final bool adresseModifiable;

  /// Prononciation vocale des mots (synthèse vocale de l'appareil).
  final ServicePrononciation prononciation;
}

final environnementProvider = Provider<Environnement>((ref) => throw UnimplementedError());

final depotProvider = Provider<DepotDonnees>((ref) => ref.watch(environnementProvider).depot);

/// Incrémenté après chaque écriture locale ou synchronisation : les listes se rafraîchissent.
final versionDonneesProvider = StateProvider<int>((ref) => 0);

// --- Connexion et synchronisation ---------------------------------------------------------

@immutable
class EtatConnexionUI {
  const EtatConnexionUI({
    this.etat = EtatConnexion.aVerifier,
    this.syncTerminee = false,
    this.erreurSync = false,
    this.clientTropAncien = false,
    this.versionServeur,
    this.apk,
  });
  final EtatConnexion etat;
  final bool syncTerminee;
  final bool erreurSync;
  final bool clientTropAncien;
  final String? versionServeur;
  final Map<String, dynamic>? apk;

  bool get joignable => etat == EtatConnexion.enLigne || etat == EtatConnexion.synchronisation;

  EtatConnexionUI copyWith({
    EtatConnexion? etat,
    bool? syncTerminee,
    bool? erreurSync,
    bool? clientTropAncien,
    String? versionServeur,
    Map<String, dynamic>? apk,
  }) => EtatConnexionUI(
    etat: etat ?? this.etat,
    syncTerminee: syncTerminee ?? this.syncTerminee,
    erreurSync: erreurSync ?? this.erreurSync,
    clientTropAncien: clientTropAncien ?? this.clientTropAncien,
    versionServeur: versionServeur ?? this.versionServeur,
    apk: apk ?? this.apk,
  );
}

class ConnexionNotifier extends StateNotifier<EtatConnexionUI> {
  ConnexionNotifier(this.ref) : super(const EtatConnexionUI());
  final Ref ref;
  Timer? _effacement;

  Environnement get _env => ref.read(environnementProvider);

  /// Appelé par SyncService à chaque changement d'état.
  void surEtat(EtatConnexion etat, ResultatSync? resultat) {
    if (!mounted) return;
    final sante = _env.sync?.derniereSante;
    state = state.copyWith(
      etat: etat,
      erreurSync: resultat == ResultatSync.erreur || _env.cache?.aExaminer().isNotEmpty == true,
      clientTropAncien: resultat == ResultatSync.clientTropAncien,
      versionServeur: sante?.version,
      apk: sante?.apk,
    );
    if (resultat == ResultatSync.termine) {
      state = state.copyWith(syncTerminee: true);
      _effacement?.cancel();
      _effacement = Timer(const Duration(seconds: 3), () {
        if (mounted) state = state.copyWith(syncTerminee: false); // SYN-26
      });
      ref.read(versionDonneesProvider.notifier).state++;
    }
    ref.read(fileActionsProvider.notifier).actualiser();
  }

  /// Vérifie le serveur (PWA : écran « Le serveur ne répond pas », PWA-04).
  Future<bool> verifier() async {
    final sante = await _env.api.sante();
    if (!mounted) return sante != null;
    state = state.copyWith(
      etat: sante == null ? EtatConnexion.pcInjoignable : EtatConnexion.enLigne,
      versionServeur: sante?.version,
      apk: sante?.apk,
    );
    return sante != null;
  }

  /// Lance un cycle (mobile) ; [manuel] pour le bouton « Synchroniser maintenant ».
  Future<ResultatSync?> synchroniser({bool manuel = false}) async {
    final sync = _env.sync;
    if (sync == null) {
      await verifier();
      ref.read(versionDonneesProvider.notifier).state++;
      return null;
    }
    return sync.synchroniser(manuel: manuel);
  }

  @override
  void dispose() {
    _effacement?.cancel();
    super.dispose();
  }
}

final connexionProvider = StateNotifierProvider<ConnexionNotifier, EtatConnexionUI>(
  (ref) => ConnexionNotifier(ref),
);

@immutable
class EtatFile {
  const EtatFile({this.enAttente = 0, this.aExaminer = const []});
  final int enAttente;
  final List<OperationSync> aExaminer;
}

class FileActionsNotifier extends StateNotifier<EtatFile> {
  FileActionsNotifier(this.ref) : super(const EtatFile()) {
    actualiser();
  }
  final Ref ref;

  LocalCache? get _cache => ref.read(environnementProvider).cache;

  void actualiser() {
    final cache = _cache;
    if (cache == null || !mounted) return;
    state = EtatFile(enAttente: cache.file().length, aExaminer: cache.aExaminer());
  }

  Future<void> reessayer(String opId) async {
    await _cache?.reessayer(opId);
    actualiser();
    unawaited(ref.read(connexionProvider.notifier).synchroniser());
  }

  Future<void> abandonner(String opId) async {
    await _cache?.abandonner(opId);
    actualiser();
  }
}

final fileActionsProvider = StateNotifierProvider<FileActionsNotifier, EtatFile>(
  (ref) => FileActionsNotifier(ref),
);

/// Signale une écriture : rafraîchit les listes et le compteur d'actions en attente.
void signalerEcriture(Ref ref) {
  ref.read(versionDonneesProvider.notifier).state++;
  ref.read(fileActionsProvider.notifier).actualiser();
}

/// Même chose depuis un widget.
void signalerEcritureWidget(WidgetRef ref) {
  ref.read(versionDonneesProvider.notifier).state++;
  ref.read(fileActionsProvider.notifier).actualiser();
}

// --- Mots ---------------------------------------------------------------------------------

@immutable
class FiltresMots {
  const FiltresMots({this.niveau, this.q = '', this.tri = 'created_desc'});
  final String? niveau;
  final String q;
  final String tri;

  FiltresMots copyWith({Object? niveau = _absent, String? q, String? tri}) => FiltresMots(
    niveau: identical(niveau, _absent) ? this.niveau : niveau as String?,
    q: q ?? this.q,
    tri: tri ?? this.tri,
  );
}

const _absent = Object();

@immutable
class EtatMots {
  const EtatMots({
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.chargement = true,
    this.erreur,
    this.aSuite = false,
  });
  final List<Mot> items;
  final int total;
  final int page;
  final bool chargement;
  final Object? erreur;
  final bool aSuite;
}

final filtresMotsProvider = StateProvider<FiltresMots>((ref) => const FiltresMots());

/// Liste paginée filtrée (cache sur mobile, API sur PC) ; défilement continu par 50.
class MotsNotifier extends StateNotifier<EtatMots> {
  MotsNotifier(this.ref) : super(const EtatMots()) {
    charger();
  }
  final Ref ref;
  static const taille = 50;
  int _generation = 0;

  Future<void> charger() async {
    final generation = ++_generation;
    state = EtatMots(items: state.items, total: state.total, chargement: true);
    try {
      final f = ref.read(filtresMotsProvider);
      final page = await ref
          .read(depotProvider)
          .listerMots(niveau: f.niveau, q: f.q, tri: f.tri, page: 1, taille: taille);
      if (!mounted || generation != _generation) return;
      state = EtatMots(items: page.items, total: page.total, page: 1, chargement: false, aSuite: page.aSuite);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = EtatMots(items: state.items, total: state.total, chargement: false, erreur: e);
    }
  }

  Future<void> chargerSuite() async {
    if (state.chargement || !state.aSuite) return;
    final generation = _generation;
    state = EtatMots(
      items: state.items,
      total: state.total,
      page: state.page,
      chargement: true,
      aSuite: true,
    );
    try {
      final f = ref.read(filtresMotsProvider);
      final page = await ref
          .read(depotProvider)
          .listerMots(niveau: f.niveau, q: f.q, tri: f.tri, page: state.page + 1, taille: taille);
      if (!mounted || generation != _generation) return;
      state = EtatMots(
        items: [...state.items, ...page.items],
        total: page.total,
        page: page.page,
        chargement: false,
        aSuite: page.aSuite,
      );
    } catch (e) {
      if (!mounted) return;
      state = EtatMots(
        items: state.items,
        total: state.total,
        page: state.page,
        chargement: false,
        erreur: e,
      );
    }
  }

  Future<void> supprimer(String id) async {
    await ref.read(depotProvider).supprimerMot(id);
    signalerEcriture(ref);
  }
}

final motsProvider = StateNotifierProvider<MotsNotifier, EtatMots>((ref) {
  ref.watch(filtresMotsProvider);
  ref.watch(versionDonneesProvider);
  return MotsNotifier(ref);
});

/// Trois derniers mots ajoutés (écran d'ajout, 27.3).
final derniersMotsProvider = FutureProvider.autoDispose<List<Mot>>((ref) async {
  ref.watch(versionDonneesProvider);
  return ref.watch(depotProvider).derniersMots(3);
});

const delaiPollingWeb = Duration(seconds: 2);
const delaiPollingMobile = Duration(seconds: 3);
const dureeMaxPolling = Duration(seconds: 90);

/// État de la fiche : le mot et le dépassement éventuel du délai d'attente (19.4, étape 6).
@immutable
class EtatFiche {
  const EtatFiche(this.mot, {this.delaiDepasse = false});
  final Mot? mot;
  final bool delaiDepasse;
}

/// Fiche d'un mot, avec interrogation de l'enrichissement jusqu'à un statut final (ENR-05).
final motDetailProvider = StreamProvider.autoDispose.family<EtatFiche, String>((ref, id) async* {
  final env = ref.watch(environnementProvider);
  final depot = env.depot;
  final debut = DateTime.now();
  var mot = await depot.obtenirMot(id);
  yield EtatFiche(mot);
  while (mot != null && !mot.enrichissementTermine) {
    if (DateTime.now().difference(debut) > dureeMaxPolling) {
      yield EtatFiche(mot, delaiDepasse: true);
      return;
    }
    await Future<void>.delayed(env.mobile ? delaiPollingMobile : delaiPollingWeb);
    if (env.mobile) await env.sync?.synchroniser();
    mot = await depot.obtenirMot(id);
    yield EtatFiche(mot);
  }
});

// --- Révisions ----------------------------------------------------------------------------

final revisionsDuesProvider = FutureProvider<RevisionsDues>((ref) async {
  ref.watch(versionDonneesProvider);
  return ref.watch(depotProvider).revisionsDues();
});

// --- Réglages et artistes -----------------------------------------------------------------

class ReglagesNotifier extends StateNotifier<AsyncValue<Reglages>> {
  ReglagesNotifier(this.ref) : super(const AsyncValue.loading()) {
    charger();
  }
  final Ref ref;

  Future<void> charger() async {
    state = await AsyncValue.guard(() => ref.read(depotProvider).reglages());
  }

  /// Aperçu pendant le glissement du curseur, sans enregistrement.
  void apercu(Reglages reglages) => state = AsyncValue.data(reglages);

  /// Enregistrement immédiat (US-07) ; le web écrit par l'API, le mobile en local puis file.
  Future<void> modifier(Reglages nouveaux) async {
    final precedents = state.valueOrNull;
    state = AsyncValue.data(nouveaux);
    try {
      await ref.read(depotProvider).enregistrerReglages(nouveaux);
      signalerEcriture(ref);
      final env = ref.read(environnementProvider);
      if (env.cache != null) await env.notifications.reprogrammer(env.cache!);
    } catch (e) {
      if (precedents != null) state = AsyncValue.data(precedents);
      rethrow;
    }
  }
}

final reglagesProvider = StateNotifierProvider<ReglagesNotifier, AsyncValue<Reglages>>((ref) {
  ref.watch(versionDonneesProvider);
  return ReglagesNotifier(ref);
});

final artistesPreferesProvider = FutureProvider<List<Artiste>>((ref) async {
  ref.watch(versionDonneesProvider);
  return ref.watch(depotProvider).artistesPreferes();
});

final suggestionsProvider = FutureProvider<List<Artiste>>((ref) async {
  return ref.watch(depotProvider).suggestions();
});

/// Enregistre la liste ordonnée des artistes préférés.
Future<void> enregistrerArtistes(WidgetRef ref, List<Artiste> artistes) async {
  await ref.read(depotProvider).enregistrerArtistes(artistes);
  ref.read(versionDonneesProvider.notifier).state++;
  ref.read(fileActionsProvider.notifier).actualiser();
}

/// Onboarding déjà fait : sur mobile, dans la méta ; sur le web, si des artistes existent.
final onboardingFaitProvider = StateProvider<bool?>((ref) => null);
