// Écran « Choix des artistes » (US-01, H.3 écran 1, 43.6, 1-choix-des-artistes.html).
// Utilisé au premier lancement et depuis les Réglages (même interface).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/divers.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';

const maxArtistes = 30;
const longueurMinRecherche = 2;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onTermine, this.depuisReglages = false});

  /// Appelé après « Continuer » ou « Passer ».
  final VoidCallback onTermine;
  final bool depuisReglages;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _recherche = TextEditingController();
  final List<Artiste> _choisis = [];
  final Map<String, int> _couleurs = {};
  List<Artiste>? _resultats;
  bool _chargementRecherche = false;
  Object? _erreurRecherche;
  Timer? _antiRebond;
  bool _envoi = false;
  int _requete = 0;

  @override
  void initState() {
    super.initState();
    if (widget.depuisReglages) {
      ref.read(depotProvider).artistesPreferes().then((liste) {
        if (mounted) setState(() => _choisis.addAll(liste));
      });
    }
  }

  @override
  void dispose() {
    _antiRebond?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  int _couleur(Artiste a) => _couleurs.putIfAbsent(a.cle, () => _couleurs.length);

  bool _estChoisi(Artiste a) => _choisis.any((x) => x.cle == a.cle);

  void _basculer(Artiste a) {
    setState(() {
      if (_estChoisi(a)) {
        _choisis.removeWhere((x) => x.cle == a.cle);
      } else if (_choisis.length >= maxArtistes) {
        afficherMessage(context, S.maxArtistes);
      } else {
        _choisis.add(a);
      }
    });
  }

  /// Anti-rebond de 300 ms après la dernière frappe (API-32).
  void _chercher(String q) {
    _antiRebond?.cancel();
    if (q.trim().length < longueurMinRecherche) {
      setState(() {
        _resultats = null;
        _erreurRecherche = null;
      });
      return;
    }
    _antiRebond = Timer(Durees.antiRebond, () => _lancerRecherche(q.trim()));
  }

  Future<void> _lancerRecherche(String q) async {
    final numero = ++_requete;
    setState(() {
      _chargementRecherche = true;
      _erreurRecherche = null;
    });
    try {
      final resultats = await ref.read(depotProvider).rechercherArtistes(q);
      if (!mounted || numero != _requete) return;
      setState(() {
        _resultats = resultats;
        _chargementRecherche = false;
      });
    } catch (e) {
      if (!mounted || numero != _requete) return;
      setState(() {
        _erreurRecherche = e;
        _chargementRecherche = false;
      });
    }
  }

  Future<void> _continuer() async {
    setState(() => _envoi = true);
    try {
      await enregistrerArtistes(ref, List.of(_choisis));
      widget.onTermine();
    } catch (_) {
      if (mounted) afficherMessage(context, S.serveurMuet);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final suggestions = ref.watch(suggestionsProvider);
    final n = _choisis.length;
    final largeur = MediaQuery.sizeOf(context).width;
    final colonnes = largeur >= Ruptures.ficheDeuxColonnes ? 6 : (largeur >= Ruptures.pc ? 5 : 3);

    List<Artiste> grille;
    Widget? etat;
    if (_resultats != null || _chargementRecherche || _erreurRecherche != null) {
      grille = _resultats ?? const [];
      if (_chargementRecherche) {
        etat = const Padding(
          padding: EdgeInsets.all(Espaces.e20),
          child: Squelette(hauteur: Tailles.avatar, rayon: Rayons.carte),
        );
      } else if (_erreurRecherche != null) {
        etat = EtatErreur(
          message: _erreurRecherche is HorsLigneException ? S.horsLigneFonction : S.serveurMuet,
          onReessayer: () => _lancerRecherche(_recherche.text.trim()),
        );
      } else if (grille.isEmpty) {
        etat = Padding(
          padding: const EdgeInsets.all(Espaces.e20),
          child: Text(
            S.aucunArtiste,
            textAlign: TextAlign.center,
            style: Textes.corps.copyWith(color: c.texteSecondaire),
          ),
        );
      }
    } else {
      grille = [
        ..._choisis.where((a) => !(suggestions.valueOrNull ?? const []).any((s) => s.cle == a.cle)),
        ...(suggestions.valueOrNull ?? const []),
      ];
      if (suggestions.isLoading) {
        etat = const Padding(
          padding: EdgeInsets.all(Espaces.e20),
          child: Squelette(hauteur: Tailles.avatar, rayon: Rayons.carte),
        );
      }
    }

    final entete = Padding(
      padding: EdgeInsets.fromLTRB(Espaces.margeEnTete, margeHauteEcran(context), Espaces.margeEnTete, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PastilleSimple(libelle: S.bienvenue, fond: c.violet, texte: c.surViolet),
              const Spacer(),
              Semantics(
                liveRegion: true,
                child: Text(S.choisis(n), style: Textes.date.copyWith(color: c.violetFonce)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: Espaces.e16, bottom: Espaces.e8),
            child: Semantics(
              header: true,
              child: Text(S.choisisArtistes, style: Textes.titreEcranSerre.copyWith(color: c.encre)),
            ),
          ),
          Text(S.sousTitreArtistes, style: Textes.corps.copyWith(color: c.texteSecondaire)),
          const SizedBox(height: Espaces.e16),
          ChampRecherche(aide: S.rechercherArtiste, controleur: _recherche, onChanged: _chercher),
        ],
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: ContenuCentre(child: entete)),
                if (etat != null) SliverToBoxAdapter(child: ContenuCentre(child: etat)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Espaces.margeEcran,
                    Espaces.e22,
                    Espaces.margeEcran,
                    Espaces.paddingBasGrille,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: ContenuCentre(
                      child: LayoutBuilder(
                        builder: (context, contraintes) {
                          const ecart = Espaces.e8;
                          final largeurCellule = (contraintes.maxWidth - ecart * (colonnes - 1)) / colonnes;
                          return Wrap(
                            spacing: ecart,
                            runSpacing: Espaces.e22,
                            children: [
                              for (final a in grille)
                                SizedBox(
                                  width: largeurCellule,
                                  child: ArtisteAvatar(
                                    nom: a.nom,
                                    initiales: a.initiales,
                                    indexCouleur: _couleur(a),
                                    imageUrl: a.imageUrl,
                                    selectionne: _estChoisi(a),
                                    onTap: () => _basculer(a),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PanneauBas(
              child: ContenuCentre(
                largeurMax: Tailles.carteRevisionPcMax,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BoutonPrincipal(
                      libelle: n == 0 ? S.choisisAuMoinsUn : S.continuerAvec(n),
                      style: Textes.boutonContinuer,
                      onPressed: n == 0 || _envoi ? null : _continuer,
                    ),
                    const SizedBox(height: Espaces.e6),
                    BoutonLien(
                      libelle: widget.depuisReglages ? S.annuler : S.passer,
                      onPressed: widget.onTermine,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
