// Point d'entrée : une seule base de code pour la PWA et l'APK (PWA-01).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'environnement.dart';
import 'providers/providers.dart';
import 'services/local_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  Intl.defaultLocale = 'fr_FR';
  await Hive.initFlutter();
  final prefs = await ouvrirMagasinHive('prefs');
  final environnement = await construireEnvironnement(prefs);
  runApp(
    ProviderScope(
      overrides: [
        environnementProvider.overrideWithValue(environnement),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const Application(),
    ),
  );
}
