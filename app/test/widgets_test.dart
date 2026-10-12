// Tests d'interface (41.6, PWA-T08, QUAL-02).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lyrics_vocab/app.dart';
import 'package:lyrics_vocab/models/divers.dart';
import 'package:lyrics_vocab/models/extrait.dart';
import 'package:lyrics_vocab/providers/providers.dart';
import 'package:lyrics_vocab/services/connectivite_service.dart';
import 'package:lyrics_vocab/services/depot_local.dart';
import 'package:lyrics_vocab/services/local_cache.dart';
import 'package:lyrics_vocab/services/notifications_service.dart';
import 'package:lyrics_vocab/strings.dart';
import 'package:lyrics_vocab/widgets/composants.dart';

import 'outils.dart';

class Banc {
  Banc(this.cache, this.depot, this.env, this.prefs);
  final LocalCache cache;
  final DepotLocal depot;
  final Environnement env;
  final Magasin prefs;
}

Future<Banc> preparerBanc({bool onboardingFait = true}) async {
  final cache = LocalCache(ouvrirMagasinMemoire);
  await cache.ouvrir();
  final api = apiDeTest(FauxServeur((r, c) => (200, santeOk())));
  final depot = DepotLocal(cache: cache, api: api, declencherSync: () {}, serveurJoignable: () => false);
  final env = Environnement(
    mobile: true,
    api: api,
    depot: depot,
    cache: cache,
    connectivite: ConnectiviteNeutre(),
    notifications: NotificationsNeutres(),
  );
  final prefs = MagasinMemoire();
  if (onboardingFait) await prefs.ecrire(Meta.onboardingFait, {'v': true});
  return Banc(cache, depot, env, prefs);
}

