// Composants de référence (21.2, 43.5, 43.9) construits uniquement avec les jetons (DES-02).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/extrait.dart';
import '../models/revision.dart';
import '../services/extraction.dart';
import '../services/plateforme.dart';
import '../services/prononciation_service.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import 'icones.dart';

// --- Zone cliquable : survol, appui, focus clavier (43.10, DES-19, UI-05) -----------------

class Cliquable extends StatefulWidget {
  const Cliquable({
    super.key,
    required this.child,
    required this.onTap,
    this.rayon = Rayons.bouton,
    this.libelle,
    this.bouton = true,
    this.selectionne,
    this.onLongPress,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double rayon;
  final String? libelle;
  final bool bouton;
  final bool? selectionne;
  final bool autofocus;

  @override
  State<Cliquable> createState() => _CliquableState();
}

class _CliquableState extends State<Cliquable> {
  bool _survol = false;
  bool _appui = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final actif = widget.onTap != null;
    Color? voile;
    if (actif && _appui) {
      voile = c.ombre.withValues(alpha: Opacites.appui);
    } else if (actif && _survol) {
      voile = c.surface.withValues(alpha: Opacites.survol);
    }
    return Semantics(
      button: widget.bouton,
      enabled: actif,
      selected: widget.selectionne,
      label: widget.libelle,
      child: FocusableActionDetector(
        enabled: actif,
        autofocus: widget.autofocus,
        mouseCursor: actif ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        onShowHoverHighlight: (v) => setState(() => _survol = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: actif ? (_) => setState(() => _appui = true) : null,
          onTapUp: actif ? (_) => setState(() => _appui = false) : null,
          onTapCancel: actif ? () => setState(() => _appui = false) : null,
          child: Container(
            foregroundDecoration: BoxDecoration(
              color: voile,
              borderRadius: BorderRadius.circular(widget.rayon),
            ),
            decoration: _focus
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.rayon + Tailles.focusDecalage),
                    border: Border.all(color: c.violet, width: Tailles.focusAnneau),
                  )
                : null,
            padding: _focus ? EdgeInsets.zero : EdgeInsets.zero,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// --- Boutons (43.5) -----------------------------------------------------------------------

enum TypeBouton { principal, negatif, positif, confirmationSuppression }

class BoutonPrincipal extends StatelessWidget {
  const BoutonPrincipal({
    super.key,
    required this.libelle,
    required this.onPressed,
    this.type = TypeBouton.principal,
    this.style = Textes.bouton,
    this.pleineLargeur = true,
    this.autofocus = false,
  });

  final String libelle;
  final VoidCallback? onPressed;
  final TypeBouton type;
  final TextStyle style;
  final bool pleineLargeur;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final (fond, texte) = switch (type) {
      TypeBouton.principal || TypeBouton.confirmationSuppression => (c.rose, c.surAccent),
      TypeBouton.negatif => (c.jaune, c.surAccent),
      TypeBouton.positif => (c.turquoise, c.vertTexte),
    };
    final actif = onPressed != null;
    return Opacity(
      opacity: actif ? 1 : Opacites.desactive,
      child: Cliquable(
        onTap: onPressed,
        libelle: libelle,
        autofocus: autofocus,
        child: Container(
          constraints: const BoxConstraints(minHeight: Tailles.boutonMin),
          width: pleineLargeur ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Espaces.e16, vertical: Espaces.e10),
          decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(Rayons.bouton)),
          child: ExcludeSemantics(
            child: Text(
              libelle,
              textAlign: TextAlign.center,
              style: style.copyWith(color: texte),
            ),
          ),
        ),
      ),
    );
  }
}

class BoutonLien extends StatelessWidget {
  const BoutonLien({super.key, required this.libelle, required this.onPressed, this.couleur});
  final String libelle;
  final VoidCallback? onPressed;
  final Color? couleur;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? Opacites.desactive : 1,
    child: Cliquable(
      onTap: onPressed,
      libelle: libelle,
      rayon: Rayons.etiquetteIA,
      child: Container(
        constraints: const BoxConstraints(minHeight: Tailles.lienMin),
        padding: const EdgeInsets.symmetric(horizontal: Espaces.e8),
        alignment: Alignment.center,
        child: ExcludeSemantics(
          child: Text(libelle, style: Textes.lien.copyWith(color: couleur ?? context.couleurs.violetFonce)),
        ),
      ),
    ),
  );
}

/// Bouton icône carré (actions secondaires : menu, fermer, retour), zone tactile ≥ 48.
class BoutonIcone extends StatelessWidget {
  const BoutonIcone({
    super.key,
    required this.forme,
    required this.libelle,
    required this.onPressed,
    this.couleur,
  });
  final FormeIcone forme;
  final String libelle;
  final VoidCallback? onPressed;
  final Color? couleur;

