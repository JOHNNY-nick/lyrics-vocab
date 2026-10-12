// Conversion JSON sur les exemples du chapitre 18 (FLU-03, T-26).
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_vocab/models/divers.dart';
import 'package:lyrics_vocab/models/mot.dart';
import 'package:lyrics_vocab/models/revision.dart';

void main() {
  test('18.1 création d\'un mot', () {
    final mot = Mot.fromJson({
      'id': '9d4e6b1a-2c7f-4a0e-8f55-3b1c0d2a7e11',
      'terme': 'Lowkey',
      'terme_normalise': 'lowkey',
      'traduction_fr': null,
      'explication': null,
      'source_explication': null,
      'statut_enrichissement': 'en_attente',
      'niveau': 'nouveau',
      'nb_echecs': 0,
      'extraits': [],
      'prochaine_revision': '2026-10-12',
      'created_at': '2026-10-12T08:14:00Z',
      'updated_at': '2026-10-12T08:14:00Z',
    });
    expect(mot.termeNormalise, 'lowkey');
    expect(mot.enrichissementTermine, isFalse);
    expect(mot.prochaineRevision, DateTime.utc(2026, 10, 12));
    expect(mot.createdAt, DateTime.utc(2026, 10, 12, 8, 14));
    expect(Mot.fromJson(mot.toJson()).toJson(), mot.toJson());
  });

  test('18.2 fiche avec extrait', () {
    final mot = Mot.fromJson({
      'id': '9d4e',
      'terme': 'Lowkey',
      'terme_normalise': 'lowkey',
      'traduction_fr': 'discrètement ; plutôt',
      'explication': 'Argot : « lowkey » signifie « un peu ».',
      'source_explication': 'ia',
      'statut_enrichissement': 'ok',
      'niveau': 'en_cours',
      'nb_echecs': 1,
      'extraits': [
        {
          'id': 'c0a1',
          'texte': "I lowkey miss you\nBut I'm never saying that",
          'surbrillance_debut': 2,
          'surbrillance_fin': 8,
          'hors_liste': false,
          'morceau': {'titre': 'Titre', 'artiste': 'Artiste', 'url_genius': null},
        },
      ],
      'prochaine_revision': '2026-10-15',
    });
    expect(mot.extraits.single.titre, 'Titre');
    expect(mot.extraits.single.motId, '9d4e');
    expect(mot.estArgot, isTrue);
    expect(mot.explicationIA, isTrue);
  });

  test('18.4 révisions dues et réponse', () {
    final dues = RevisionsDues.fromJson({
      'total_dus': 7,
      'jour': '2026-10-12',
      'items': [
        {
          'id': 'a7b8',
          'mot_id': '9d4e',
          'mode': 'rappel',
          'date_prevue': '2026-10-10',
          'terme': 'Lowkey',
          'traduction_fr': 'discrètement',
          'indice': "I ____ miss you\nBut I'm never saying that",
        },
      ],
    });
    expect(dues.totalDus, 7);
    expect(dues.items.single.indice, contains('____'));
    final resultat = ResultatReponse.fromJson({
      'statut': 'applique',
      'prochaine_date': '2026-10-13',
      'intervalle_jours': 1,
      'facilite': 2.5,
      'repetitions': 1,
      'niveau': 'en_cours',
    });
    expect(resultat.prochaineDate, DateTime.utc(2026, 10, 13));
  });

  test('18.5 exercice et verdict', () {
    expect(
      Exercice.fromJson({'id': 'e1f2', 'phrase_fr': 'Je suis discrètement content.', 'generee': true}).id,
      'e1f2',
    );
    final verdict = Verdict.fromJson({
      'verdict': 'correct',
      'explication': 'Bonne traduction.',
      'verdict_repli': false,
      'reference_en': "I'm lowkey happy to see you.",
    });
    expect(verdict.verdict, 'correct');
  });

  test('18.6 réglages et artistes', () {
    final r = Reglages.fromJson({
      'frequence_rappels': 'quotidien',
      'heure_rappel': '19:00',
      'mots_par_session': 20,
      'mode_revision': 'rappel',
      'heure_changement_jour': '04:00',
      'sync_wifi_seulement': false,
    });
    expect(r.toJson()['heure_rappel'], '19:00');
    expect(r.copyWith(motsParSession: 30).difference(r), {'mots_par_session': 30});
    expect(const Artiste(nom: 'Artiste A', geniusId: 1234).toEntree(), {
      'genius_id': 1234,
      'nom': 'Artiste A',
      'image_url': null,
    });
  });

  test('pull : extrait à plat et révision', () {
    final page = PageChangements.fromJson({
      'curseur': 1311,
      'a_suite': false,
      'changements': {
        'mots': [],
        'extraits': [
          {
            'id': 'e',
            'mot_id': 'm',
            'texte': 'good vibe',
            'surbrillance_debut': 5,
            'surbrillance_fin': 9,
            'hors_liste': true,
            'titre': 'T',
            'artiste': 'A',
            'deleted_at': null,
          },
        ],
        'revisions': [
          {
            'id': 'r',
            'mot_id': 'm',
            'date_prevue': '2026-10-13',
            'repetitions': 1,
            'facilite': 2.5,
            'intervalle_jours': 1,
            'statut': 'planifiee',
            'mode': 'rappel',
          },
        ],
      },
    });
    expect(page.curseur, 1311);
    expect(page.changements['extraits']!.single['titre'], 'T');
    expect(Revision.fromJson(page.changements['revisions']!.single).planifiee, isTrue);
  });
}
