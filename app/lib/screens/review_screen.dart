// Écran « Révisions du jour » : accueil, session, exercice, récapitulatif
// (US-05, US-06, REV-10 à REV-18, 27.2, 43.6, 43.9, 2-revisions-du-jour.html).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/revision.dart';
import '../providers/providers.dart';
import '../providers/session.dart';
import '../services/local_cache.dart';
import '../services/sm2.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';
import '../widgets/icones.dart';
import 'shell.dart';

const secondesParMot = 25;

String _majuscule(String texte) => texte.isEmpty ? texte : texte[0].toUpperCase() + texte.substring(1);

String dateLongue(DateTime jour) => _majuscule(DateFormat('EEEE d MMMM', 'fr_FR').format(jour));

String dateFiche(DateTime jour) => DateFormat('EEEE d MMMM', 'fr_FR').format(jour);

class _Reveler extends Intent {
  const _Reveler();
}

class _Repondre extends Intent {
  const _Repondre(this.qualite);
  final int qualite;
}

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionRevisionProvider);
    final Widget corps;
    if (session.demarree && session.termine && !session.enAttente) {
      corps = const _Recapitulatif();
    } else if (session.demarree && !session.termine) {
      corps = const _Session();
    } else if (session.demarree && session.termine) {
      corps = const _Session(); // dernière réponse encore annulable
    } else {
      corps = const _Accueil();
    }
    return Scaffold(body: corps);
  }
}

/// Mise en page commune : en-tête violet puis bloc qui le chevauche (DES-27).
class _AvecEnTete extends StatelessWidget {
  const _AvecEnTete({
    required this.enTete,
    required this.contenu,
    this.fond,
    this.hauteur = Tailles.enTeteRevisions,
    this.actions,
  });
  final Widget? actions;
  final Widget enTete;
  final Widget contenu;
  final Color? fond;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final pc = context.estPc;
    return SingleChildScrollView(
      child: ContenuCentre(
        child: Padding(
          padding: pc ? const EdgeInsets.all(Espaces.margePc) : EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnTeteColore(
                fond: fond ?? context.couleurs.violet,
                hauteur: hauteur,
                actions: actions,
                child: enTete,
              ),
              if (pc)
                Padding(
                  padding: const EdgeInsets.only(top: Espaces.e20),
                  child: ContenuCentre(largeurMax: Tailles.carteRevisionPcMax, child: contenu),
                )
              else
                Transform.translate(
                  offset: const Offset(0, -Tailles.chevauchementRevision),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Espaces.margeEcran),
                    child: contenu,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneDate extends StatelessWidget {
  const _LigneDate({required this.jour, required this.serie});
  final DateTime jour;
  final int serie;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Row(
      children: [
        Expanded(
          child: Opacity(
            opacity: Opacites.dateEnTete,
            child: Text(dateLongue(jour), style: Textes.date.copyWith(color: c.surViolet)),
          ),
        ),
        if (serie >= 2)
          PastilleSimple(libelle: S.serie(serie), fond: c.jaune, texte: c.surAccent, rayon: Rayons.serie),
      ],
    );
  }
}

class _EnTeteRevisions extends StatelessWidget {
  const _EnTeteRevisions({required this.jour, required this.serie, required this.fait, required this.total});
  final DateTime jour;
  final int serie;
  final int fait;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LigneDate(jour: jour, serie: serie),
        Padding(
          padding: const EdgeInsets.only(top: Espaces.e14, bottom: Espaces.e6),
          child: Semantics(
            header: true,
            child: Text(S.revisionsDuJour, style: Textes.titreEcran.copyWith(color: c.surViolet)),
          ),
        ),
        Opacity(
          opacity: Opacites.sousTitreEnTete,
          child: Text(S.progression(fait, total), style: Textes.corps.copyWith(color: c.surViolet)),
        ),
        const SizedBox(height: Espaces.e12),
        BarreProgression(valeur: total == 0 ? 0 : fait / total),
      ],
    );
  }
}

BoxDecoration _carte(Couleurs c) => BoxDecoration(
  color: c.surface,
  borderRadius: BorderRadius.circular(Rayons.carteLarge),
  boxShadow: Ombres.carteRevision(c),
);

// --- Accueil ------------------------------------------------------------------------------

