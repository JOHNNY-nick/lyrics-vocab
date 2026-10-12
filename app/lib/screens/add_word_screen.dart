// Écran « Ajouter un mot » (US-02, 27.3, 43.9).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/depot_local.dart';
import '../services/normalisation.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';
import 'shell.dart';

class AddWordScreen extends ConsumerStatefulWidget {
  const AddWordScreen({super.key});

  @override
  ConsumerState<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends ConsumerState<AddWordScreen> {
  // UI-13 : la saisie est conservée tant que l'écran existe (onglet gardé en mémoire).
  final _controleur = TextEditingController();
  String? _erreur;
  String? _dejaPresentId;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _controleur.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  Future<void> _ajouter() async {
    if (_envoi) return; // CL-06 : bouton désactivé pendant l'envoi
    final validation = validerTerme(
      _controleur.text,
      messageVide: S.termeVide,
      messageTropLong: S.termeTropLong,
    );
    if (!validation.valide) {
      setState(() {
        _erreur = validation.erreur;
        _dejaPresentId = null;
      });
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
      _dejaPresentId = null;
    });
    try {
      final resultat = await ref.read(depotProvider).creerMot(_controleur.text);
      signalerEcritureWidget(ref);
      if (!mounted) return;
      if (resultat.dejaPresent) {
        setState(() {
          _erreur = S.motDejaPresent;
          _dejaPresentId = resultat.mot.id;
        });
      } else {
        _controleur.clear();
        ouvrirFiche(ref, resultat.mot.id);
      }
    } on TermeInvalideException catch (e) {
      setState(() => _erreur = e.message);
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.code == 'terme_invalide' ? S.termeTropLong : e.message);
    } on Exception {
      setState(() => _erreur = S.serveurMuet);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final derniers = ref.watch(derniersMotsProvider);
    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Espaces.margeEcran,
          context.estPc ? Espaces.e32 : margeHauteEcran(context),
          Espaces.margeEcran,
          Espaces.e24,
        ),
        child: ContenuCentre(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(S.ajouterUnMot, style: Textes.titreEcran.copyWith(color: c.encre)),
              ),
              const SizedBox(height: Espaces.e16),
              ChampMot(
                controleur: _controleur,
                aide: S.aideChampMot,
                autofocus: true,
                erreur: _erreur,
                onSubmitted: (_) => _ajouter(), // MAQ-08 : Entrée valide
              ),
              if (_dejaPresentId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonLien(
                    libelle: S.voirLaFiche,
                    onPressed: () => ouvrirFiche(ref, _dejaPresentId!),
                  ),
                ),
              const SizedBox(height: Espaces.e16),
              BoutonPrincipal(
                libelle: S.ajouter,
                onPressed: _controleur.text.trim().isEmpty || _envoi ? null : _ajouter,
              ),
              const SizedBox(height: Espaces.e24),
              ...derniers.maybeWhen(
                data: (mots) => mots.isEmpty
                    ? <Widget>[]
                    : [
                        Text(S.derniersMots, style: Textes.etiquette.copyWith(color: c.texteSecondaire)),
                        const SizedBox(height: Espaces.e12),
                        for (final mot in mots) ...[
                          CarteMot(
                            terme: mot.terme,
                            traduction: mot.traductionFr,
                            niveau: mot.niveau,
                            enAttente: !mot.enrichissementTermine,
                            onTap: () => ouvrirFiche(ref, mot.id),
                          ),
                          const SizedBox(height: Espaces.e12),
                        ],
                      ],
                orElse: () => <Widget>[],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