  @override
  Widget build(BuildContext context) => Cliquable(
    onTap: onPressed,
    libelle: libelle,
    rayon: Rayons.etiquetteIA,
    child: SizedBox.square(
      dimension: Tailles.zoneTactileMin,
      child: Center(child: IconeTrace(forme, couleur: couleur ?? context.couleurs.encre)),
    ),
  );
}

// --- Champs -------------------------------------------------------------------------------

class ChampRecherche extends StatelessWidget {
  const ChampRecherche({
    super.key,
    required this.aide,
    required this.controleur,
    this.onChanged,
    this.avecIcone = true,
    this.focus,
    this.suffixe,
  });
  final String aide;
  final TextEditingController controleur;
  final ValueChanged<String>? onChanged;
  final bool avecIcone;
  final FocusNode? focus;

  /// Action posée à droite du champ (tri de la bibliothèque).
  final Widget? suffixe;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Container(
      height: Tailles.recherche + 2 * Tailles.bordureChamp,
      padding: const EdgeInsets.symmetric(horizontal: Espaces.e16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Rayons.bouton),
        border: Border.all(color: c.bordure, width: Tailles.bordureChamp),
      ),
      child: Row(
        children: [
          if (avecIcone) ...[
            IconeTrace(
              Icones.loupe,
              taille: Tailles.iconeRecherche,
              couleur: c.texteSecondaire,
              epaisseur: 2.2,
            ),
            const SizedBox(width: Espaces.e10),
          ],
          Expanded(
            // ACC-01 : zone sémantique de 48 dp autour de la ligne de saisie.
            child: MergeSemantics(
              child: SizedBox(
                height: Tailles.zoneTactileMin,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextField(
                    controller: controleur,
                    focusNode: focus,
                    onChanged: onChanged,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    style: Textes.corps.copyWith(color: c.encre),
                    cursorColor: c.violet,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: aide,
                      hintStyle: Textes.corps.copyWith(color: c.texteSecondaire),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controleur,
            builder: (context, valeur, _) => valeur.text.isEmpty
                ? const SizedBox.shrink()
                : BoutonIcone(
                    forme: Icones.fermer,
                    libelle: S.effacerRecherche,
                    couleur: c.texteSecondaire,
                    onPressed: () {
                      controleur.clear();
                      onChanged?.call('');
                    },
                  ),
          ),
          ?suffixe,
        ],
      ),
    );
  }
}

/// Champ du mot (43.9) : hauteur 60, compteur dès 80 caractères, erreur sous le champ.
class ChampMot extends StatefulWidget {
  const ChampMot({
    super.key,
    required this.controleur,
    required this.aide,
    this.erreur,
    this.onSubmitted,
    this.autofocus = false,
    this.multiligne = false,
    this.max = 100,
    this.focus,
    this.onChanged,
  });
  final TextEditingController controleur;
  final String aide;
  final String? erreur;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool multiligne;
  final int max;
  final FocusNode? focus;

  static const seuilCompteur = 80;

  @override
  State<ChampMot> createState() => _ChampMotState();
}

class _ChampMotState extends State<ChampMot> {
  late final FocusNode _focus = widget.focus ?? FocusNode();
  bool _actif = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _actif = _focus.hasFocus));
  }

  @override
  void dispose() {
    if (widget.focus == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final seuil = widget.multiligne ? widget.max - 20 : ChampMot.seuilCompteur;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: Tailles.champMot),
          padding: const EdgeInsets.symmetric(horizontal: Espaces.e16, vertical: Espaces.e4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Rayons.bouton),
            border: Border.all(color: _actif ? c.violet : c.bordure, width: Tailles.bordureChamp),
          ),
          child: MergeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Tailles.zoneTactileMin),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: widget.controleur,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  minLines: 1,
                  maxLines: widget.multiligne ? 4 : 1,
                  textInputAction: widget.multiligne ? TextInputAction.newline : TextInputAction.done,
                  inputFormatters: [LengthLimitingTextInputFormatter(widget.max + 20)],
                  onSubmitted: widget.onSubmitted,
                  onChanged: widget.onChanged,
                  style: Textes.saisie.copyWith(color: c.encre),
                  cursorColor: c.violet,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.aide,
                    hintStyle: Textes.saisie.copyWith(color: c.texteSecondaire),
                  ),
                ),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controleur,
          builder: (context, valeur, _) {
            final longueur = valeur.text.runes.length;
            if (longueur < seuil) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: Espaces.e6),
              child: Text(
                '$longueur / ${widget.max}',
                textAlign: TextAlign.right,
                style: Textes.legende.copyWith(color: c.texteSecondaire),
              ),
            );
          },
        ),
        if (widget.erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: Espaces.e6),
            child: Semantics(
              liveRegion: true,
              child: Text(widget.erreur!, style: Textes.etiquette.copyWith(color: c.erreurTexte)),
            ),
          ),
      ],
    );
  }
}