Future<void> lancer(WidgetTester tester, Banc banc, {Size taille = const Size(390, 844)}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        environnementProvider.overrideWithValue(banc.env),
        prefsProvider.overrideWithValue(banc.prefs),
      ],
      child: const Application(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> arreter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> ajouterExtrait(Banc banc, String motId, {bool horsListe = false}) async {
  await banc.cache.ecrireExtrait(
    Extrait(
      id: 'e-$motId',
      motId: motId,
      texte: "I lowkey miss you\nBut I'm never saying that",
      surbrillanceDebut: 2,
      surbrillanceFin: 8,
      horsListe: horsListe,
      titre: 'Titre',
      artiste: 'Artiste',
    ),
  );
  final mot = banc.cache.motBrut(motId)!;
  await banc.cache.ecrireMot(
    mot.copyWith(
      traductionFr: 'discrètement',
      explication: 'Argot : veut dire un peu.',
      sourceExplication: 'ia',
      statutEnrichissement: 'ok',
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    Intl.defaultLocale = 'fr_FR';
  });

  testWidgets('ajout_vide puis ajout_valide : bouton désactivé, navigation vers la fiche', (tester) async {
    final banc = await preparerBanc();
    await lancer(tester, banc);
    await tester.tap(find.text(S.navAjouter).last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(S.ajouterUnMot), findsWidgets);
    final bouton = find.widgetWithText(BoutonPrincipal, S.ajouter);
    expect(tester.widget<BoutonPrincipal>(bouton).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, 'lowkey');
    await tester.pump();
    expect(tester.widget<BoutonPrincipal>(bouton).onPressed, isNotNull);
    await tester.tap(bouton);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(S.ficheDuMot), findsOneWidget);
    expect(find.text(S.enrichissementEnCours), findsOneWidget);
    expect(find.byType(Squelette), findsWidgets);
    await arreter(tester);
  });

  testWidgets('ajout_doublon : message « déjà dans ta bibliothèque »', (tester) async {
    final banc = await preparerBanc();
    await banc.depot.creerMot('vibe');
    await lancer(tester, banc);
    await tester.tap(find.text(S.navAjouter).last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, 'Vibe');
    await tester.pump();
    await tester.tap(find.widgetWithText(BoutonPrincipal, S.ajouter));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(S.motDejaPresent), findsOneWidget);
    expect(find.text(S.voirLaFiche), findsOneWidget);
    await arreter(tester);
  });

  testWidgets('fiche_etats et fiche_hors_liste : étiquette IA et mention hors liste', (tester) async {
    final banc = await preparerBanc();
    final mot = (await banc.depot.creerMot('lowkey')).mot;
    await ajouterExtrait(banc, mot.id, horsListe: true);
    await lancer(tester, banc);
    await tester.tap(find.text(S.navMots).last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('lowkey').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(S.ficheDuMot), findsOneWidget);
    expect(find.text(S.etiquetteIA), findsOneWidget);
    expect(find.text(S.horsListe), findsOneWidget);
    expect(find.text(S.argot), findsOneWidget);
    expect(find.text('Titre — Artiste'), findsOneWidget);
    await arreter(tester);
  });

  testWidgets('revision_deroule : révéler, répondre, annuler, récapitulatif', (tester) async {
    final banc = await preparerBanc();
    final mot = (await banc.depot.creerMot('lowkey')).mot;
    await ajouterExtrait(banc, mot.id);
    await lancer(tester, banc);
    expect(find.text(S.motsAReviser(1)), findsOneWidget);
    await tester.tap(find.text(S.commencer));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(S.devineLeMot), findsOneWidget);
    expect(find.text(S.aideBoutons), findsOneWidget);
    final savais = find.widgetWithText(BoutonPrincipal, S.savais);
    expect(tester.widget<BoutonPrincipal>(savais).onPressed, isNull); // MAQ-06
    await tester.ensureVisible(find.text(S.reveler));
    await tester.tap(find.text(S.reveler));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('discrètement'), findsOneWidget);
    expect(tester.widget<BoutonPrincipal>(savais).onPressed, isNotNull);
    await tester.ensureVisible(savais);
    await tester.tap(savais);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(S.annuler), findsOneWidget);
    await tester.tap(find.text(S.annuler));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('discrètement'), findsOneWidget); // retour sur la carte
    expect(banc.cache.file().where((o) => o.type == 'revision.repondre'), isEmpty);
    await tester.ensureVisible(find.widgetWithText(BoutonPrincipal, S.savais));
    await tester.tap(find.widgetWithText(BoutonPrincipal, S.savais));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(S.bienJoue), findsOneWidget);
    expect(banc.cache.file().where((o) => o.type == 'revision.repondre').length, 1);
    await arreter(tester);
  });

  testWidgets('revision_vide : « Rien à réviser aujourd\'hui »', (tester) async {
    final banc = await preparerBanc();
    await lancer(tester, banc);
    await tester.tap(find.text(S.navRevisions).last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Rien à réviser aujourd\'hui'), findsOneWidget);
    await arreter(tester);
  });

  testWidgets('bandeaux : hors ligne et PC injoignable', (tester) async {
    final banc = await preparerBanc();
    await lancer(tester, banc);
    final element = tester.element(find.byType(MaterialApp));
    final conteneur = ProviderScope.containerOf(element);
    conteneur.read(connexionProvider.notifier).surEtat(EtatConnexion.horsLigne, null);
    await tester.pump();
    expect(find.text(S.horsLigne), findsOneWidget);
    conteneur.read(connexionProvider.notifier).surEtat(EtatConnexion.pcInjoignable, null);
    await tester.pump();
    expect(find.text(S.pcInjoignable), findsOneWidget);
    await arreter(tester);
  });

  testWidgets('onboarding : compteur, bouton désactivé puis activé', (tester) async {
    final banc = await preparerBanc(onboardingFait: false);
    await lancer(tester, banc);
    expect(find.text(S.choisisArtistes), findsOneWidget);
    expect(find.text(S.choisis(0)), findsOneWidget);
    expect(find.text(S.choisisAuMoinsUn), findsOneWidget);
    await tester.tap(find.text('Drake'));
    await tester.pump();
    expect(find.text(S.continuerAvec(1)), findsOneWidget);
    await tester.tap(find.text(S.continuerAvec(1)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(banc.cache.artistesPreferes().single.nom, 'Drake');
    expect(banc.cache.file().single.type, 'artistes.modifier');
    await arreter(tester);
  });

  for (final largeur in [360.0, 768.0, 1280.0]) {
    testWidgets('responsive à $largeur px : aucun débordement sur les quatre onglets', (tester) async {
      final banc = await preparerBanc();
      for (final terme in ['lowkey', 'break up', 'a very long expression here ok']) {
        final mot = (await banc.depot.creerMot(terme)).mot;
        await ajouterExtrait(banc, mot.id);
      }
      await lancer(tester, banc, taille: Size(largeur, 800));
      for (final onglet in [S.navMots, S.navAjouter, S.navReglages, S.navRevisions]) {
        await tester.tap(find.text(onglet).last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: onglet);
      }
      await arreter(tester);
    });
  }

  testWidgets('accessibilité : zones tactiles d\'au moins 48 dp sur la navigation', (tester) async {
    final banc = await preparerBanc();
    await lancer(tester, banc);
    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
    await arreter(tester);
  });

  test('réglages par défaut', () => expect(const Reglages().motsParSession, 20));
}
