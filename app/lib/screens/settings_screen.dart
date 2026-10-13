// Écran « Réglages » (US-07, H.3 écran 6, 27.6, 43.9).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../models/divers.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/local_cache.dart';
import '../services/sync_service.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';
import 'onboarding_screen.dart';

/// Informations du serveur (version, Ollama, quotas, erreurs), lues seulement si joignable.
final infosServeurProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(environnementProvider).api;
  final sante = await api.sante();
  if (sante == null) return {};
  final infos = <String, dynamic>{'sante': sante};
  try {
    infos['quotas'] = await api.quotas();
    infos['erreurs'] = await api.erreursRecentes();
  } on Exception {
    // informations facultatives
  }
  return infos;
});

final permissionNotificationsProvider = FutureProvider.autoDispose<bool>((ref) async {
  return ref.watch(environnementProvider).notifications.permissionAccordee();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final reglages = ref.watch(reglagesProvider);
    final env = ref.watch(environnementProvider);
    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Espaces.margeEcran,
          context.estPc ? Espaces.e32 : margeHauteEcran(context),
          Espaces.margeEcran,
          Espaces.e32,
        ),
        child: ContenuCentre(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(S.reglages, style: Textes.titreEcran.copyWith(color: c.encre)),
              ),
              const SizedBox(height: Espaces.e16),
              ...reglages.when(
                loading: () => [const Squelette(hauteur: 200)],
                error: (_, _) => [
                  EtatErreur(
                    message: S.serveurMuet,
                    onReessayer: () => ref.read(reglagesProvider.notifier).charger(),
                  ),
                ],
                data: (r) => _sections(context, ref, r, env),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, WidgetRef ref, Reglages r, Environnement env) {
    Future<void> modifier(Reglages nouveaux) async {
      try {
        await ref.read(reglagesProvider.notifier).modifier(nouveaux);
      } on Exception {
        if (context.mounted) afficherMessage(context, S.serveurMuet);
      }
    }

    final sections = <Widget>[
      const _SectionArtistes(),
      _SectionRevisions(reglages: r, modifier: modifier),
      _SectionRappels(reglages: r, modifier: modifier),
      if (env.mobile) _SectionSync(reglages: r, modifier: modifier),
      if (env.adresseModifiable) const _SectionServeur(),
      const _SectionInformations(),
      const _SectionApparence(),
      const _SectionDonnees(),
    ];
    return [
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: Espaces.e14),
        sections[i],
      ],
    ];
  }
}

/// Ligne de réglage : au moins 56 de haut, libellé à gauche, contrôle à droite (43.9).
class _Ligne extends StatelessWidget {
  const _Ligne({required this.libelle, required this.controle, this.sousTitre});
  final String libelle;
  final Widget controle;
  final String? sousTitre;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Tailles.boutonMin),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(libelle, style: Textes.reglage.copyWith(color: c.encre)),
                if (sousTitre != null)
                  Text(sousTitre!, style: Textes.legende.copyWith(color: c.texteSecondaire)),
              ],
            ),
          ),
          const SizedBox(width: Espaces.e12),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: controle),
          ),
        ],
      ),
    );
  }
}

class _Interrupteur extends StatelessWidget {
  const _Interrupteur({required this.valeur, required this.onChanged, required this.libelle});
  final bool valeur;
  final ValueChanged<bool> onChanged;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Semantics(
      label: libelle,
      child: Switch(
        value: valeur,
        onChanged: onChanged,
        thumbColor: WidgetStatePropertyAll(c.surface),
        trackColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected)
              ? c.violet
              : c.encre.withValues(alpha: Opacites.interrupteurInactif),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}

class _Choix extends StatelessWidget {
  const _Choix({required this.options, required this.valeur, required this.onChanged});
  final Map<String, String> options;
  final String valeur;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Wrap(
      spacing: Espaces.e8,
      runSpacing: Espaces.e8,
      alignment: WrapAlignment.end,
      children: [
        for (final e in options.entries)
          PastilleFiltre(
            libelle: e.value,
            fond: c.lavande,
            actif: e.key == valeur,
            onTap: () => onChanged(e.key),
          ),
      ],
    );
  }
}

Future<String?> _choisirHeure(BuildContext context, String actuelle) async {
  final morceaux = actuelle.split(':');
  final choix = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: int.parse(morceaux[0]), minute: int.parse(morceaux[1])),
    builder: (context, enfant) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: enfant!),
  );
  if (choix == null) return null;
  return '${choix.hour.toString().padLeft(2, '0')}:${choix.minute.toString().padLeft(2, '0')}';
}

