// Exercice d'utilisation d'un mot (US-06) : phrase française à traduire en anglais, verdict de
// l'IA. Ouvert depuis la fiche ; c'est un entraînement libre, sans effet sur les révisions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/revision.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../strings.dart';
import '../theme/jetons.dart';
import '../widgets/composants.dart';
import '../widgets/icones.dart';

class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({super.key, required this.motId, required this.terme});
  final String motId;
  final String terme;

  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen> {
  final _reponse = TextEditingController();
  Exercice? _exercice;
  Verdict? _verdict;
  String? _erreur;
  bool _chargement = true;
  bool _evaluation = false;

  @override
  void initState() {
    super.initState();
    _nouvellePhrase(premiere: true);
  }

  @override
  void dispose() {
    _reponse.dispose();
    super.dispose();
  }

  String _message(Object e) => switch (e) {
    HorsLigneException() || ReseauException() => S.horsLigneFonction,
    ServeurIndisponibleException() => S.exerciceIndisponible,
    ErreurApi(:final message) when message.isNotEmpty => message,
    _ => S.exerciceIndisponible,
  };

  Future<void> _nouvellePhrase({bool premiere = false}) async {
    setState(() {
      _chargement = true;
      _erreur = null;
      _verdict = null;
      _reponse.clear();
    });
    try {
      // La première phrase peut être celle préparée à l'avance ; les suivantes sont nouvelles.
      final exercice = await ref.read(depotProvider).creerExercice(widget.motId, nouvelle: !premiere);
      if (mounted) setState(() => _exercice = exercice);
    } catch (e) {
      if (mounted) setState(() => _erreur = _message(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _valider() async {
    final exercice = _exercice;
    if (exercice == null || _reponse.text.trim().isEmpty) return;
    setState(() => _evaluation = true);
    try {
      final verdict = await ref.read(depotProvider).evaluerExercice(exercice.id, _reponse.text.trim());
      if (mounted) setState(() => _verdict = verdict);
    } catch (e) {
      if (mounted) setState(() => _erreur = _message(e));
    } finally {
      if (mounted) setState(() => _evaluation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final pc = context.estPc;
    final carte = Container(
      padding: const EdgeInsets.all(Espaces.e24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Rayons.carteLarge),
        boxShadow: Ombres.carteRevision(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.traduisEnAnglais, style: Textes.etiquetteMajuscules.copyWith(color: c.violet)),
          const SizedBox(height: Espaces.e12),
          if (_chargement) ...[
            const Squelette(hauteur: Espaces.e32, rayon: Rayons.surlignage),
            const SizedBox(height: Espaces.e12),
            const Squelette(hauteur: Tailles.boutonMin, rayon: Rayons.bouton),
          ] else if (_erreur != null && _exercice == null) ...[
            Text(_erreur!, style: Textes.corps.copyWith(color: c.texteSecondaire)),
            const SizedBox(height: Espaces.e16),
            BoutonPrincipal(libelle: S.reessayer, onPressed: _nouvellePhrase),
          ] else ...[
            Text(_exercice?.phraseFr ?? '', style: Textes.titreExtrait.copyWith(color: c.encre)),
            const SizedBox(height: Espaces.e16),
            if (_verdict == null) ...[
              ChampMot(
                controleur: _reponse,
                aide: S.taReponse,
                multiligne: true,
                max: 300,
                autofocus: true,
                erreur: _erreur,
              ),
              const SizedBox(height: Espaces.e16),
              BoutonPrincipal(libelle: S.valider, onPressed: _evaluation ? null : _valider),
              const SizedBox(height: Espaces.e10),
              if (!_evaluation)
                BoutonDictee(
                  controleur: _reponse,
                  service: ref.read(environnementProvider).dictee,
                  surReponse: (_) => _valider(),
                  motAttendu: widget.terme,
                ),
            ] else ...[
              BlocVerdict(verdict: _verdict!),
              const SizedBox(height: Espaces.e12),
              Text(S.taReponseLabel, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
              Text(_reponse.text, style: Textes.corps.copyWith(color: c.encre)),
              if (_verdict!.referenceEn != null) ...[
                const SizedBox(height: Espaces.e12),
                Text(S.attendu, style: Textes.libelleCarte.copyWith(color: c.texteSecondaire)),
                Text(_verdict!.referenceEn!, style: Textes.corps.copyWith(color: c.encre)),
              ],
              const SizedBox(height: Espaces.e16),
              BoutonPrincipal(libelle: S.nouvellePhrase, onPressed: _nouvellePhrase, autofocus: true),
            ],
          ],
        ],
      ),
    );

    return Scaffold(
      body: SingleChildScrollView(
        child: ContenuCentre(
          child: Padding(
            padding: pc ? const EdgeInsets.all(Espaces.margePc) : EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EnTeteColore(
                  fond: c.violet,
                  hauteur: Tailles.enTeteFiche,
                  actions: BoutonIcone(
                    forme: Icones.retour,
                    libelle: S.fermer,
                    couleur: c.surViolet,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.exerciceTitre, style: Textes.date.copyWith(color: c.surViolet)),
                      Padding(
                        padding: const EdgeInsets.only(top: Espaces.e10, bottom: Espaces.e8),
                        child: Row(
                          children: [
                            Flexible(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  widget.terme,
                                  style: Textes.titreEcran.copyWith(color: c.surViolet),
                                ),
                              ),
                            ),
                            const SizedBox(width: Espaces.e8),
                            BoutonPrononciation(
                              mot: widget.terme,
                              service: ref.read(environnementProvider).prononciation,
                              couleur: c.surViolet,
                            ),
                          ],
                        ),
                      ),
                      Opacity(
                        opacity: Opacites.sousTitreEnTete,
                        child: Text(S.exerciceSousTitre, style: Textes.corps.copyWith(color: c.surViolet)),
                      ),
                      if (!pc) const SizedBox(height: Tailles.chevauchementFiche + Espaces.e20),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, pc ? Espaces.e20 : -Tailles.chevauchementFiche),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pc ? 0 : Espaces.margeEcran),
                    child: carte,
                  ),
                ),
                const SizedBox(height: Espaces.e32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
