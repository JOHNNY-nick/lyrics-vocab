// Cache local, dépôt hors-ligne et synchronisation client (41.5, SYN-T01, CLI-01 à CLI-05).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_vocab/models/divers.dart';
import 'package:lyrics_vocab/services/api_client.dart';
import 'package:lyrics_vocab/models/revision.dart';
import 'package:lyrics_vocab/services/depot_donnees.dart';
import 'package:lyrics_vocab/services/depot_local.dart';
import 'package:lyrics_vocab/services/local_cache.dart';
import 'package:lyrics_vocab/services/sm2.dart';
import 'package:lyrics_vocab/services/sync_service.dart';

import 'outils.dart';

class Contexte {
  Contexte(this.cache, this.serveur, this.depot, this.sync);
  final LocalCache cache;
  final FauxServeur serveur;
  final DepotLocal depot;
  final SyncService sync;
}

Future<Contexte> preparer({TypeReseau reseau = TypeReseau.wifi, Gestionnaire? gestionnaire}) async {
  final cache = LocalCache(ouvrirMagasinMemoire);
  await cache.ouvrir();
  final serveur = FauxServeur(gestionnaire ?? (r, c) => (200, santeOk()));
  final api = apiDeTest(serveur);
  final sync = SyncService(
    api: api,
    cache: cache,
    appareilId: () => 'android-test',
    typeReseau: () async => reseau,
  );
  final depot = DepotLocal(
    cache: cache,
    api: api,
    declencherSync: () {},
    serveurJoignable: () => false,
    horloge: () => DateTime(2026, 10, 12, 10),
  );
  return Contexte(cache, serveur, depot, sync);
}

/// Faux serveur minimal : accuse toutes les opérations et renvoie une page vide.
Gestionnaire serveurAccusant({
  List<List<Map<String, dynamic>>>? lots,
  Map<String, String> rejets = const {},
}) => (r, corps) {
  if (r.path.endsWith('/health')) return (200, santeOk());
  if (r.path.endsWith('/sync/push')) {
    final ops = (corps!['operations'] as List).cast<Map<String, dynamic>>();
    lots?.add(ops);
    return (
      200,
      {
        'resultats': [
          for (final op in ops)
            rejets.containsKey(op['type'])
                ? {'op_id': op['op_id'], 'statut': 'rejete', 'code': rejets[op['type']], 'message': 'refus'}
                : {'op_id': op['op_id'], 'statut': 'applique', 'donnees': null},
        ],
      },
    );
  }
  if (r.path.endsWith('/sync/pull')) {
    return (200, {'curseur': 0, 'a_suite': false, 'changements': <String, dynamic>{}});
  }
  return (404, {'code': 'introuvable', 'message': 'x', 'details': {}});
};

