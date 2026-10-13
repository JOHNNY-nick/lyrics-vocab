// Application : thèmes, langue, premier lancement, serveur muet, synchronisation au lancement.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/divers.dart';
import 'providers/providers.dart';
import 'screens/code_acces_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'services/local_cache.dart';
import 'services/plateforme.dart';
import 'services/sync_service.dart';
import 'strings.dart';
import 'theme/jetons.dart';
import 'theme/theme.dart';
import 'widgets/composants.dart';
import 'widgets/icones.dart';

const intervalleVersion = Duration(minutes: 5);

/// Préférences locales (premier lancement, appareil_id), Hive sur toutes les plateformes.
final prefsProvider = Provider<Magasin>((ref) => throw UnimplementedError());

const clePrefTheme = 'theme';

/// Thème choisi dans les Réglages : clair par défaut, comme le design (voir DECISIONS.md).
final themeProvider = StateProvider<ThemeMode>((ref) {
  final valeur = ref.watch(prefsProvider).lire(clePrefTheme)?['v'];
  return switch (valeur) {
    'sombre' => ThemeMode.dark,
    'systeme' => ThemeMode.system,
    _ => ThemeMode.light,
  };
});

/// Enregistre le thème choisi.
Future<void> choisirTheme(WidgetRef ref, ThemeMode mode) async {
  ref.read(themeProvider.notifier).state = mode;
  final valeur = switch (mode) {
    ThemeMode.dark => 'sombre',
    ThemeMode.system => 'systeme',
    ThemeMode.light => 'clair',
  };
  await ref.read(prefsProvider).ecrire(clePrefTheme, {'v': valeur});
}

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => _ApplicationState();
}

class _ApplicationState extends ConsumerState<Application> {
  final _messager = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<TypeReseau>? _reseau;
  Timer? _version;
  String? _versionWeb;

  @override
  void initState() {
    super.initState();
    final env = ref.read(environnementProvider);
    final connexion = ref.read(connexionProvider.notifier);
    final sync = env.sync;
    if (sync != null) {
      sync.surEtat = connexion.surEtat;
      sync.apresSync = () async {
        if (env.cache != null) await env.notifications.reprogrammer(env.cache!, inclureAujourdhui: false);
      };
      // SYN-07 : retour du réseau.
      _reseau = env.connectivite.changements.listen((type) {
        if (type != TypeReseau.aucun) {
          unawaited(sync.synchroniser());
        } else {
          connexion.surEtat(EtatConnexion.horsLigne, ResultatSync.horsLigne);
        }
      });
    }
    unawaited(_demarrer());
  }

  Future<void> _demarrer() async {
    final env = ref.read(environnementProvider);
    await env.notifications.initialiser();
    if (env.mobile) {
      // AND-06 : l'écran s'affiche depuis le cache, la synchronisation suit (AND-07, AND-12).
      final resultat = await ref.read(connexionProvider.notifier).synchroniser();
      if (env.cache?.reinitialise == true &&
          (resultat == ResultatSync.pcInjoignable || resultat == ResultatSync.horsLigne)) {
        _messager.currentState?.showSnackBar(const SnackBar(content: Text(S.donneesLocalesVides)));
      }
      if (env.cache != null) await env.notifications.reprogrammer(env.cache!, inclureAujourdhui: false);
    } else {
      await ref.read(connexionProvider.notifier).verifier();
      _version = Timer.periodic(intervalleVersion, (_) => _verifierVersion());
      unawaited(_verifierVersion());
    }
    // DES-13 : Révisions s'il y a des mots dus, sinon Mots.
    try {
      final dues = await ref.read(revisionsDuesProvider.future);
      if (mounted && dues.totalDus == 0) ref.read(ongletProvider.notifier).state = Onglets.mots;
    } catch (_) {
      // l'écran affichera son état d'erreur
    }
  }

  /// PWA-07 : « Une nouvelle version est disponible » si version.json change pendant l'usage.
  Future<void> _verifierVersion() async {
    try {
      final reponse = await Dio().get<dynamic>(
        '${originePage()}/version.json',
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
      );
      final donnees = reponse.data is Map ? reponse.data as Map : null;
      final version = '${donnees?['version']}+${donnees?['build_number']}';
      if (_versionWeb == null) {
        _versionWeb = version;
      } else if (version != _versionWeb) {
        _messager.currentState?.showSnackBar(
          SnackBar(
            content: const Text(S.nouvelleVersion),
            duration: const Duration(days: 1),
            action: SnackBarAction(label: S.actualiserPage, onPressed: rechargerPage),
          ),
        );
        _version?.cancel();
      }
    } catch (_) {
      // hors ligne : nouvelle tentative au prochain intervalle
    }
  }

  @override
  void dispose() {
    _reseau?.cancel();
    _version?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: S.nomApplication,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messager,
      theme: construireTheme(Couleurs.clair, Brightness.light),
      darkTheme: construireTheme(Couleurs.sombre, Brightness.dark),
      themeMode: ref.watch(themeProvider),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Racine(),
    );
  }
}

/// Premier lancement → choix des artistes ; PWA sans serveur → écran dédié ; sinon la coquille.
class Racine extends ConsumerStatefulWidget {
  const Racine({super.key});

  @override
  ConsumerState<Racine> createState() => _RacineState();
}

class _RacineState extends ConsumerState<Racine> {
  late bool _onboardingFait = ref.read(prefsProvider).lire(Meta.onboardingFait)?['v'] == true;

  Future<void> _terminerOnboarding() async {
    await ref.read(prefsProvider).ecrire(Meta.onboardingFait, {'v': true});
    if (mounted) setState(() => _onboardingFait = true);
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(environnementProvider);
    final connexion = ref.watch(connexionProvider);
    final violet = context.couleurs.violet;
    final fond = context.couleurs.fond;
    final enTeteViolet = !_onboardingFait || ref.watch(ongletProvider) == Onglets.revisions;
    final sombre = Theme.of(context).brightness == Brightness.dark;
    // DES-17 : barre d'état violette sur les révisions et les artistes, fond ailleurs.
    final style = (enTeteViolet || sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: enTeteViolet ? violet : fond,
    );
    Widget enfant;
    if (!env.mobile && connexion.etat == EtatConnexion.aVerifier) {
      enfant = const Scaffold(body: SizedBox.shrink());
    } else if (!env.mobile && connexion.etat == EtatConnexion.pcInjoignable) {
      enfant = const _ServeurMuet();
    } else if (env.mobile && connexion.etat == EtatConnexion.codeAccesRequis) {
      enfant = const CodeAccesScreen();
    } else if (!_onboardingFait) {
      enfant = OnboardingScreen(onTermine: _terminerOnboarding);
    } else {
      enfant = const Shell();
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: enfant);
  }
}

/// PWA-04 : « Le serveur ne répond pas » avec un bouton pour réessayer.
class _ServeurMuet extends ConsumerWidget {
  const _ServeurMuet();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(Espaces.margeEcran),
        child: ContenuCentre(
          largeurMax: Tailles.carteRevisionPcMax,
          child: EtatVide(
            icone: Icones.nuage,
            titre: S.erreurGenerique,
            texte: S.serveurMuet,
            action: S.reessayer,
            erreur: true,
            onAction: () async {
              if (await ref.read(connexionProvider.notifier).verifier()) {
                ref.read(versionDonneesProvider.notifier).state++;
              }
            },
          ),
        ),
      ),
    ),
  );
}
