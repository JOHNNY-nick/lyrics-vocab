// Écran « Fiche d'un mot » (US-03, 27.4, 43.6, 3-fiche-du-mot.html).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/mot.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/prononciation_service.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';
import '../widgets/icones.dart';
import 'exercise_screen.dart';

class WordDetailScreen extends ConsumerWidget {
  const WordDetailScreen({super.key, required this.motId});
  final String motId;

  static const hauteurSqueletteTraduction = 76.0;
  static const hauteurSqueletteExtrait = 120.0;
  static const hauteurSqueletteExplication = 110.0;

  Future<void> _supprimer(BuildContext context, WidgetRef ref) async {
    if (!await confirmer(context, titre: S.suppressionQuestion, action: S.supprimer)) return;
    if (!context.mounted) return;
    final navigateur = Navigator.of(context);
    final messager = ScaffoldMessenger.of(context);
    navigateur.pop(); // UI-12 : retour à la bibliothèque
    var annule = false;
    messager.hideCurrentSnackBar();
    messager
        .showSnackBar(
          SnackBar(
            content: const Text(S.motSupprime),
            duration: Durees.annulation,
            action: SnackBarAction(label: S.annuler, onPressed: () => annule = true),
          ),
        )
        .closed
        .then((_) async {
          if (annule) return; // la suppression n'est envoyée qu'après 5 s
          await ref.read(depotProvider).supprimerMot(motId);
          signalerEcritureWidget(ref);
        });
  }

  Future<void> _relancer(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(depotProvider).relancerEnrichissement(motId);
      ref.invalidate(motDetailProvider(motId));
    } on HorsLigneException {
      if (context.mounted) afficherMessage(context, S.horsLigneFonction);
    } on ErreurApi catch (e) {
      if (context.mounted) afficherMessage(context, e.code == 'quota_depasse' ? S.quotaAtteint : e.message);
    } on Exception {
      if (context.mounted) afficherMessage(context, S.serveurMuet);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final fiche = ref.watch(motDetailProvider(motId));
    return Scaffold(
      body: fiche.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(Espaces.e20),
            child: Squelette(hauteur: Tailles.enTeteFiche),
          ),
        ),
        error: (_, _) => Center(
          child: EtatErreur(
            message: S.serveurMuet,
            onReessayer: () => ref.invalidate(motDetailProvider(motId)),
          ),
        ),
        data: (etat) {
          final mot = etat.mot;
          if (mot == null) {
            return Center(
              child: EtatVide(
                icone: Icones.mots,
                titre: S.motSupprime,
                texte: '',
                action: S.fermer,
                onAction: () => Navigator.of(context).maybePop(),
              ),
            );
          }
          return _Fiche(
            mot: mot,
            delaiDepasse: etat.delaiDepasse,
            onSupprimer: () => _supprimer(context, ref),
            onRelancer: () => _relancer(context, ref),
            couleurs: c,
            prononciation: ref.read(environnementProvider).prononciation,
          );
        },
      ),
    );
  }
}

class _Fiche extends StatelessWidget {
  const _Fiche({
    required this.mot,
    required this.delaiDepasse,
    required this.onSupprimer,
    required this.onRelancer,
    required this.couleurs,
    required this.prononciation,
  });
  final Mot mot;
  final ServicePrononciation prononciation;
  final bool delaiDepasse;
  final VoidCallback onSupprimer;
  final VoidCallback onRelancer;
  final Couleurs couleurs;

  bool get _enCours => !mot.enrichissementTermine && !delaiDepasse;

  Widget _apparition(BuildContext context, Widget enfant, {required Object cle}) => AnimatedSwitcher(
    duration: context.animationsReduites ? Duration.zero : Durees.apparition,
    child: KeyedSubtree(key: ValueKey(cle), child: enfant),
  );