// --- Pastilles ----------------------------------------------------------------------------

/// Libellé, icône et couleurs d'un niveau (21.3) : jamais la couleur seule (UI-05).
(String, FormeIcone, Color, Color) styleNiveau(BuildContext context, String niveau) {
  final c = context.couleurs;
  return switch (niveau) {
    'acquis' => (S.acquis, Icones.coche, c.acquisFond, c.acquisTexte),
    'en_cours' => (S.enCours, Icones.progression, c.enCoursFond, c.enCoursTexte),
    _ => (S.nouveau, Icones.etoile, c.nouveauFond, c.nouveauTexte),
  };
}

class PastilleNiveau extends StatelessWidget {
  const PastilleNiveau(this.niveau, {super.key});
  final String niveau;

  @override
  Widget build(BuildContext context) {
    final (libelle, _, fond, texte) = styleNiveau(context, niveau);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaces.e12, vertical: Espaces.e6),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(Rayons.pastilleListe)),
      child: Text(libelle, style: Textes.pastilleNiveau.copyWith(color: texte)),
    );
  }
}

class PastilleFiltre extends StatelessWidget {
  const PastilleFiltre({
    super.key,
    required this.libelle,
    required this.fond,
    required this.actif,
    required this.onTap,
  });
  final String libelle;
  final Color fond;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Cliquable(
      onTap: onTap,
      libelle: libelle,
      selectionne: actif,
      rayon: Rayons.filtre,
      child: Container(
        constraints: const BoxConstraints(minHeight: Tailles.zoneTactileMin - 12),
        padding: const EdgeInsets.symmetric(horizontal: Espaces.e16, vertical: Espaces.e9),
        decoration: BoxDecoration(
          color: actif ? c.violet : fond,
          borderRadius: BorderRadius.circular(Rayons.filtre),
        ),
        child: ExcludeSemantics(
          child: Text(libelle, style: Textes.etiquette.copyWith(color: actif ? c.surViolet : c.surAccent)),
        ),
      ),
    );
  }
}

class PastilleSimple extends StatelessWidget {
  const PastilleSimple({
    super.key,
    required this.libelle,
    required this.fond,
    required this.texte,
    this.rayon = Rayons.pastille,
    this.padding = const EdgeInsets.symmetric(horizontal: Espaces.e14, vertical: Espaces.e6),
    this.style = Textes.etiquette,
  });
  final String libelle;
  final Color fond;
  final Color texte;
  final double rayon;
  final EdgeInsets padding;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(rayon)),
    child: Text(libelle, style: style.copyWith(color: texte)),
  );
}

class EtiquetteIA extends StatelessWidget {
  const EtiquetteIA({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaces.e10, vertical: Espaces.e3),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Rayons.etiquetteIA)),
      child: Text(S.etiquetteIA, style: Textes.etiquetteIA.copyWith(color: c.violetFonce)),
    );
  }
}

// --- Cartes -------------------------------------------------------------------------------

