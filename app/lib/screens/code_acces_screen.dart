// Code d'invitation : demandé quand le PC est joint par le tunnel Cloudflare (amis sans
// Tailscale). Le code désigne la bibliothèque de l'ami sur le PC.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/divers.dart';
import '../providers/providers.dart';
import '../services/local_cache.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';

class CodeAccesScreen extends ConsumerStatefulWidget {
  const CodeAccesScreen({super.key});

  @override
  ConsumerState<CodeAccesScreen> createState() => _CodeAccesScreenState();
}

class _CodeAccesScreenState extends ConsumerState<CodeAccesScreen> {
  final _code = TextEditingController();
  String? _erreur;
  bool _verification = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _verification = true;
      _erreur = null;
    });
    final env = ref.read(environnementProvider);
    await env.cache?.fixerMeta(Meta.codeAcces, code);
    await ref.read(connexionProvider.notifier).synchroniser(manuel: true);
    if (!mounted) return;
    final etat = ref.read(connexionProvider).etat;
    setState(() {
      _verification = false;
      if (etat == EtatConnexion.codeAccesRequis) _erreur = S.codeAccesInvalide;
      if (etat == EtatConnexion.pcInjoignable) _erreur = S.codeAccesInjoignable;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Scaffold(
      body: SafeArea(
        child: ContenuCentre(
          child: Padding(
            padding: const EdgeInsets.all(Espaces.margeEcran),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(S.codeAccesTitre, style: Textes.titreEcran.copyWith(color: c.encre)),
                ),
                const SizedBox(height: Espaces.e12),
                Text(S.codeAccesTexte, style: Textes.corps.copyWith(color: c.texteSecondaire)),
                const SizedBox(height: Espaces.e20),
                ChampMot(
                  controleur: _code,
                  aide: S.codeAccesChamp,
                  erreur: _erreur,
                  max: 20,
                  autofocus: true,
                  onSubmitted: (_) => _valider(),
                ),
                const SizedBox(height: Espaces.e16),
                BoutonPrincipal(libelle: S.valider, onPressed: _verification ? null : _valider),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
