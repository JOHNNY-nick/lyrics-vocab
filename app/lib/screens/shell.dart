// Coquille : quatre onglets avec navigation imbriquée, bandeaux d'état, raccourcis PC
// (UI-04, UI-14, AND-23, MAQ-04, DES-13, DES-14, DES-25).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/divers.dart';
import '../providers/providers.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';
import '../widgets/navigation.dart';
import 'add_word_screen.dart';
import 'library_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'word_detail_screen.dart';

class Onglets {
  static const revisions = 0;
  static const mots = 1;
  static const ajouter = 2;
  static const reglages = 3;
}

final ongletProvider = StateProvider<int>((ref) => Onglets.revisions);

final clesNavigateurs = List.generate(4, (_) => GlobalKey<NavigatorState>());

/// Ouvre la fiche d'un mot sous l'onglet « Mots » (DES-14).
void ouvrirFiche(WidgetRef ref, String motId) {
  ref.read(ongletProvider.notifier).state = Onglets.mots;
  final navigateur = clesNavigateurs[Onglets.mots].currentState;
  navigateur?.popUntil((route) => route.isFirst);
  navigateur?.push(MaterialPageRoute<void>(builder: (_) => WordDetailScreen(motId: motId)));
}

class _IntentionOnglet extends Intent {
  const _IntentionOnglet(this.onglet);
  final int onglet;
}

class _IntentionRetour extends Intent {
  const _IntentionRetour();
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  StreamSubscription<String>? _appuis;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final env = ref.read(environnementProvider);
    _appuis = env.notifications.appuis.listen(_ouvrirDepuisNotification);
    env.notifications.chargeAuLancement().then((charge) {
      if (charge != null) _ouvrirDepuisNotification(charge);
    });
  }

  /// NOT-05 : « Révisions du jour », ou la fiche s'il n'y a qu'un mot.
  void _ouvrirDepuisNotification(String charge) {
    if (!mounted) return;
    if (charge.startsWith('mot:')) {
      ouvrirFiche(ref, charge.substring(4));
    } else {
      ref.read(ongletProvider.notifier).state = Onglets.revisions;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    final env = ref.read(environnementProvider);
    if (etat == AppLifecycleState.resumed) {
      unawaited(ref.read(connexionProvider.notifier).synchroniser()); // SYN-07 : reprise
      if (env.cache != null) {
        unawaited(env.notifications.reprogrammer(env.cache!, inclureAujourdhui: false));
      }
    } else if (etat == AppLifecycleState.paused && env.cache != null) {
      unawaited(env.notifications.reprogrammer(env.cache!)); // NOT-08
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appuis?.cancel();
    super.dispose();
  }

  void _choisir(int onglet) {
    final actuel = ref.read(ongletProvider);
    if (actuel == onglet) {
      clesNavigateurs[onglet].currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(ongletProvider.notifier).state = onglet;
  }

  bool _retour() {
    final onglet = ref.read(ongletProvider);
    final navigateur = clesNavigateurs[onglet].currentState;
    if (navigateur != null && navigateur.canPop()) {
      navigateur.pop();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final onglet = ref.watch(ongletProvider);
    final pc = context.estPc;
    final pages = [
      const ReviewScreen(),
      const LibraryScreen(),
      const AddWordScreen(),
      const SettingsScreen(),
    ];
    final contenu = Column(
      children: [
        const BandeauxEtat(),
        Expanded(
          child: IndexedStack(
            index: onglet,
            children: [
              for (var i = 0; i < pages.length; i++)
                HeroControllerScope.none(
                  child: Navigator(
                    key: clesNavigateurs[i],
                    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => pages[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true): _IntentionOnglet(Onglets.ajouter),
        SingleActivator(LogicalKeyboardKey.keyR, control: true): _IntentionOnglet(Onglets.revisions),
        SingleActivator(LogicalKeyboardKey.keyB, control: true): _IntentionOnglet(Onglets.mots),
        SingleActivator(LogicalKeyboardKey.escape): _IntentionRetour(),
      },
      child: Actions(
        actions: {
          _IntentionOnglet: CallbackAction<_IntentionOnglet>(
            onInvoke: (i) {
              _choisir(i.onglet);
              return null;
            },
          ),
          _IntentionRetour: CallbackAction<_IntentionRetour>(
            onInvoke: (_) {
              _retour();
              return null;
            },
          ),
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (aEteDepile, _) {
            if (aEteDepile || _retour()) return;
            if (ref.read(ongletProvider) != Onglets.revisions) {
              ref.read(ongletProvider.notifier).state = Onglets.revisions;
            } else {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            body: pc
                ? Row(
                    children: [
                      BarreLaterale(actif: onglet, onChoix: _choisir),
                      Expanded(child: contenu),
                    ],
                  )
                : contenu,
            bottomNavigationBar: pc ? null : BarreNavigation(actif: onglet, onChoix: _choisir),
          ),
        ),
      ),
    );
  }
}

/// Bandeaux sous la barre de titre, qui poussent le contenu (MAQ-04, G.7).
class BandeauxEtat extends ConsumerWidget {
  const BandeauxEtat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(environnementProvider);
    final connexion = ref.watch(connexionProvider);
    final file = ref.watch(fileActionsProvider);
    final bandeaux = <Widget>[];
    if (env.mobile) {
      if (connexion.etat == EtatConnexion.horsLigne) {
        bandeaux.add(const BandeauEtat(type: TypeBandeau.horsLigne, texte: S.horsLigne));
      } else if (connexion.etat == EtatConnexion.pcInjoignable) {
        bandeaux.add(const BandeauEtat(type: TypeBandeau.pcInjoignable, texte: S.pcInjoignable));
      }
      if (connexion.clientTropAncien) {
        bandeaux.add(const BandeauEtat(type: TypeBandeau.erreurSync, texte: S.misAJourRequise));
      } else if (file.aExaminer.isNotEmpty) {
        bandeaux.add(const BandeauEtat(type: TypeBandeau.erreurSync, texte: S.erreurSync));
      }
    }
    if (connexion.syncTerminee && env.mobile) {
      bandeaux.add(const BandeauEtat(type: TypeBandeau.syncTerminee, texte: S.syncTerminee));
    }
    if (bandeaux.isEmpty) return const SizedBox.shrink();
    return SafeArea(bottom: false, child: Column(children: bandeaux));
  }
}