class CarteMot extends StatelessWidget {
  const CarteMot({
    super.key,
    required this.terme,
    required this.traduction,
    required this.niveau,
    required this.onTap,
    this.enAttente = false,
    this.onMenu,
  });
  final String terme;
  final String? traduction;
  final String niveau;
  final bool enAttente;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Cliquable(
      onTap: onTap,
      onLongPress: onMenu,
      rayon: Rayons.carteListe,
      libelle:
          '$terme, ${traduction ?? S.enAttenteEnrichissement}, '
          '${styleNiveau(context, niveau).$1}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Espaces.e18, vertical: Espaces.e14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Rayons.carteListe),
          boxShadow: Ombres.carteListe(c),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      terme,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Textes.termeListe.copyWith(color: c.encre),
                    ),
                    const SizedBox(height: Espaces.e2),
                    Row(
                      children: [
                        if (enAttente) ...[
                          Squelette(largeur: Espaces.e10, hauteur: Espaces.e10, rayon: Espaces.e6),
                          const SizedBox(width: Espaces.e6),
                        ],
                        Flexible(
                          child: Text(
                            traduction ?? S.enAttenteEnrichissement,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Textes.corpsListe.copyWith(color: c.texteSecondaire),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Espaces.e8),
              PastilleNiveau(niveau),
            ],
          ),
        ),
      ),
    );
  }
}

class CarteFiche extends StatelessWidget {
  const CarteFiche({super.key, required this.libelle, required this.child, this.pied});
  final String libelle;
  final Widget child;
  final Widget? pied;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Espaces.e20, vertical: Espaces.e18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Rayons.carte),
        boxShadow: Ombres.carteFiche(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(libelle, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
          ),
          child,
          if (pied != null) pied!,
        ],
      ),
    );
  }
}

class BlocExplication extends StatelessWidget {
  const BlocExplication({super.key, required this.texte});
  final String texte;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Espaces.e20, vertical: Espaces.e18),
      decoration: BoxDecoration(color: c.lavande, borderRadius: BorderRadius.circular(Rayons.carte)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Espaces.e8,
              runSpacing: Espaces.e6,
              children: [
                Semantics(
                  header: true,
                  child: Text(S.explication, style: Textes.libelleCarte.copyWith(color: c.violetFonce)),
                ),
                const EtiquetteIA(),
              ],
            ),
          ),
          const SizedBox(height: Espaces.e8),
          Text(texte, style: Textes.corpsExplication.copyWith(color: c.encre)),
        ],
      ),
    );
  }
}

/// Texte d'un extrait avec le mot surligné, ou masqué sur la carte de révision (43.5).
class ExtraitSurligne extends StatelessWidget {
  const ExtraitSurligne({
    super.key,
    required this.texte,
    required this.debut,
    required this.fin,
    this.style = Textes.extraitFiche,
    this.masque = false,
  });
  final String texte;
  final int debut;
  final int fin;
  final TextStyle style;
  final bool masque;

  factory ExtraitSurligne.depuis(Extrait e, {TextStyle style = Textes.extraitFiche, bool masque = false}) =>
      ExtraitSurligne(
        texte: e.texte,
        debut: e.surbrillanceDebut,
        fin: e.surbrillanceFin,
        style: style,
        masque: masque,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final base = style.copyWith(color: c.encre);
    final bornes = bornesSurbrillance(texte, debut, fin);
    if (bornes == null) return Text(texte, style: base);
    final (d, f) = bornes;
    final mot = texte.substring(d, f);
    final marque = masque
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: Espaces.e10),
            decoration: BoxDecoration(color: c.lavande, borderRadius: BorderRadius.circular(Rayons.masque)),
            child: Text('_' * (fin - debut), style: base.copyWith(color: c.violet, height: 1.0)),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: Espaces.e6),
            decoration: BoxDecoration(color: c.jaune, borderRadius: BorderRadius.circular(Rayons.surlignage)),
            child: Text(mot, style: base.copyWith(color: c.surAccent, height: 1.0)),
          );
    return Semantics(
      label: masque ? texte.replaceRange(d, f, '…') : texte,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(text: texte.substring(0, d)),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: marque,
              ),
              TextSpan(text: texte.substring(f)),
            ],
          ),
        ),
      ),
    );
  }
}

