// Barre de navigation du bas (43.5, 43.7) et barre latérale PC (43.10).
import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme/jetons.dart';
import 'composants.dart';
import 'icones.dart';

class EntreeNavigation {
  const EntreeNavigation(this.libelle, this.icone);
  final String libelle;
  final FormeIcone icone;
}

const entreesNavigation = [
  EntreeNavigation(S.navRevisions, Icones.revisions),
  EntreeNavigation(S.navMots, Icones.mots),
  EntreeNavigation(S.navAjouter, Icones.ajouter),
  EntreeNavigation(S.navReglages, Icones.reglages),
];

class BarreNavigation extends StatelessWidget {
  const BarreNavigation({super.key, required this.actif, required this.onChoix});
  final int actif;
  final ValueChanged<int> onChoix;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Semantics(
      container: true,
      label: S.navigationPrincipale,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.bordure)),
        ),
        padding: EdgeInsets.only(
          left: Espaces.e8,
          right: Espaces.e8,
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
        child: SizedBox(
          height: Tailles.navHauteur,
          child: Row(
            children: [
              for (var i = 0; i < entreesNavigation.length; i++)
                Expanded(
                  child: Cliquable(
                    onTap: () => onChoix(i),
                    libelle: entreesNavigation[i].libelle,
                    selectionne: i == actif,
                    rayon: Rayons.pastille,
                    child: ExcludeSemantics(child: _Entree(entreesNavigation[i], i == actif)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entree extends StatelessWidget {
  const _Entree(this.entree, this.actif);
  final EntreeNavigation entree;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final couleur = actif ? c.violet : c.navInactif;
    return SizedBox(
      height: Tailles.navHauteur,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: Tailles.navPastilleLargeur,
            height: Tailles.navPastilleHauteur,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: actif ? c.lavande : Colors.transparent,
              borderRadius: BorderRadius.circular(Rayons.navPastille),
            ),
            child: IconeTrace(entree.icone, taille: Tailles.navIcone, couleur: couleur),
          ),
          const SizedBox(height: Espaces.e4),
          Text(entree.libelle, style: Textes.navigation.copyWith(color: couleur)),
        ],
      ),
    );
  }
}

/// Logo horizontal (43.8) : symbole, « Lyrics & Vocab » avec le « & » en rose.
class LogoHorizontal extends StatelessWidget {
  const LogoHorizontal({super.key, this.taille = Tailles.logoBarreLaterale});
  final double taille;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SymboleLogo(taille: taille),
        const SizedBox(width: Espaces.e10),
        Flexible(
          child: Text.rich(
            TextSpan(
              style: Textes.logo.copyWith(color: c.encre),
              children: [
                const TextSpan(text: 'Lyrics '),
                TextSpan(
                  text: '&',
                  style: TextStyle(color: c.rose),
                ),
                const TextSpan(text: ' Vocab'),
              ],
            ),
            semanticsLabel: S.nomApplication,
          ),
        ),
      ],
    );
  }
}

class BarreLaterale extends StatelessWidget {
  const BarreLaterale({super.key, required this.actif, required this.onChoix});
  final int actif;
  final ValueChanged<int> onChoix;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Container(
      width: Tailles.barreLaterale,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.bordure)),
      ),
      padding: const EdgeInsets.fromLTRB(Espaces.e16, Espaces.e32, Espaces.e16, Espaces.e16),
      child: Semantics(
        container: true,
        label: S.navigationPrincipale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: Espaces.e4, bottom: Espaces.e24),
              child: LogoHorizontal(),
            ),
            for (var i = 0; i < entreesNavigation.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Espaces.e4),
                child: Cliquable(
                  onTap: () => onChoix(i),
                  libelle: entreesNavigation[i].libelle,
                  selectionne: i == actif,
                  rayon: Rayons.focus,
                  child: ExcludeSemantics(
                    child: Container(
                      height: Tailles.entreeLaterale,
                      padding: const EdgeInsets.symmetric(horizontal: Espaces.e12),
                      decoration: BoxDecoration(
                        color: i == actif ? c.lavande : Colors.transparent,
                        borderRadius: BorderRadius.circular(Rayons.focus),
                      ),
                      child: Row(
                        children: [
                          IconeTrace(
                            entreesNavigation[i].icone,
                            taille: Tailles.navIcone,
                            couleur: i == actif ? c.violet : c.navInactif,
                          ),
                          const SizedBox(width: Espaces.e12),
                          Text(
                            entreesNavigation[i].libelle,
                            style: Textes.reglage.copyWith(color: i == actif ? c.violet : c.navInactif),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