class _Accueil extends ConsumerWidget {
  const _Accueil();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final dues = ref.watch(revisionsDuesProvider);
    final file = ref.watch(fileActionsProvider);
    return dues.when(
      loading: () => _AvecEnTete(
        enTete: _EnTeteRevisions(jour: DateTime.now(), serie: 0, fait: 0, total: 0),
        contenu: const Squelette(hauteur: 220, rayon: Rayons.carteLarge),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(Espaces.margeEcran),
        child: Center(
          child: EtatErreur(message: S.serveurMuet, onReessayer: () => ref.invalidate(revisionsDuesProvider)),
        ),
      ),
      data: (resultat) {
        final total = resultat.totalDus;
        final enTete = _EnTeteRevisions(jour: resultat.jour, serie: resultat.serie, fait: 0, total: total);
        if (total == 0) {
          final prochaine = resultat.prochaineDate == null ? null : dateFiche(resultat.prochaineDate!);
          return _AvecEnTete(
            enTete: enTete,
            contenu: Container(
              padding: const EdgeInsets.all(Espaces.e24),
              decoration: _carte(c),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(S.aucuneRevision(prochaine), style: Textes.titreCarte.copyWith(color: c.encre)),
                  if (file.enAttente > 0) ...[
                    const SizedBox(height: Espaces.e14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BadgeAttente(nombre: file.enAttente),
                    ),
                  ],
                  const SizedBox(height: Espaces.e20),
                  BoutonLien(
                    libelle: S.ajouterUnMot,
                    onPressed: () => ref.read(ongletProvider.notifier).state = Onglets.ajouter,
                  ),
                ],
              ),
            ),
          );
        }
        // La phrase du premier mot se prépare pendant que l'accueil est affiché.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => ref.read(sessionRevisionProvider.notifier).preparer(resultat.items.first),
        );
        final minutes = ((total * secondesParMot) / 60).ceil();
        return _AvecEnTete(
          enTete: enTete,
          contenu: Container(
            padding: const EdgeInsets.all(Espaces.e24),
            decoration: _carte(c),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(S.motsAReviser(total), style: Textes.titreCarte.copyWith(color: c.encre)),
                const SizedBox(height: Espaces.e4),
                Text(S.dureeEstimee(minutes), style: Textes.corps.copyWith(color: c.texteSecondaire)),
                if (file.enAttente > 0) ...[
                  const SizedBox(height: Espaces.e14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BadgeAttente(nombre: file.enAttente),
                  ),
                ],
                const SizedBox(height: Espaces.e20),
                // Chaque mot du jour est employé dans une phrase à traduire (demande de
                // l'utilisateur) ; la révision rapide garde la carte « mot masqué ».
                BoutonPrincipal(
                  libelle: S.commencer,
                  autofocus: context.estPc,
                  onPressed: () =>
                      ref.read(sessionRevisionProvider.notifier).demarrer(resultat.items, exercices: true),
                ),
                const SizedBox(height: Espaces.e6),
                BoutonLien(
                  libelle: S.revisionRapide,
                  onPressed: () => ref.read(sessionRevisionProvider.notifier).demarrer(resultat.items),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- Session ------------------------------------------------------------------------------

class _Session extends ConsumerStatefulWidget {
  const _Session();

  @override
  ConsumerState<_Session> createState() => _SessionState();
}

class _SessionState extends ConsumerState<_Session> {
  final _reponse = TextEditingController();
  final _focus = FocusNode(debugLabel: 'session');

  @override
  void dispose() {
    _reponse.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _fermer() async {
    final session = ref.read(sessionRevisionProvider);
    if (session.revises > 0 || session.revele) {
      final ok = await confirmer(
        context,
        titre: S.fermerSession,
        texte: S.fermerSessionTexte,
        action: S.quitter,
      );
      if (!ok) return;
    }
    ref.read(sessionRevisionProvider.notifier).terminer();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final session = ref.watch(sessionRevisionProvider);
    final notifier = ref.read(sessionRevisionProvider.notifier);
    final optionFacile = ref.watch(environnementProvider).cache?.meta(Meta.optionFacile) == true;
    final jour = ref.watch(revisionsDuesProvider).valueOrNull?.jour ?? DateTime.now();
    final carte = session.carte;
    final production =
        session.phase == PhaseExercice.saisie ||
        session.phase == PhaseExercice.evaluation ||
        session.phase == PhaseExercice.verdict ||
        session.phase == PhaseExercice.chargement;

    final enTete = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_EnTeteRevisions(jour: jour, serie: 0, fait: session.index, total: session.file.length)],
    );

    Widget contenu;
    if (carte == null) {
      contenu = const SizedBox.shrink();
    } else if (production) {
      contenu = _CarteExercice(carte: carte, controleur: _reponse);
    } else {
      contenu = _CarteRappel(
        carte: carte,
        revele: session.revele,
        message: session.phase == PhaseExercice.indisponible
            ? (session.messageIA ?? S.exerciceIndisponible)
            : null,
      );
    }

    final reponses = carte == null || production
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Tailles.ecartReponses),
              Row(
                children: [
                  Expanded(
                    child: BoutonPrincipal(
                      libelle: S.neSavaisPas,
                      type: TypeBouton.negatif,
                      onPressed: session.revele ? () => notifier.repondre(Notes.neSavaisPas) : null,
                    ),
                  ),
                  const SizedBox(width: Espaces.e12),
                  Expanded(
                    child: BoutonPrincipal(
                      libelle: S.savais,
                      type: TypeBouton.positif,
                      onPressed: session.revele ? () => notifier.repondre(Notes.savais) : null,
                    ),
                  ),
                ],
              ),
              if (optionFacile && session.revele) ...[
                const SizedBox(height: Espaces.e8),
                BoutonLien(libelle: S.facile, onPressed: () => notifier.repondre(Notes.facile)),
              ],
              if (!session.revele) ...[
                const SizedBox(height: Tailles.ecartAide),
                Text(
                  S.aideBoutons,
                  textAlign: TextAlign.center,
                  style: Textes.legende.copyWith(color: c.texteSecondaire),
                ),
              ],
            ],
          );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): _Reveler(),
        SingleActivator(LogicalKeyboardKey.digit1): _Repondre(Notes.neSavaisPas),
        SingleActivator(LogicalKeyboardKey.digit2): _Repondre(Notes.savais),
        SingleActivator(LogicalKeyboardKey.numpad1): _Repondre(Notes.neSavaisPas),
        SingleActivator(LogicalKeyboardKey.numpad2): _Repondre(Notes.savais),
      },
      child: Actions(
        actions: {
          _Reveler: CallbackAction<_Reveler>(
            onInvoke: (_) {
              if (!production) notifier.reveler();
              return null;
            },
          ),
          _Repondre: CallbackAction<_Repondre>(
            onInvoke: (i) {
              if (!production) notifier.repondre(i.qualite);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focus,
          autofocus: !production,
          child: Stack(
            children: [
              Positioned.fill(
                child: _AvecEnTete(
                  // Pendant la session, le bouton fermer occupe le coin haut droit (la série
                  // reste affichée sur l'accueil des révisions, voir DECISIONS.md).
                  actions: BoutonIcone(
                    forme: Icones.fermer,
                    libelle: S.fermer,
                    couleur: c.surViolet,
                    onPressed: _fermer,
                  ),
                  enTete: enTete,
                  contenu: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (session.termine)
                        Container(
                          padding: const EdgeInsets.all(Espaces.e24),
                          decoration: _carte(c),
                          child: Text(
                            S.reponseEnregistree,
                            style: Textes.titreCarte.copyWith(color: c.encre),
                          ),
                        )
                      else
                        contenu,
                      reponses,
                      const SizedBox(height: Espaces.e32 * 3),
                    ],
                  ),
                ),
              ),
              if (session.enAttente)
                Positioned(
                  left: Espaces.margeEcran,
                  right: Espaces.margeEcran,
                  bottom: Espaces.e16,
                  child: _BandeauAnnulation(onAnnuler: notifier.annuler),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandeauAnnulation extends StatelessWidget {
  const _BandeauAnnulation({required this.onAnnuler});
  final VoidCallback onAnnuler;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.only(left: Espaces.e16, right: Espaces.e6),
        constraints: const BoxConstraints(minHeight: Tailles.zoneTactileMin),
        decoration: BoxDecoration(color: c.encre, borderRadius: BorderRadius.circular(Rayons.bouton)),
        child: Row(
          children: [
            Expanded(
              child: Text(S.reponseEnregistree, style: Textes.etiquette.copyWith(color: c.fond)),
            ),
            BoutonLien(libelle: S.annuler, onPressed: onAnnuler, couleur: c.jaune),
          ],
        ),
      ),
    );
  }
}

class _CarteRappel extends StatelessWidget {
  const _CarteRappel({required this.carte, required this.revele, this.message});
  final RevisionDue carte;
  final bool revele;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final extrait = carte.extrait;
    return Consumer(
      builder: (context, ref, _) {
        final notifier = ref.read(sessionRevisionProvider.notifier);
        return Container(
          padding: const EdgeInsets.all(Espaces.e24),
          decoration: _carte(c),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                extrait == null ? S.traduisLeMot : S.devineLeMot,
                style: Textes.etiquetteMajuscules.copyWith(color: c.violet),
              ),
              const SizedBox(height: Espaces.e12),
              if (extrait == null)
                Text(carte.terme, style: Textes.titreExtrait.copyWith(color: c.encre)) // REV-14
              else
                ExtraitSurligne.depuis(extrait, style: Textes.titreExtrait, masque: !revele),
              const SizedBox(height: Espaces.e14),
              Text(
                extrait == null
                    ? S.pasDExtrait
                    : '${extrait.horsListe ? S.extraitHorsListe : S.extraitDeTaListe}'
                          '${revele ? ' — ${extrait.titre}, ${extrait.artiste}' : ''}',
                style: Textes.legende.copyWith(color: c.texteSecondaire),
              ),
              if (revele && extrait != null) LienChanson(extrait: extrait),
              if (message != null) ...[
                const SizedBox(height: Espaces.e8),
                Text(message!, style: Textes.legende.copyWith(color: c.texteSecondaire)),
              ],
              if (!revele) ...[
                const SizedBox(height: Espaces.e20),
                BoutonPrincipal(libelle: S.reveler, onPressed: notifier.reveler, autofocus: true),
              ] else ...[
                const SizedBox(height: Espaces.e20),
                AnimatedOpacity(
                  opacity: 1,
                  duration: Durees.apparition,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Le mot révélé et sa prononciation (jamais avant la révélation).
                      Row(
                        children: [
                          Expanded(
                            child: Text(carte.terme, style: Textes.termeListe.copyWith(color: c.encre)),
                          ),
                          BoutonPrononciation(
                            mot: carte.terme,
                            service: ref.read(environnementProvider).prononciation,
                          ),
                        ],
                      ),
                      const SizedBox(height: Espaces.e8),
                      Text(S.traduction, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
                      const SizedBox(height: Espaces.e4),
                      Text(
                        carte.traductionFr ?? S.traductionIndisponible,
                        style: Textes.titreCarte.copyWith(color: c.encre),
                      ),
                      if (carte.explication != null && carte.sourceExplication == 'ia') ...[
                        const SizedBox(height: Espaces.e14),
                        BlocExplication(texte: carte.explication!),
                      ],
                      if (carte.exemples.isNotEmpty) ...[
                        const SizedBox(height: Espaces.e14),
                        BlocExemples(exemples: carte.exemples),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CarteExercice extends ConsumerWidget {
  const _CarteExercice({required this.carte, required this.controleur});
  final RevisionDue carte;
  final TextEditingController controleur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final session = ref.watch(sessionRevisionProvider);
    final notifier = ref.read(sessionRevisionProvider.notifier);
    final verdict = session.verdict;
    if (session.phase == PhaseExercice.chargement) {
      return Container(
        padding: const EdgeInsets.all(Espaces.e24),
        decoration: _carte(c),
        child: const Column(
          children: [
            Squelette(hauteur: Espaces.e16, rayon: Rayons.surlignage),
            SizedBox(height: Espaces.e12),
            Squelette(hauteur: Tailles.boutonMin, rayon: Rayons.bouton),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(Espaces.e24),
      decoration: _carte(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.traduisEnAnglais, style: Textes.etiquetteMajuscules.copyWith(color: c.violet)),
          const SizedBox(height: Espaces.e12),
          Text(session.exercice?.phraseFr ?? '', style: Textes.titreExtrait.copyWith(color: c.encre)),
          const SizedBox(height: Espaces.e16),
          if (verdict == null) ...[
            // Le mot n'est jamais montré avant le verdict : à l'utilisateur de le retrouver.
            Text(S.consigneMotCache, style: Textes.legende.copyWith(color: c.texteSecondaire)),
            const SizedBox(height: Espaces.e12),
            ChampMot(controleur: controleur, aide: S.taReponse, multiligne: true, max: 300, autofocus: true),
            const SizedBox(height: Espaces.e16),
            BoutonPrincipal(
              libelle: S.valider,
              onPressed: session.phase == PhaseExercice.evaluation
                  ? null
                  : () => notifier.evaluer(controleur.text),
            ),
            const SizedBox(height: Espaces.e10),
            // Réponse dictée : le texte reconnu remplit le champ puis est vérifié.
            if (session.phase != PhaseExercice.evaluation)
              BoutonDictee(
                controleur: controleur,
                service: ref.read(environnementProvider).dictee,
                surReponse: notifier.evaluer,
                motAttendu: carte.terme,
              ),
          ] else ...[
            BlocVerdict(verdict: verdict),
            const SizedBox(height: Espaces.e14),
            Text(S.taReponseLabel, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
            Text(controleur.text, style: Textes.corps.copyWith(color: c.encre)),
            const SizedBox(height: Espaces.e12),
            Text(S.motAEmployer, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
            Row(
              children: [
                Flexible(
                  child: Text(carte.terme, style: Textes.termeListe.copyWith(color: c.encre)),
                ),
                BoutonPrononciation(mot: carte.terme, service: ref.read(environnementProvider).prononciation),
              ],
            ),
            if (carte.traductionFr != null)
              Text(carte.traductionFr!, style: Textes.corps.copyWith(color: c.texteSecondaire)),
            if (verdict.referenceEn != null) ...[
              const SizedBox(height: Espaces.e12),
              Text(S.attendu, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
              Text(verdict.referenceEn!, style: Textes.corps.copyWith(color: c.encre)),
            ],
            const SizedBox(height: Espaces.e16),
            BoutonPrincipal(
              libelle: S.suivant,
              autofocus: true,
              onPressed: () {
                notifier.validerVerdict(controleur.text);
                controleur.clear();
              },
            ),
          ],
        ],
      ),
    );
  }
}

// --- Récapitulatif ------------------------------------------------------------------------

class _Recapitulatif extends ConsumerWidget {
  const _Recapitulatif();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final session = ref.watch(sessionRevisionProvider);
    final dues = ref.watch(revisionsDuesProvider).valueOrNull;
    final restants = dues?.totalDus ?? 0;
    final prochaine = dues?.prochaineDate;
    return _AvecEnTete(
      fond: c.turquoise,
      hauteur: Tailles.enTeteFiche,
      enTete: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(S.bienJoue, style: Textes.titreEcran.copyWith(color: c.vertTexte)),
          ),
          const SizedBox(height: Espaces.e8),
          if (prochaine != null && restants == 0)
            Text(
              S.prochaineRevisionLe(dateFiche(prochaine)),
              style: Textes.corps.copyWith(color: c.vertTexte),
            ),
        ],
      ),
      contenu: Transform.translate(
        offset: Offset(0, context.estPc ? 0 : Tailles.chevauchementRevision - Tailles.chevauchementFiche),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TuileInfo(valeur: '${session.revises}', legende: S.motsRevises, couleur: c.violet),
                ),
                const SizedBox(width: Espaces.e12),
                Expanded(
                  child: TuileInfo(valeur: '${session.reussites}', legende: S.reussites, couleur: c.rose),
                ),
              ],
            ),
            const SizedBox(height: Espaces.e20),
            if (restants > 0) ...[
              BoutonPrincipal(
                libelle: S.sessionSuivante,
                onPressed: () => ref.read(sessionRevisionProvider.notifier).continuer(dues!.items),
              ),
              const SizedBox(height: Espaces.e6),
              BoutonLien(
                libelle: S.terminer,
                onPressed: () => ref.read(sessionRevisionProvider.notifier).terminer(),
              ),
            ] else
              BoutonPrincipal(
                libelle: S.terminer,
                onPressed: () => ref.read(sessionRevisionProvider.notifier).terminer(),
              ),
          ],
        ),
      ),
    );
  }
}