class TuileInfo extends StatelessWidget {
  const TuileInfo({super.key, required this.valeur, required this.legende, required this.couleur});
  final String valeur;
  final String legende;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Container(
      padding: const EdgeInsets.all(Espaces.e14),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Rayons.carteListe)),
      child: Semantics(
        label: '$legende : $valeur',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Text(
                valeur,
                textAlign: TextAlign.center,
                style: Textes.valeur.copyWith(color: couleur),
              ),
              Text(
                legende,
                textAlign: TextAlign.center,
                style: Textes.legendeTuile.copyWith(color: c.texteSecondaire),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Artistes -----------------------------------------------------------------------------

class ArtisteAvatar extends StatelessWidget {
  const ArtisteAvatar({
    super.key,
    required this.nom,
    required this.initiales,
    required this.indexCouleur,
    required this.selectionne,
    required this.onTap,
    this.imageUrl,
    this.diametre = Tailles.avatar,
    this.avecNom = true,
  });
  final String nom;
  final String initiales;
  final int indexCouleur;
  final bool selectionne;
  final VoidCallback? onTap;
  final String? imageUrl;
  final double diametre;
  final bool avecNom;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final couleurs = c.avatars;
    final fond = couleurs[indexCouleur % couleurs.length];
    final echelle = diametre / Tailles.avatar;
    Widget disque = Container(
      width: diametre,
      height: diametre,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fond,
        shape: BoxShape.circle,
        boxShadow: selectionne
            ? [
                BoxShadow(color: c.rose, spreadRadius: Tailles.anneau * 2),
                BoxShadow(color: c.fond, spreadRadius: Tailles.anneau),
              ]
            : null,
      ),
      child: Text(
        initiales,
        style: Textes.initiales.copyWith(
          color: c.texteSurAvatar(fond),
          fontSize: Textes.initiales.fontSize! * echelle,
        ),
      ),
    );
    if (imageUrl != null) {
      disque = Stack(
        alignment: Alignment.center,
        children: [
          disque,
          ClipOval(
            child: Image.network(
              imageUrl!,
              width: diametre,
              height: diametre,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              frameBuilder: (_, enfant, image, _) => image == null ? const SizedBox.shrink() : enfant,
            ),
          ),
        ],
      );
    }
    if (selectionne) {
      disque = Stack(
        clipBehavior: Clip.none,
        children: [
          disque,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: Tailles.coche * echelle,
              height: Tailles.coche * echelle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.rose,
                shape: BoxShape.circle,
                border: Border.all(color: c.fond, width: Tailles.cocheBordure),
              ),
              child: IconeTrace(
                Icones.coche,
                taille: Tailles.cocheIcone * echelle,
                couleur: c.surAccent,
                epaisseur: 3.2,
              ),
            ),
          ),
        ],
      );
    }
    return Cliquable(
      onTap: onTap,
      libelle: nom,
      selectionne: selectionne,
      rayon: diametre / 2,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            disque,
            if (avecNom) ...[
              const SizedBox(height: Espaces.e10),
              Text(
                nom,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Textes.etiquette.copyWith(color: c.encre),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Structure ----------------------------------------------------------------------------

class PanneauBas extends StatelessWidget {
  const PanneauBas({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Container(
      constraints: const BoxConstraints(minHeight: Tailles.panneauBas),
      padding: EdgeInsets.fromLTRB(
        Espaces.e20,
        Espaces.e18,
        Espaces.e20,
        Espaces.e12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rayons.carteLarge)),
        boxShadow: Ombres.panneauBas(c),
      ),
      child: child,
    );
  }
}

/// En-tête coloré : pleine largeur avec angles bas arrondis, carte arrondie sur PC (43.10).
class EnTeteColore extends StatelessWidget {
  const EnTeteColore({
    super.key,
    required this.fond,
    required this.hauteur,
    required this.child,
    this.actions,
  });
  final Color fond;
  final double hauteur;
  final Widget child;

  /// Boutons d'action posés en haut à droite, sans décaler le contenu du design.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final pc = context.estPc;
    final haut = pc ? Espaces.e32 : margeHauteEcran(context);
    final enTete = _bloc(context, pc, haut);
    if (actions == null) return enTete;
    return Stack(
      children: [
        enTete,
        Positioned(
          top: pc ? Espaces.e4 : MediaQuery.paddingOf(context).top + Espaces.e4,
          right: Espaces.e8,
          child: actions!,
        ),
      ],
    );
  }

  Widget _bloc(BuildContext context, bool pc, double haut) {
    return Container(
      constraints: BoxConstraints(minHeight: pc ? 0 : hauteur),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(Espaces.margeEnTete, haut, Espaces.margeEnTete, pc ? Espaces.e24 : 0),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: pc
            ? BorderRadius.circular(Rayons.carteLarge)
            : const BorderRadius.vertical(bottom: Radius.circular(Rayons.enTete)),
      ),
      child: child,
    );
  }
}

/// Marge haute réelle : max(56, inset de la barre d'état + 16) (43.15).
double margeHauteEcran(BuildContext context) {
  final inset = MediaQuery.paddingOf(context).top + Espaces.sousBarreEtat;
  return inset > Espaces.margeHaute ? inset : Espaces.margeHaute;
}

