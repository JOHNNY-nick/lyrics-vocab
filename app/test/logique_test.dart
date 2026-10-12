// SM-2, normalisation, jour local, masquage, rappels : mêmes cas que le backend (REV-T01, ALG-01).
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_vocab/models/divers.dart';
import 'package:lyrics_vocab/models/revision.dart';
import 'package:lyrics_vocab/services/calendrier.dart';
import 'package:lyrics_vocab/services/extraction.dart';
import 'package:lyrics_vocab/services/normalisation.dart';
import 'package:lyrics_vocab/services/notifications_service.dart';
import 'package:lyrics_vocab/services/sm2.dart';
import 'package:lyrics_vocab/services/sync_service.dart';

void main() {
  group('SM-2 (F.4)', () {
    const cas = [
      ([0, 2.5, 0], 4, [1, 2.5, 1]),
      ([1, 2.5, 1], 4, [2, 2.5, 3]),
      ([2, 2.5, 3], 4, [3, 2.5, 8]),
      ([3, 2.5, 8], 5, [4, 2.6, 20]),
      ([3, 2.5, 8], 3, [4, 2.36, 20]),
      ([3, 2.5, 8], 1, [0, 2.5, 1]),
      ([2, 1.3, 3], 3, [3, 1.3, 4]),
      ([0, 2.5, 0], 0, [0, 2.5, 1]),
    ];
    for (var i = 0; i < cas.length; i++) {
      final (depart, q, attendu) = cas[i];
      test('sm2_cas_${i + 1}', () {
        final r = appliquerSm2(
          EtatRevision(
            repetitions: depart[0].toInt(),
            facilite: depart[1].toDouble(),
            intervalleJours: depart[2].toInt(),
          ),
          q,
        );
        expect([r.repetitions, r.facilite, r.intervalleJours], attendu);
      });
    }
    test('sm2_plafond', () {
      expect(
        appliquerSm2(
          const EtatRevision(repetitions: 5, facilite: 2.5, intervalleJours: 200),
          4,
        ).intervalleJours,
        365,
      );
    });
    test('sm2_facilite_minimale', () {
      expect(
        appliquerSm2(const EtatRevision(repetitions: 3, facilite: 1.3, intervalleJours: 10), 3).facilite,
        1.3,
      );
    });
    test('niveaux', () {
      expect(niveauDepuisEtat(const EtatRevision(repetitions: 4, intervalleJours: 22), 4), 'acquis');
      expect(niveauDepuisEtat(const EtatRevision(intervalleJours: 1), 1, niveauActuel: 'acquis'), 'en_cours');
      expect(niveauDepuisEtat(const EtatRevision(intervalleJours: 1), 1), 'nouveau');
    });
  });

  group('Normalisation (B.5, ALG-01)', () {
    const exemples = {
      'Lowkey': 'lowkey',
      'Ain’t': "ain't",
      '"break up"': 'break up',
      'Well-known!': 'well-known',
      'GONNA': 'gonna',
      "Rock 'n' Roll": "rock 'n' roll",
      'Y’all': "y'all",
      '(Ride or die)': 'ride or die',
      'Ça va': 'ça va',
      'Ça va': 'ça va',
    };
    exemples.forEach((saisie, attendu) {
      test(saisie, () => expect(normaliser(saisie), attendu));
    });
    for (final refus in ['!!!', 'a' * 101, 'a b c d e f g', '2024', '   ']) {
      test('refus « $refus »', () {
        expect(validerTerme(refus, messageVide: 'v', messageTropLong: 'l').valide, isFalse);
      });
    }
    test('accepte', () {
      expect(validerTerme('  Break   UP ', messageVide: 'v', messageTropLong: 'l').normalise, 'break up');
    });
    test('recherche sans accents', () => expect(formeComparable('CAFÉ'), 'cafe'));
  });

  group('Jour local (20.6)', () {
    test('jour_local_nuit', () {
      expect(jourLocalDepuisHeureLocale(DateTime(2026, 10, 13, 1, 30), '04:00'), DateTime.utc(2026, 10, 12));
    });
    test('jour_local_ete', () {
      expect(jourLocalDepuisHeureLocale(DateTime(2026, 10, 25, 20, 0), '04:00'), DateTime.utc(2026, 10, 25));
      expect(datePrevue(DateTime.utc(2026, 10, 24), 1), DateTime.utc(2026, 10, 25));
      expect(datePrevue(DateTime.utc(2026, 12, 31), 1), DateTime.utc(2027, 1, 1));
    });
    test('formats', () {
      expect(formatDate(DateTime.utc(2026, 1, 5)), '2026-01-05');
      expect(lireDate('2026-10-12'), DateTime.utc(2026, 10, 12));
    });
  });

  group('Extraits', () {
    test('masquer', () => expect(masquerMot('I lowkey miss you', 2, 8), 'I ______ miss you'));
    test('points de code et UTF-16', () {
      const texte = '😀 lowkey';
      expect(bornesSurbrillance(texte, 2, 8), (3, 9));
      expect(masquerMot(texte, 2, 8), '😀 ______');
    });
  });

  group('Divers', () {
    test('versions', () {
      expect(comparerVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(comparerVersions('1.2.0', '1.10.0'), lessThan(0));
      expect(comparerVersions('2.0.0+3', '2.0.0'), 0);
    });
    test('attente progressive plafonnée à 60 s ± 20 %', () {
      for (var i = 0; i < 12; i++) {
        final ms = attenteProgressive(i).inMilliseconds;
        final base = [1, 2, 4, 8, 16, 32, 60][i.clamp(0, 6)] * 1000;
        expect(ms, inInclusiveRange(base * 0.8, base * 1.2));
      }
    });
    test('initiales', () {
      expect(const Artiste(nom: 'Taylor Swift').initiales, 'TS');
      expect(const Artiste(nom: 'Adele').initiales, 'A');
    });
  });

  group('Rappels (40.4)', () {
    Revision revision(String jour) => Revision(id: jour, motId: 'm$jour', datePrevue: lireDate(jour));
    test('une notification seulement si un mot est dû', () {
      final rappels = planifierRappels(
        maintenantLocal: DateTime(2026, 10, 12, 10),
        reglages: const Reglages(),
        planifiees: [revision('2026-10-14')],
        indice: (_) => 'I ______ miss you',
      );
      expect(rappels.first.quand, DateTime(2026, 10, 14, 19));
      expect(rappels.first.nombre, 1);
      expect(rappels.first.corps, contains('______'));
      expect(rappels.length, 12);
    });
    test('désactivé et tous les 2 jours', () {
      final dues = [revision('2026-10-12')];
      expect(
        planifierRappels(
          maintenantLocal: DateTime(2026, 10, 12, 10),
          reglages: const Reglages(frequenceRappels: 'desactive'),
          planifiees: dues,
          indice: (_) => null,
        ),
        isEmpty,
      );
      final rappels = planifierRappels(
        maintenantLocal: DateTime(2026, 10, 12, 10),
        reglages: const Reglages(frequenceRappels: 'tous_les_2_jours', heureRappel: '08:15'),
        planifiees: dues,
        indice: (_) => null,
      );
      expect(rappels.map((r) => r.quand.day).take(3), [14, 16, 18]);
      expect(rappels.first.quand.hour, 8);
    });
    test('aujourd\'hui exclu quand l\'application est ouverte (NOT-08)', () {
      final rappels = planifierRappels(
        maintenantLocal: DateTime(2026, 10, 12, 10),
        reglages: const Reglages(),
        planifiees: [revision('2026-10-12')],
        indice: (_) => null,
        inclureAujourdhui: false,
      );
      expect(rappels.first.quand.day, 13);
    });
  });
}