class _BoutonHeure extends StatelessWidget {
  const _BoutonHeure({required this.heure, required this.onChanged, required this.libelle});
  final String heure;
  final ValueChanged<String> onChanged;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return PastilleFiltre(
      libelle: heure,
      fond: c.lavande,
      actif: false,
      onTap: () async {
        final choix = await _choisirHeure(context, heure);
        if (choix != null) onChanged(choix);
      },
    );
  }
}

class _SectionArtistes extends ConsumerWidget {
  const _SectionArtistes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final artistes = ref.watch(artistesPreferesProvider);
    return CarteFiche(
      libelle: S.sectionArtistes,
      child: Padding(
        padding: const EdgeInsets.only(top: Espaces.e12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            artistes.when(
              loading: () => const Squelette(hauteur: Tailles.avatarReglages),
              error: (_, _) => Text(S.serveurMuet, style: Textes.corps.copyWith(color: c.texteSecondaire)),
              data: (liste) => liste.isEmpty
                  ? Text(S.aucunArtisteChoisi, style: Textes.corps.copyWith(color: c.texteSecondaire))
                  : Wrap(
                      spacing: Espaces.e8,
                      runSpacing: Espaces.e8,
                      children: [
                        for (var i = 0; i < liste.length; i++)
                          Tooltip(
                            message: liste[i].nom,
                            child: ArtisteAvatar(
                              nom: liste[i].nom,
                              initiales: liste[i].initiales,
                              indexCouleur: i,
                              imageUrl: liste[i].imageUrl,
                              selectionne: false,
                              onTap: null,
                              diametre: Tailles.avatarReglages,
                              avecNom: false,
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: Espaces.e8),
            Align(
              alignment: Alignment.centerLeft,
              child: BoutonLien(
                libelle: S.modifierArtistes,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        OnboardingScreen(depuisReglages: true, onTermine: () => Navigator.of(context).pop()),
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

class _SectionRevisions extends ConsumerWidget {
  const _SectionRevisions({required this.reglages, required this.modifier});
  final Reglages reglages;
  final Future<void> Function(Reglages) modifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final env = ref.watch(environnementProvider);
    final facile = env.cache?.meta(Meta.optionFacile) == true;
    return CarteFiche(
      libelle: S.sectionRevisions,
      child: Column(
        children: [
          _Ligne(
            libelle: S.motsParSession,
            controle: Text('${reglages.motsParSession}', style: Textes.valeur.copyWith(color: c.violet)),
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: c.violet,
              inactiveTrackColor: c.bordure,
              thumbColor: c.violet,
              overlayColor: c.violet.withValues(alpha: Opacites.appui),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: Tailles.pouceCurseur / 2),
            ),
            child: Slider(
              value: reglages.motsParSession.toDouble(),
              min: 5,
              max: 100,
              divisions: 19,
              label: '${reglages.motsParSession}',
              semanticFormatterCallback: (v) => '${v.round()} ${S.motsParSession.toLowerCase()}',
              onChanged: (v) =>
                  ref.read(reglagesProvider.notifier).apercu(reglages.copyWith(motsParSession: v.round())),
              onChangeEnd: (v) => modifier(reglages.copyWith(motsParSession: v.round())),
            ),
          ),
          _Ligne(
            libelle: S.modeRevision,
            controle: _Choix(
              options: const {'rappel': S.modeRappel, 'melange': S.modeMelange},
              valeur: reglages.modeRevision,
              onChanged: (v) => modifier(reglages.copyWith(modeRevision: v)),
            ),
          ),
          _Ligne(
            libelle: S.heureChangementJour,
            controle: _BoutonHeure(
              libelle: S.heureChangementJour,
              heure: reglages.heureChangementJour,
              onChanged: (v) => modifier(reglages.copyWith(heureChangementJour: v)),
            ),
          ),
          if (env.cache != null)
            _Ligne(
              libelle: S.optionFacile,
              controle: _Interrupteur(
                libelle: S.optionFacile,
                valeur: facile,
                onChanged: (v) async {
                  await env.cache!.fixerMeta(Meta.optionFacile, v ? true : null);
                  ref.invalidate(reglagesProvider);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Intervalles proposés (minutes ; 0 : désactivé), mêmes valeurs que le serveur.
const intervallesNotifications = [0, 30, 60, 120, 180, 240, 360];

class _SectionRappels extends ConsumerWidget {
  const _SectionRappels({required this.reglages, required this.modifier});
  final Reglages reglages;
  final Future<void> Function(Reglages) modifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final permission = ref.watch(permissionNotificationsProvider);
    final env = ref.watch(environnementProvider);
    final accordee = permission.valueOrNull ?? false;
    return CarteFiche(
      libelle: S.sectionRappels,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Ligne(
            libelle: S.intervalleNotifications,
            sousTitre: S.sousTitreNotifications,
            controle: _Choix(
              options: {
                for (final m in intervallesNotifications) '$m': m == 0 ? S.desactive : S.toutesLes(m),
              },
              valeur: '${reglages.intervalleNotificationsMin}',
              onChanged: (v) => modifier(reglages.copyWith(intervalleNotificationsMin: int.parse(v))),
            ),
          ),
          if (reglages.intervalleNotificationsMin > 0)
            _Ligne(
              libelle: S.plageNotifications,
              controle: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _BoutonHeure(
                    libelle: S.plageNotifications,
                    heure: reglages.notificationsDebut,
                    onChanged: (v) => modifier(reglages.copyWith(notificationsDebut: v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Espaces.e8),
                    child: Text(S.etJusqua, style: Textes.corps.copyWith(color: c.texteSecondaire)),
                  ),
                  _BoutonHeure(
                    libelle: S.etJusqua,
                    heure: reglages.notificationsFin,
                    onChanged: (v) => modifier(reglages.copyWith(notificationsFin: v)),
                  ),
                ],
              ),
            ),
          if (env.mobile)
            _Ligne(
              libelle: S.permissionNotifications,
              sousTitre: accordee ? S.autorisees : S.refusees,
              controle: accordee
                  ? const SizedBox.shrink()
                  : BoutonLien(
                      libelle: S.autoriser,
                      onPressed: () async {
                        await env.notifications.demanderPermission();
                        ref.invalidate(permissionNotificationsProvider);
                        if (env.cache != null) await env.notifications.reprogrammer(env.cache!);
                      },
                    ),
            ),
          if (env.mobile && !accordee && permission.hasValue)
            Container(
              padding: const EdgeInsets.all(Espaces.e12),
              decoration: BoxDecoration(
                color: c.nouveauFond,
                borderRadius: BorderRadius.circular(Rayons.etiquetteIA),
              ),
              child: Text(S.notificationRefusee, style: Textes.legende.copyWith(color: c.surAccent)),
            ),
          if (env.mobile) ...[
            const SizedBox(height: Espaces.e8),
            Text(S.batterieTexte, style: Textes.legende.copyWith(color: c.texteSecondaire)),
          ],
        ],
      ),
    );
  }
}

class _SectionSync extends ConsumerWidget {
  const _SectionSync({required this.reglages, required this.modifier});
  final Reglages reglages;
  final Future<void> Function(Reglages) modifier;

  Future<void> _synchroniser(BuildContext context, WidgetRef ref) async {
    final env = ref.read(environnementProvider);
    if (await env.connectivite.type() == TypeReseau.mobile && reglages.syncWifiSeulement) {
      if (!context.mounted) return;
      final ok = await confirmer(context, titre: S.syncMobileConfirmation, action: S.confirmer); // SYN-09
      if (!ok) return;
    }
    final resultat = await ref.read(connexionProvider.notifier).synchroniser(manuel: true);
    if (!context.mounted) return;
    final message = switch (resultat) {
      ResultatSync.termine => S.syncTerminee,
      ResultatSync.horsLigne => S.horsLigne,
      ResultatSync.pcInjoignable => '${S.pcInjoignable} ${S.verifierTailscale}',
      ResultatSync.clientTropAncien => S.misAJourRequise,
      _ => null,
    };
    if (message != null) afficherMessage(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final env = ref.watch(environnementProvider);
    final file = ref.watch(fileActionsProvider);
    ref.watch(connexionProvider);
    final derniere = env.cache?.meta(Meta.derniereSync) as String?;
    final derniereTexte = derniere == null
        ? S.jamais
        : DateFormat('d MMM, HH:mm', 'fr_FR').format(DateTime.parse(derniere).toLocal());
    return CarteFiche(
      libelle: S.sectionSync,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Ligne(
            libelle: S.wifiSeulement,
            controle: _Interrupteur(
              libelle: S.wifiSeulement,
              valeur: reglages.syncWifiSeulement,
              onChanged: (v) => modifier(reglages.copyWith(syncWifiSeulement: v)),
            ),
          ),
          _Ligne(
            libelle: S.derniereSync,
            controle: Text(derniereTexte, style: Textes.corps.copyWith(color: c.texteSecondaire)),
          ),
          _Ligne(
            libelle: S.actionsAttente,
            controle: Text('${file.enAttente}', style: Textes.valeur.copyWith(color: c.violet)),
          ),
          const SizedBox(height: Espaces.e8),
          BoutonPrincipal(libelle: S.synchroniserMaintenant, onPressed: () => _synchroniser(context, ref)),
          const SizedBox(height: Espaces.e14),
          Text(S.aExaminer, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
          const SizedBox(height: Espaces.e6),
          if (file.aExaminer.isEmpty)
            Text(S.rienAExaminer, style: Textes.corps.copyWith(color: c.texteSecondaire))
          else
            for (final op in file.aExaminer)
              Container(
                margin: const EdgeInsets.only(bottom: Espaces.e8),
                padding: const EdgeInsets.all(Espaces.e12),
                decoration: BoxDecoration(
                  color: c.enCoursFond,
                  borderRadius: BorderRadius.circular(Rayons.etiquetteIA),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${op.type} — ${op.message ?? op.code ?? ''}',
                      style: Textes.etiquette.copyWith(color: c.erreurTexte),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        BoutonLien(
                          libelle: S.reessayer,
                          onPressed: () => ref.read(fileActionsProvider.notifier).reessayer(op.opId),
                        ),
                        BoutonLien(
                          libelle: S.abandonner,
                          couleur: c.erreurTexte,
                          onPressed: () => ref.read(fileActionsProvider.notifier).abandonner(op.opId),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _SectionServeur extends ConsumerStatefulWidget {
  const _SectionServeur();

  @override
  ConsumerState<_SectionServeur> createState() => _SectionServeurState();
}

class _SectionServeurState extends ConsumerState<_SectionServeur> {
  late final TextEditingController _adresse = TextEditingController(
    text: (ref.read(environnementProvider).cache?.meta(Meta.adresseServeur) as String?) ?? adresseCompilee,
  );
  String? _message;
  bool _test = false;

  /// AND-05 : https et nom de machine, puis test de /api/health avant d'enregistrer.
  Future<void> _tester() async {
    final valeur = _adresse.text.trim();
    final uri = Uri.tryParse(valeur);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || !uri.host.contains('.')) {
      setState(() => _message = S.adresseInvalide);
      return;
    }
    setState(() => _test = true);
    final env = ref.read(environnementProvider);
    final sante = await env.api.sante(adresseTest: valeur);
    if (!mounted) return;
    if (sante != null) {
      await env.cache?.fixerMeta(Meta.adresseServeur, valeur);
      unawaited(ref.read(connexionProvider.notifier).synchroniser());
    }
    setState(() {
      _test = false;
      _message = sante != null ? S.adresseOk : '${S.adresseKo} ${S.verifierTailscale}';
    });
  }

  @override
  void dispose() {
    _adresse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return CarteFiche(
      libelle: S.sectionServeur,
      child: Padding(
        padding: const EdgeInsets.only(top: Espaces.e12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.adresseServeur, style: Textes.reglage.copyWith(color: c.encre)),
            const SizedBox(height: Espaces.e8),
            ChampMot(controleur: _adresse, aide: 'https://mon-pc.tailXXXX.ts.net', max: 200),
            const SizedBox(height: Espaces.e8),
            BoutonPrincipal(libelle: S.tester, onPressed: _test ? null : _tester),
            if (_message != null) ...[
              const SizedBox(height: Espaces.e8),
              Text(_message!, style: Textes.legende.copyWith(color: c.texteSecondaire)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionInformations extends ConsumerWidget {
  const _SectionInformations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final infos = ref.watch(infosServeurProvider);
    final env = ref.watch(environnementProvider);
    final donnees = infos.valueOrNull ?? const {};
    final sante = donnees['sante'] as Sante?;
    final quotas = (donnees['quotas'] as Map<String, dynamic>?)?['apis'] as List<dynamic>?;
    final erreurs = donnees['erreurs'] as List<Map<String, dynamic>>?;
    final style = Textes.corps.copyWith(color: c.texteSecondaire);
    String ollama() => switch (sante?.ollama) {
      'ok' => S.disponible,
      'indisponible' => S.indisponible,
      _ => S.inconnu,
    };
    return CarteFiche(
      libelle: S.sectionInformations,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Ligne(
            libelle: S.version,
            controle: Text(versionApplication, style: style),
          ),
          // Dépannage de la prononciation : lit « Hello » et affiche l'état du moteur.
          _Ligne(
            libelle: S.voixAnglaise,
            controle: BoutonLien(
              libelle: S.testerVoix,
              onPressed: () async {
                final ok = await env.prononciation.prononcer('Hello');
                final etat = await env.prononciation.diagnostic();
                if (context.mounted) {
                  afficherMessage(context, ok ? etat : '${S.prononciationImpossible} ($etat)');
                }
              },
            ),
          ),
          if (sante != null) ...[
            _Ligne(
              libelle: '${S.version} (PC)',
              controle: Text(sante.version, style: style),
            ),
            if (env.cache != null)
              _Ligne(
                libelle: S.curseur,
                controle: Text('${env.cache!.curseur}', style: style),
              ),
            _Ligne(
              libelle: S.ollama,
              controle: Text(ollama(), style: style),
            ),
            _Ligne(
              libelle: S.sauvegarde,
              controle: Text(sante.derniereSauvegarde ?? S.jamais, style: style),
            ),
            if (sante.alerteSauvegarde) // SAV-05
              Container(
                padding: const EdgeInsets.all(Espaces.e12),
                decoration: BoxDecoration(
                  color: c.enCoursFond,
                  borderRadius: BorderRadius.circular(Rayons.etiquetteIA),
                ),
                child: Text(S.sauvegardeEchec, style: Textes.legende.copyWith(color: c.erreurTexte)),
              ),
          ] else if (!infos.isLoading)
            Text(
              env.mobile ? S.pcInjoignable : S.serveurMuet,
              style: Textes.legende.copyWith(color: c.texteSecondaire),
            ),
          if (sante?.apk != null && comparerVersions(versionApplication, '${sante!.apk!['version']}') < 0)
            Padding(
              padding: const EdgeInsets.only(top: Espaces.e8),
              child: PastilleSimple(
                libelle: S.nouvelleVersion,
                fond: c.nouveauFond,
                texte: c.surAccent,
              ), // AND-18
            ),
          if (quotas != null) ...[
            const SizedBox(height: Espaces.e8),
            Text(S.quotas, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
            for (final q in quotas.cast<Map<String, dynamic>>())
              _Ligne(
                libelle: q['api'] as String,
                controle: Text(
                  q['api'] == 'deepl'
                      ? '${q['caracteres_mois']} / ${q['limite_mois']}'
                      : '${q['nb']}${q['limite'] == null ? '' : ' / ${q['limite']}'}',
                  style: Textes.corps.copyWith(
                    color: q['alerte'] == true ? c.erreurTexte : c.texteSecondaire,
                  ),
                ),
              ),
          ],
          if (erreurs != null && !env.mobile) ...[
            const SizedBox(height: Espaces.e8),
            Text(S.erreursRecentes, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
            const SizedBox(height: Espaces.e4),
            if (erreurs.isEmpty)
              Text(S.aucuneErreur, style: style)
            else
              for (final e in erreurs.take(5))
                Text(
                  '${e['horodatage'] ?? ''} · ${e['evenement'] ?? ''} ${e['code'] ?? e['type_exception'] ?? ''}',
                  style: Textes.legende.copyWith(color: c.texteSecondaire),
                ),
          ],
        ],
      ),
    );
  }
}

class _SectionApparence extends ConsumerWidget {
  const _SectionApparence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    final valeur = switch (mode) {
      ThemeMode.dark => 'sombre',
      ThemeMode.system => 'systeme',
      ThemeMode.light => 'clair',
    };
    return CarteFiche(
      libelle: S.sectionApparence,
      child: _Ligne(
        libelle: S.theme,
        controle: _Choix(
          options: const {'clair': S.themeClair, 'sombre': S.themeSombre, 'systeme': S.themeSysteme},
          valeur: valeur,
          onChanged: (v) => choisirTheme(ref, switch (v) {
            'sombre' => ThemeMode.dark,
            'systeme' => ThemeMode.system,
            _ => ThemeMode.light,
          }),
        ),
      ),
    );
  }
}

class _SectionDonnees extends ConsumerWidget {
  const _SectionDonnees();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CarteFiche(
      libelle: S.sectionDonnees,
      child: Padding(
        padding: const EdgeInsets.only(top: Espaces.e8),
        child: BoutonLien(
          libelle: S.exporter,
          onPressed: () async {
            try {
              final donnees = await ref.read(depotProvider).exporter();
              await Clipboard.setData(
                ClipboardData(text: const JsonEncoder.withIndent('  ').convert(donnees)),
              );
              if (context.mounted) afficherMessage(context, S.exportPret);
            } on Exception {
              if (context.mounted) afficherMessage(context, S.serveurMuet);
            }
          },
        ),
      ),
    );
  }
}
