// Écran « Bibliothèque » (US-04, 27.5, 43.6, 4-bibliotheque.html).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mot.dart';
import '../providers/providers.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';
import '../widgets/icones.dart';
import 'shell.dart';
import 'word_detail_screen.dart';

const _tris = {
  'created_desc': S.triAjoutRecent,
  'created_asc': S.triAjoutAncien,
  'prochaine_revision': S.triProchaineRevision,
  'alpha': S.triAlpha,
};

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late final TextEditingController _recherche = TextEditingController(text: ref.read(filtresMotsProvider).q);
  final _defilement = ScrollController();
  Timer? _antiRebond;
  static const _seuilChargement = 400.0;

  @override
  void initState() {
    super.initState();
    _defilement.addListener(() {
      if (_defilement.position.extentAfter < _seuilChargement) {
        ref.read(motsProvider.notifier).chargerSuite();
      }
    });
  }

  @override
  void dispose() {
    _antiRebond?.cancel();
    _recherche.dispose();
    _defilement.dispose();
    super.dispose();
  }

  void _chercher(String q) {
    _antiRebond?.cancel();
    _antiRebond = Timer(Durees.antiRebond, () {
      ref.read(filtresMotsProvider.notifier).update((f) => f.copyWith(q: q));
    });
  }

  void _ouvrir(Mot mot) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WordDetailScreen(motId: mot.id)));

  Future<void> _supprimer(Mot mot) async {
    if (!await confirmer(context, titre: S.suppressionQuestion, action: S.supprimer)) return;
    await ref.read(motsProvider.notifier).supprimer(mot.id);
    if (mounted) afficherMessage(context, S.motSupprime);
  }

  Future<void> _menu(Mot mot) async {
    final c = context.couleurs;
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => PanneauBas(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(mot.terme, style: Textes.titreCarte.copyWith(color: c.encre)),
            const SizedBox(height: Espaces.e14),
            BoutonPrincipal(libelle: S.voir, onPressed: () => Navigator.of(context).pop('voir')),
            const SizedBox(height: Espaces.e6),
            BoutonLien(libelle: S.supprimer, onPressed: () => Navigator.of(context).pop('supprimer')),
          ],
        ),
      ),
    );
    if (choix == 'voir') _ouvrir(mot);
    if (choix == 'supprimer') await _supprimer(mot);
  }

  Future<void> _choisirTri() async {
    final c = context.couleurs;
    final actuel = ref.read(filtresMotsProvider).tri;
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => PanneauBas(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.trier, style: Textes.titreCarte.copyWith(color: c.encre)),
            const SizedBox(height: Espaces.e10),
            Wrap(
              spacing: Espaces.e8,
              runSpacing: Espaces.e8,
              children: [
                for (final entree in _tris.entries)
                  PastilleFiltre(
                    libelle: entree.value,
                    fond: c.lavande,
                    actif: entree.key == actuel,
                    onTap: () => Navigator.of(context).pop(entree.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (choix != null) ref.read(filtresMotsProvider.notifier).update((f) => f.copyWith(tri: choix));
  }

  Future<void> _actualiser() => ref.read(connexionProvider.notifier).synchroniser(manuel: true);

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final etat = ref.watch(motsProvider);
    final filtres = ref.watch(filtresMotsProvider);
    final env = ref.watch(environnementProvider);
    final filtresDisponibles = [
      (null, S.tous, c.violet),
      ('nouveau', S.nouveau, c.nouveauFond),
      ('en_cours', S.enCours, c.enCoursFond),
      ('acquis', S.acquis, c.acquisFond),
    ];

    final entete = Padding(
      padding: EdgeInsets.fromLTRB(
        Espaces.margeEcran,
        context.estPc ? Espaces.e32 : margeHauteEcran(context),
        Espaces.margeEcran,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(S.mesMots, style: Textes.titreEcran.copyWith(color: c.encre)),
                ),
              ),
              Text(S.nbMots(etat.total), style: Textes.date.copyWith(color: c.violet)),
              if (context.estPc) ...[
                const SizedBox(width: Espaces.e8),
                BoutonIcone(
                  forme: Icones.actualiser,
                  libelle: S.actualiser,
                  onPressed: _actualiser,
                  couleur: c.violet,
                ),
              ],
            ],
          ),
          const SizedBox(height: Espaces.e16),
          ChampRecherche(
            aide: S.rechercherMot,
            controleur: _recherche,
            onChanged: _chercher,
            avecIcone: false,
            suffixe: BoutonIcone(
              forme: Icones.tri,
              libelle: '${S.trier} : ${_tris[filtres.tri]}',
              onPressed: _choisirTri,
              couleur: c.texteSecondaire,
            ),
          ),
          const SizedBox(height: Espaces.e14),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (niveau, libelle, fond) in filtresDisponibles) ...[
                        PastilleFiltre(
                          libelle: libelle,
                          fond: niveau == null ? c.lavande : fond,
                          actif: filtres.niveau == niveau,
                          onTap: () => ref
                              .read(filtresMotsProvider.notifier)
                              .update((f) => f.copyWith(niveau: niveau)),
                        ),
                        const SizedBox(width: Espaces.e8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaces.e18),
        ],
      ),
    );

    Widget liste;
    if (etat.erreur != null && etat.items.isEmpty) {
      liste = SliverToBoxAdapter(
        child: EtatErreur(
          message: S.serveurMuet,
          onReessayer: () => ref.read(motsProvider.notifier).charger(),
        ),
      );
    } else if (etat.chargement && etat.items.isEmpty) {
      liste = SliverList.separated(
        itemCount: 5,
        separatorBuilder: (_, _) => const SizedBox(height: Espaces.e12),
        itemBuilder: (_, _) => const Squelette(hauteur: 72, rayon: Rayons.carteListe),
      );
    } else if (etat.items.isEmpty) {
      final rien = filtres.q.isEmpty && filtres.niveau == null;
      liste = SliverToBoxAdapter(
        child: EtatVide(
          icone: Icones.mots,
          titre: rien ? S.ajouteTonPremierMot : S.aucunResultat,
          texte: rien ? S.bibliothequeVideTexte : '',
          action: rien ? S.ajouterUnMot : null,
          onAction: () => ref.read(ongletProvider.notifier).state = Onglets.ajouter,
        ),
      );
    } else {
      liste = SliverList.separated(
        itemCount: etat.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: Espaces.e12),
        itemBuilder: (context, i) {
          final mot = etat.items[i];
          return Dismissible(
            key: ValueKey(mot.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              await _supprimer(mot);
              return false;
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: Espaces.e20),
              decoration: BoxDecoration(
                color: c.enCoursFond,
                borderRadius: BorderRadius.circular(Rayons.carteListe),
              ),
              child: Text(S.supprimer, style: Textes.etiquette.copyWith(color: c.erreurTexte)),
            ),
            child: CarteMot(
              terme: mot.terme,
              traduction: mot.traductionFr,
              niveau: mot.niveau,
              enAttente: !mot.enrichissementTermine,
              onTap: () => _ouvrir(mot),
              onMenu: () => _menu(mot),
            ),
          );
        },
      );
    }

    final contenu = ContenuCentre(
      child: CustomScrollView(
        key: const PageStorageKey('bibliotheque'), // MAQ-14 : position conservée
        controller: _defilement,
        slivers: [
          SliverToBoxAdapter(child: entete),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Espaces.margeEcran,
              0,
              Espaces.margeEcran,
              Tailles.boutonFlottantBas + Tailles.boutonFlottant,
            ),
            sliver: liste,
          ),
        ],
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: env.mobile ? RefreshIndicator(onRefresh: _actualiser, child: contenu) : contenu,
          ),
          if (!context.estPc)
            Positioned(
              right: Espaces.margeEcran,
              bottom: Espaces.margeEcran,
              child: _BoutonFlottant(onTap: () => ref.read(ongletProvider.notifier).state = Onglets.ajouter),
            ),
        ],
      ),
    );
  }
}

class _BoutonFlottant extends StatelessWidget {
  const _BoutonFlottant({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Cliquable(
      onTap: onTap,
      libelle: S.ajouterUnMot,
      rayon: Rayons.boutonFlottant,
      child: Container(
        width: Tailles.boutonFlottant,
        height: Tailles.boutonFlottant,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.rose,
          borderRadius: BorderRadius.circular(Rayons.boutonFlottant),
          boxShadow: Ombres.boutonFlottant(c),
        ),
        child: IconeTrace(
          Icones.plus,
          taille: Tailles.boutonFlottantIcone,
          couleur: c.surAccent,
          epaisseur: 2.6,
        ),
      ),
    );
  }
}