  @override
  Widget build(BuildContext context) {
    final c = couleurs;
    final largeur = MediaQuery.sizeOf(context).width;
    final deuxColonnes = largeur >= Ruptures.ficheDeuxColonnes;
    final pc = context.estPc;
    final (libelleNiveau, _, _, _) = styleNiveau(context, mot.niveau);

    final enTete = EnTeteColore(
      fond: c.turquoise,
      hauteur: Tailles.enTeteFiche,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Navigator.of(context).canPop())
            BoutonIcone(
              forme: Icones.retour,
              libelle: S.fermer,
              couleur: c.vertTexte,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          BoutonIcone(
            forme: Icones.plusDActions,
            libelle: S.plusDActions,
            couleur: c.vertTexte,
            onPressed: () async {
              final choix = await showModalBottomSheet<bool>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => PanneauBas(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BoutonPrincipal(
                        libelle: S.supprimerCeMot,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      BoutonLien(libelle: S.annuler, onPressed: () => Navigator.of(context).pop(false)),
                    ],
                  ),
                ),
              );
              if (choix == true) onSupprimer();
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.ficheDuMot, style: Textes.date.copyWith(color: c.vertTexte)),
          Padding(
            padding: const EdgeInsets.only(top: Espaces.e10, bottom: Espaces.e12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(mot.terme, style: Textes.titreMot.copyWith(color: c.vertTexte)),
                  ),
                ),
                const SizedBox(width: Espaces.e8),
                BoutonPrononciation(mot: mot.terme, service: prononciation, couleur: c.vertTexte),
              ],
            ),
          ),
          Wrap(
            spacing: Espaces.e8,
            runSpacing: Espaces.e8,
            children: [
              if (mot.estArgot) PastilleSimple(libelle: S.argot, fond: c.jaune, texte: c.surAccent),
              PastilleSimple(libelle: libelleNiveau, fond: c.surface, texte: c.encre),
            ],
          ),
          if (!pc) const SizedBox(height: Tailles.chevauchementFiche + Espaces.e20),
        ],
      ),
    );

    final traduction = mot.traductionFr != null
        ? CarteFiche(
            libelle: S.traduction,
            child: Padding(
              padding: const EdgeInsets.only(top: Espaces.e4),
              child: Text(mot.traductionFr!, style: Textes.titreCarte.copyWith(color: c.encre)),
            ),
          )
        : _enCours
        ? const Squelette(hauteur: WordDetailScreen.hauteurSqueletteTraduction)
        : CarteFiche(
            libelle: S.traduction,
            child: Padding(
              padding: const EdgeInsets.only(top: Espaces.e6),
              child: Text(S.traductionIndisponible, style: Textes.corps.copyWith(color: c.texteSecondaire)),
            ),
          );

    final extraits = <Widget>[];
    if (mot.extraits.isNotEmpty) {
      for (var i = 0; i < mot.extraits.length && i < 3; i++) {
        final e = mot.extraits[i];
        extraits.add(
          CarteFiche(
            libelle: mot.extraits.length > 1 ? S.extraitNumero(i + 1) : S.extrait,
            child: Padding(
              padding: const EdgeInsets.only(top: Espaces.e6),
              child: ExtraitSurligne.depuis(e),
            ),
            pied: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Espaces.e8),
                  child: Text(
                    '${e.titre} — ${e.artiste}',
                    style: Textes.legende.copyWith(color: c.texteSecondaire),
                  ),
                ),
                LienChanson(extrait: e),
                if (e.horsListe)
                  Padding(
                    padding: const EdgeInsets.only(top: Espaces.e8),
                    child: PastilleSimple(
                      libelle: S.horsListe,
                      fond: c.nouveauFond,
                      texte: c.surAccent,
                      rayon: Rayons.pastilleListe,
                      padding: const EdgeInsets.symmetric(horizontal: Espaces.e10, vertical: Espaces.e4),
                      style: Textes.pastilleNiveau,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    } else if (_enCours) {
      extraits.add(const Squelette(hauteur: WordDetailScreen.hauteurSqueletteExtrait));
    } else {
      extraits.add(
        CarteFiche(
          libelle: S.extrait,
          child: Padding(
            padding: const EdgeInsets.only(top: Espaces.e6),
            child: Text(S.aucunExtrait, style: Textes.corps.copyWith(color: c.texteSecondaire)),
          ),
        ),
      );
    }

    final Widget explication;
    if (mot.explicationIA) {
      explication = BlocExplication(texte: mot.explication!);
    } else if (_enCours) {
      explication = const Squelette(hauteur: WordDetailScreen.hauteurSqueletteExplication);
    } else {
      explication = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: Espaces.e20, vertical: Espaces.e18),
        decoration: BoxDecoration(color: c.lavande, borderRadius: BorderRadius.circular(Rayons.carte)),
        child: Text(S.iaIndisponible, style: Textes.corps.copyWith(color: c.violetFonce)),
      );
    }

    final prochaine = mot.prochaineRevision == null
        ? S.aucuneEcheance
        : DateFormat('d MMM', 'fr_FR').format(mot.prochaineRevision!);
    final tuiles = Row(
      children: [
        Expanded(
          child: TuileInfo(valeur: prochaine, legende: S.prochaineRevision, couleur: c.rose),
        ),
        const SizedBox(width: Espaces.e12),
        Expanded(
          child: TuileInfo(valeur: '${mot.nbEchecs}', legende: S.echecs(mot.nbEchecs), couleur: c.violet),
        ),
      ],
    );

    final entrainement = mot.traductionFr == null
        ? Text(S.exerciceSansTraduction, style: Textes.legende.copyWith(color: c.texteSecondaire))
        : BoutonPrincipal(
            libelle: S.sEntrainer,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExerciseScreen(motId: mot.id, terme: mot.terme),
              ),
            ),
          );

    final messages = <Widget>[
      if (_enCours)
        Semantics(
          liveRegion: true,
          child: Text(S.enrichissementEnCours, style: Textes.legende.copyWith(color: c.texteSecondaire)),
        ),
      if (delaiDepasse && !mot.enrichissementTermine)
        Text(S.pluslongQuePrevu, style: Textes.legende.copyWith(color: c.texteSecondaire)),
      if (mot.statutEnrichissement == 'partiel' || mot.statutEnrichissement == 'echec')
        Center(
          child: BoutonLien(libelle: S.reessayerEnrichissement, onPressed: onRelancer),
        ),
    ];

    Widget colonne(List<Widget> enfants) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < enfants.length; i++) ...[
          if (i > 0) const SizedBox(height: Espaces.e14),
          enfants[i],
        ],
      ],
    );

    final gauche = [
      _apparition(context, traduction, cle: 't${mot.traductionFr}$_enCours'),
      _apparition(context, explication, cle: 'e${mot.explication}$_enCours'),
      entrainement, // juste sous l'explication
      if (mot.exemples.isNotEmpty) BlocExemples(exemples: mot.exemples, prononciation: prononciation),
    ];
    final droite = [
      _apparition(context, colonne(extraits), cle: 'x${mot.extraits.length}$_enCours'),
      tuiles,
      ...messages,
    ];

    final corps = deuxColonnes
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: colonne(gauche)),
              const SizedBox(width: Espaces.e14),
              Expanded(child: colonne(droite)),
            ],
          )
        : colonne([gauche[0], droite.first, ...gauche.skip(1), ...droite.skip(1)]);

    return SingleChildScrollView(
      child: ContenuCentre(
        child: Padding(
          padding: pc ? const EdgeInsets.all(Espaces.margePc) : EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              enTete,
              Transform.translate(
                offset: Offset(0, pc ? 0 : -Tailles.chevauchementFiche),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    pc ? 0 : Espaces.margeEcran,
                    pc ? Espaces.e14 : 0,
                    pc ? 0 : Espaces.margeEcran,
                    Espaces.e24,
                  ),
                  child: corps,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