void main() {
  test('Scénario A (SYN-T01) : actions hors ligne, file conservée, envoi dans l\'ordre', () async {
    final ctx = await preparer(reseau: TypeReseau.aucun);
    final a = await ctx.depot.creerMot('lowkey');
    await ctx.depot.creerMot('vibe');
    expect((await ctx.depot.creerMot('Lowkey')).dejaPresent, isTrue);
    expect(a.mot.statutEnrichissement, 'en_attente'); // AND-09
    final dues = await ctx.depot.revisionsDues();
    expect(dues.totalDus, 2);
    await ctx.depot.repondre(dues.items.first, const ReponseCarte(qualite: Notes.savais));
    expect(await ctx.sync.synchroniser(), ResultatSync.horsLigne);
    expect(ctx.cache.file().map((o) => o.type), ['mot.creer', 'mot.creer', 'revision.repondre']);

    final lots = <List<Map<String, dynamic>>>[];
    ctx.serveur.gestionnaire = serveurAccusant(lots: lots);
    final sync = SyncService(
      api: ctx.sync.api,
      cache: ctx.cache,
      appareilId: () => 'android-test',
      typeReseau: () async => TypeReseau.wifi,
    );
    expect(await sync.synchroniser(), ResultatSync.termine);
    expect(lots.single.map((o) => o['type']), ['mot.creer', 'mot.creer', 'revision.repondre']);
    expect(ctx.cache.file(), isEmpty);
    final reponse = lots.single.last['donnees'] as Map<String, dynamic>;
    expect(reponse['nouvelle_revision_id'], isNotNull);
    expect(reponse['qualite'], 4);
  });

  test('SM-2 local et mots dus (AND-10, REV-T06)', () async {
    final ctx = await preparer();
    await ctx.depot.creerMot('ain\'t');
    final due = (await ctx.depot.revisionsDues()).items.single;
    await ctx.depot.repondre(due, const ReponseCarte(qualite: Notes.neSavaisPas));
    final mot = ctx.cache.mot(due.motId)!;
    expect(mot.nbEchecs, 1);
    expect(mot.prochaineRevision, DateTime.utc(2026, 10, 13));
    expect((await ctx.depot.revisionsDues()).totalDus, 0);
    expect(ctx.depot.serieJours(DateTime.utc(2026, 10, 12)), 1);
  });

  test('erreur réseau avant l\'accusé : la file est conservée (client_accuse, SYN-T03)', () async {
    final ctx = await preparer();
    await ctx.depot.creerMot('gonna');
    var appels = 0;
    ctx.serveur.gestionnaire = (r, c) {
      if (r.path.endsWith('/health')) return (200, santeOk());
      appels++;
      return (503, {'code': 'erreur_interne', 'message': 'x', 'details': {}});
    };
    expect(await ctx.sync.synchroniser(), ResultatSync.erreur);
    ctx.sync.annulerReessai();
    expect(appels, 1);
    expect(ctx.cache.file().length, 1);
  });

  test('opération rejetée : déplacée dans « à examiner » (SYN-13)', () async {
    final ctx = await preparer();
    await ctx.depot.creerMot('slay');
    await ctx.depot.supprimerMot(ctx.cache.tousMots().single.id);
    ctx.serveur.gestionnaire = serveurAccusant(rejets: {'mot.supprimer': 'operation_inconnue'});
    expect(await ctx.sync.synchroniser(), ResultatSync.termine);
    expect(ctx.cache.file(), isEmpty);
    expect(ctx.cache.aExaminer().single.code, 'operation_inconnue');
    await ctx.cache.reessayer(ctx.cache.aExaminer().single.opId);
    expect(ctx.cache.file().single.type, 'mot.supprimer');
  });

  test('PC injoignable : aucun envoi, état pcInjoignable (ENV-T07)', () async {
    final ctx = await preparer();
    ctx.serveur.coupe = true;
    await ctx.depot.creerMot('vibe');
    expect(await ctx.sync.synchroniser(), ResultatSync.pcInjoignable);
    ctx.sync.annulerReessai();
    expect(ctx.cache.file().length, 1);
  });

  test('Wi-Fi seulement : pas de cycle sur données mobiles sauf manuel (SYN-09)', () async {
    final ctx = await preparer(reseau: TypeReseau.mobile, gestionnaire: serveurAccusant());
    await ctx.cache.ecrireReglages(ctx.cache.reglages().copyWith(syncWifiSeulement: true));
    expect(await ctx.sync.synchroniser(), ResultatSync.wifiSeulement);
    expect(await ctx.sync.synchroniser(manuel: true), ResultatSync.termine);
  });

  test('verrou : deux déclenchements simultanés, un seul cycle (client_verrou)', () async {
    final ctx = await preparer(gestionnaire: serveurAccusant());
    final resultats = await Future.wait([ctx.sync.synchroniser(), ctx.sync.synchroniser()]);
    expect(resultats, contains(ResultatSync.ignore));
    expect(ctx.serveur.requetes.where((r) => r.path.endsWith('/health')).length, 1);
  });

  test('base vide puis pull complet en pages, le serveur fait foi (client_base_vide)', () async {
    final ctx = await preparer();
    expect(ctx.cache.reinitialise, isTrue);
    final sinceRecus = <int>[];
    ctx.serveur.gestionnaire = (r, c) {
      if (r.path.endsWith('/health')) return (200, santeOk());
      if (r.path.endsWith('/sync/push')) return (200, {'resultats': []});
      final since = int.parse('${r.queryParameters['since']}');
      sinceRecus.add(since);
      if (since == 0) {
        return (
          200,
          {
            'curseur': 5,
            'a_suite': true,
            'changements': {
              'mots': [
                {
                  'id': 'm1',
                  'terme': 'lowkey',
                  'terme_normalise': 'lowkey',
                  'statut_enrichissement': 'ok',
                  'niveau': 'nouveau',
                },
              ],
              'revisions': [
                {
                  'id': 'r1',
                  'mot_id': 'm1',
                  'date_prevue': '2026-10-01',
                  'statut': 'planifiee',
                  'mode': 'rappel',
                },
              ],
            },
          },
        );
      }
      return (
        200,
        {
          'curseur': 9,
          'a_suite': false,
          'changements': {
            'extraits': [
              {
                'id': 'e1',
                'mot_id': 'm1',
                'texte': 'I lowkey miss you',
                'surbrillance_debut': 2,
                'surbrillance_fin': 8,
                'hors_liste': false,
                'titre': 'T',
                'artiste': 'A',
              },
            ],
            'reglages': [
              {
                'frequence_rappels': 'quotidien',
                'heure_rappel': '20:00',
                'mots_par_session': 10,
                'mode_revision': 'rappel',
                'heure_changement_jour': '04:00',
                'sync_wifi_seulement': false,
              },
            ],
          },
        },
      );
    };
    expect(await ctx.sync.synchroniser(), ResultatSync.termine);
    expect(sinceRecus, [0, 5]);
    expect(ctx.cache.curseur, 9);
    expect(ctx.cache.reglages().heureRappel, '20:00');
    final dues = await ctx.depot.revisionsDues();
    expect(dues.items.single.indice, 'I ______ miss you');
  });

  test('curseur invalide : synchronisation complète (CL-25)', () async {
    final ctx = await preparer();
    await ctx.cache.fixerCurseur(999);
    final sinceRecus = <String>[];
    ctx.serveur.gestionnaire = (r, c) {
      if (r.path.endsWith('/health')) return (200, santeOk());
      if (r.path.endsWith('/sync/push')) return (200, {'resultats': []});
      sinceRecus.add('${r.queryParameters['since']}');
      if (r.queryParameters['since'].toString() == '999') {
        return (400, {'code': 'curseur_invalide', 'message': 'x', 'details': {}});
      }
      return (200, {'curseur': 3, 'a_suite': false, 'changements': <String, dynamic>{}});
    };
    expect(await ctx.sync.synchroniser(), ResultatSync.termine);
    expect(sinceRecus, ['999', '0']);
    expect(ctx.cache.curseur, 3);
  });

  test('fusion : le mot local est remplacé et les réponses réaffectées (CLI-03)', () async {
    final ctx = await preparer();
    final local = (await ctx.depot.creerMot('vibe')).mot;
    final due = (await ctx.depot.revisionsDues()).items.single;
    await ctx.depot.repondre(due, const ReponseCarte(qualite: 4));
    final lots = <List<Map<String, dynamic>>>[];
    var lot = 0;
    ctx.serveur.gestionnaire = (r, corps) {
      if (r.path.endsWith('/health')) return (200, santeOk());
      if (r.path.endsWith('/sync/push')) {
        final ops = (corps!['operations'] as List).cast<Map<String, dynamic>>();
        lots.add(ops);
        lot++;
        return (
          200,
          {
            'resultats': [
              {
                'op_id': ops.first['op_id'],
                'statut': 'applique',
                'donnees': {'mot_id': 'serveur-1', 'id_local': local.id, 'fusion': true, 'cree': false},
              },
              // la réponse n'est pas acquittée dans ce premier lot
            ],
          },
        );
      }
      return (200, {'curseur': 0, 'a_suite': false, 'changements': <String, dynamic>{}});
    };
    await ctx.sync.synchroniser();
    expect(lot, greaterThanOrEqualTo(2));
    expect(ctx.cache.mot(local.id), isNull);
    expect(lots[1].single['donnees']['mot_id'], 'serveur-1');
  });

  test('révision du serveur : une seule planifiée par mot', () async {
    final ctx = await preparer();
    await ctx.cache.ecrireRevision(Revision(id: 'local', motId: 'm', datePrevue: DateTime.utc(2026, 10, 13)));
    await ctx.sync.appliquerChangements({
      'revisions': [
        {
          'id': 'serveur',
          'mot_id': 'm',
          'date_prevue': '2026-10-15',
          'statut': 'planifiee',
          'mode': 'rappel',
        },
      ],
    });
    expect(ctx.cache.revisions().map((r) => r.id), ['serveur']);
  });

  test('client trop ancien : pas de synchronisation (CL-32)', () async {
    final ctx = await preparer(gestionnaire: (r, c) => (200, santeOk(versionMin: '9.0.0')));
    await ctx.depot.creerMot('lowkey');
    expect(await ctx.sync.synchroniser(), ResultatSync.clientTropAncien);
    expect(ctx.cache.file().length, 1);
  });

  test('version de schéma local incompatible : données vidées, file conservée (FLU-05)', () async {
    final magasins = <String, Magasin>{};
    Future<Magasin> ouvrir(String nom) async => magasins.putIfAbsent(nom, MagasinMemoire.new);
    final cache = LocalCache(ouvrir);
    await cache.ouvrir();
    final depot = DepotLocal(
      cache: cache,
      api: apiDeTest(FauxServeur((r, c) => (200, null))),
      declencherSync: () {},
      serveurJoignable: () => false,
    );
    await depot.creerMot('lowkey');
    await magasins[Boites.meta]!.ecrire(Meta.versionSchema, {'v': 0});
    final rouvert = LocalCache(ouvrir);
    await rouvert.ouvrir();
    expect(rouvert.tousMots(), isEmpty);
    expect(rouvert.file().length, 1);
    expect(rouvert.reinitialise, isTrue);
  });

  test("tunnel : code d'invitation demandé, puis accepté ; adresse retrouvée", () async {
    final cache = LocalCache(ouvrirMagasinMemoire);
    await cache.ouvrir();
    var adresse = 'https://ancienne.test/api';
    String? code;
    final codesVus = <String?>[];
    final serveur = FauxServeur((r, corps) {
      if (r.uri.host == 'api.github.com') return (200, {'adresse': 'https://nouvelle.trycloudflare.com'});
      if (r.uri.host == 'ancienne.test') return (502, null); // ancien tunnel fermé
      codesVus.add(r.headers['X-Code-Acces'] as String?);
      if (r.path.endsWith('/health')) return (200, santeOk());
      if (r.headers['X-Code-Acces'] != 'LV-AAAA-BBBB') {
        return (401, {'code': 'code_acces_requis', 'message': 'x', 'details': {}});
      }
      return serveurAccusant()(r, corps);
    });
    final api = ApiClient(
      Dio()..httpClientAdapter = serveur,
      () => adresse,
      fuseau: () => 'Europe/Paris',
      appareilId: () => 'android-test',
      codeAcces: () => code,
    );
    final etats = <EtatConnexion>[];
    final sync = SyncService(
      api: api,
      cache: cache,
      appareilId: () => 'android-test',
      typeReseau: () async => TypeReseau.wifi,
      surEtat: (e, _) => etats.add(e),
      decouvrir: () async {
        final publiee = await api.adressePubliee();
        if (publiee == null || publiee == adresse) return false;
        adresse = '$publiee/api';
        return true;
      },
    );
    await sync.synchroniser();
    expect(adresse, 'https://nouvelle.trycloudflare.com/api');
    expect(etats.last, EtatConnexion.codeAccesRequis);
    code = 'LV-AAAA-BBBB';
    expect(await sync.synchroniser(), ResultatSync.termine);
    expect(etats.last, EtatConnexion.enLigne);
    expect(codesVus.last, 'LV-AAAA-BBBB');
    sync.annulerReessai();
  });
}