/// Contenu centré : 640 max en dessous de 900 px, 960 max au-delà (27.1, 43.10).
class ContenuCentre extends StatelessWidget {
  const ContenuCentre({super.key, required this.child, this.largeurMax});
  final Widget child;
  final double? largeurMax;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: largeurMax ?? (context.estPc ? Tailles.contenuPcMax : Tailles.colonneMobileMax),
      ),
      child: child,
    ),
  );
}

class BarreProgression extends StatelessWidget {
  const BarreProgression({super.key, required this.valeur});
  final double valeur;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Semantics(
      value: '${(valeur * 100).round()} %',
      child: Container(
        height: Tailles.barreProgression,
        decoration: BoxDecoration(
          color: c.surViolet.withValues(alpha: Opacites.pisteProgression),
          borderRadius: BorderRadius.circular(Rayons.barreProgression),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: valeur.clamp(0, 1),
          child: Container(
            decoration: BoxDecoration(
              color: c.jaune,
              borderRadius: BorderRadius.circular(Rayons.barreProgression),
            ),
          ),
        ),
      ),
    );
  }
}

// --- États (COMPO-03, COMPO-04, COMPO-06, 43.9) -------------------------------------------

enum TypeBandeau { horsLigne, pcInjoignable, syncTerminee, erreurSync }

class BandeauEtat extends StatelessWidget {
  const BandeauEtat({super.key, required this.type, required this.texte});
  final TypeBandeau type;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final (fond, couleur) = switch (type) {
      TypeBandeau.horsLigne => (c.encre, c.fond),
      TypeBandeau.pcInjoignable => (c.nouveauFond, c.surAccent),
      TypeBandeau.syncTerminee => (c.acquisFond, c.vertTexte),
      TypeBandeau.erreurSync => (c.enCoursFond, c.erreurTexte),
    };
    return Semantics(
      liveRegion: true, // annonce vocale polie
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: Tailles.bandeau),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Espaces.e16, vertical: Espaces.e6),
        color: fond,
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: Textes.etiquette.copyWith(color: couleur),
        ),
      ),
    );
  }
}

class BadgeAttente extends StatelessWidget {
  const BadgeAttente({super.key, required this.nombre});
  final int nombre;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return PastilleSimple(libelle: S.actionsEnAttente(nombre), fond: c.lavande, texte: c.violetFonce);
  }
}

/// Squelette gris avec pulsation douce de 1,2 s, immobile si les animations sont réduites.
class Squelette extends StatefulWidget {
  const Squelette({super.key, this.largeur, required this.hauteur, this.rayon = Rayons.carte});
  final double? largeur;
  final double hauteur;
  final double rayon;

  @override
  State<Squelette> createState() => _SqueletteState();
}

class _SqueletteState extends State<Squelette> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: Durees.pulsation);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.animationsReduites) {
      _anim.stop();
    } else if (!_anim.isAnimating) {
      _anim.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 1, end: 0.55).animate(_anim),
    child: Container(
      width: widget.largeur ?? double.infinity,
      height: widget.hauteur,
      decoration: BoxDecoration(
        color: context.couleurs.bordure,
        borderRadius: BorderRadius.circular(widget.rayon),
      ),
    ),
  );
}

class EtatVide extends StatelessWidget {
  const EtatVide({
    super.key,
    required this.icone,
    required this.titre,
    required this.texte,
    this.action,
    this.onAction,
    this.erreur = false,
  });
  final FormeIcone icone;
  final String titre;
  final String texte;
  final String? action;
  final VoidCallback? onAction;
  final bool erreur;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final fond = erreur ? c.enCoursFond : c.lavande;
    final couleur = erreur ? c.erreurTexte : c.violet;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaces.e32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: Tailles.illustrationVide,
            height: Tailles.illustrationVide,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(Rayons.carte)),
            child: IconeTrace(icone, taille: Tailles.illustrationVide / 2, couleur: couleur),
          ),
          const SizedBox(height: Espaces.e16),
          Text(
            titre,
            textAlign: TextAlign.center,
            style: Textes.titreCarte.copyWith(color: erreur ? c.erreurTexte : c.encre),
          ),
          const SizedBox(height: Espaces.e8),
          Text(
            texte,
            textAlign: TextAlign.center,
            style: Textes.corps.copyWith(color: erreur ? c.erreurTexte : c.texteSecondaire),
          ),
          if (action != null) ...[
            const SizedBox(height: Espaces.e16),
            BoutonPrincipal(libelle: action!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

class EtatErreur extends StatelessWidget {
  const EtatErreur({super.key, required this.message, required this.onReessayer});
  final String message;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) => EtatVide(
    icone: Icones.actualiser,
    titre: S.erreurGenerique,
    texte: message,
    action: S.reessayer,
    onAction: onReessayer,
    erreur: true,
  );
}

/// Feuille de confirmation (43.9) : retourne vrai si l'action est confirmée.
Future<bool> confirmer(
  BuildContext context, {
  required String titre,
  required String action,
  String? texte,
}) async {
  final c = context.couleurs;
  final resultat = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => PanneauBas(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titre, style: Textes.titreCarte.copyWith(color: c.encre)),
          if (texte != null) ...[
            const SizedBox(height: Espaces.e8),
            Text(texte, style: Textes.corps.copyWith(color: c.texteSecondaire)),
          ],
          const SizedBox(height: Espaces.e18),
          BoutonPrincipal(libelle: action, onPressed: () => Navigator.of(context).pop(true), autofocus: true),
          const SizedBox(height: Espaces.e6),
          BoutonLien(libelle: S.annuler, onPressed: () => Navigator.of(context).pop(false)),
        ],
      ),
    ),
  );
  return resultat ?? false;
}

/// Message court en bas de l'écran.
void afficherMessage(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
  Duration duree = const Duration(seconds: 4),
}) {
  final messager = ScaffoldMessenger.of(context);
  messager.hideCurrentSnackBar();
  messager.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duree,
      action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
    ),
  );
}

/// Verdict d'un exercice (43.9) : couleur, libellé, explication et étiquette IA.
class BlocVerdict extends StatelessWidget {
  const BlocVerdict({super.key, required this.verdict});
  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final (fond, texte, libelle) = switch (verdict.verdict) {
      'correct' => (c.acquisFond, c.vertTexte, S.correct),
      'proche' => (c.nouveauFond, c.surAccent, S.presque),
      _ => (c.enCoursFond, c.erreurTexte, S.incorrect),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Espaces.e20, vertical: Espaces.e18),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(Rayons.carte)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Espaces.e8,
              runSpacing: Espaces.e6,
              children: [
                Text(libelle, style: Textes.titreCarte.copyWith(color: texte)),
                const EtiquetteIA(),
              ],
            ),
            const SizedBox(height: Espaces.e8),
            Text(verdict.explication, style: Textes.corps.copyWith(color: texte)),
            if (verdict.verdictRepli) ...[
              const SizedBox(height: Espaces.e6),
              Text(S.evaluationSimplifiee, style: Textes.legende.copyWith(color: texte)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lien « Écouter la chanson » d'un extrait (Deezer, Genius, sinon recherche YouTube).
class LienChanson extends StatelessWidget {
  const LienChanson({super.key, required this.extrait});
  final Extrait extrait;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Semantics(
      link: true,
      child: BoutonLien(
        libelle: S.ecouterChanson,
        // Ouverture synchrone dans le geste : nouvel onglet sur le web, application sur Android.
        onPressed: () => ouvrirLien(extrait.lienEcoute).then((ok) {
          if (!ok && context.mounted) afficherMessage(context, S.lienImpossible);
        }),
      ),
    ),
  );
}

/// Bouton haut-parleur : prononce le mot en anglais ; appui long pour une diction lente.
class BoutonPrononciation extends StatelessWidget {
  const BoutonPrononciation({super.key, required this.mot, required this.service, this.couleur});
  final String mot;
  final ServicePrononciation service;
  final Color? couleur;

  Future<void> _dire(BuildContext context, {required bool lent}) async {
    final ok = await service.prononcer(mot, lent: lent);
    if (!ok && context.mounted) afficherMessage(context, S.prononciationImpossible);
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: S.prononciationLente,
    child: Cliquable(
      onTap: () => _dire(context, lent: false),
      onLongPress: () => _dire(context, lent: true),
      libelle: S.prononcer(mot),
      rayon: Rayons.etiquetteIA,
      child: SizedBox.square(
        dimension: Tailles.zoneTactileMin,
        child: Center(child: IconeTrace(Icones.hautParleur, couleur: couleur ?? context.couleurs.violet)),
      ),
    ),
  );
}
