// Session de révision : file, carte courante, réponse en attente 5 s, exercice, récapitulatif
// (REV-11 à REV-18, 27.2, sessionRevisionProvider de 22.2).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/revision.dart';
import '../services/api_client.dart';
import '../services/depot_donnees.dart';
import '../services/sm2.dart';
import 'providers.dart';

const delaiAnnulation = Duration(seconds: 5);
const frequenceProduction = 3;

enum PhaseExercice { aucun, chargement, saisie, evaluation, verdict, indisponible }

@immutable
class EtatSession {
  const EtatSession({
    this.file = const [],
    this.index = 0,
    this.revele = false,
    this.enAttente = false,
    this.revises = 0,
    this.reussites = 0,
    this.termine = false,
    this.phase = PhaseExercice.aucun,
    this.exercice,
    this.verdict,
    this.messageIA,
  });

  final List<RevisionDue> file;
  final int index;
  final bool revele;

  /// Une réponse est en attente d'envoi (bandeau « Annuler » visible).
  final bool enAttente;
  final int revises;
  final int reussites;
  final bool termine;
  final PhaseExercice phase;
  final Exercice? exercice;
  final Verdict? verdict;
  final String? messageIA;

  bool get demarree => file.isNotEmpty;
  RevisionDue? get carte => index < file.length ? file[index] : null;

  EtatSession copyWith({
    List<RevisionDue>? file,
    int? index,
    bool? revele,
    bool? enAttente,
    int? revises,
    int? reussites,
    bool? termine,
    PhaseExercice? phase,
    Object? exercice = _absent,
    Object? verdict = _absent,
    Object? messageIA = _absent,
  }) => EtatSession(
    file: file ?? this.file,
    index: index ?? this.index,
    revele: revele ?? this.revele,
    enAttente: enAttente ?? this.enAttente,
    revises: revises ?? this.revises,
    reussites: reussites ?? this.reussites,
    termine: termine ?? this.termine,
    phase: phase ?? this.phase,
    exercice: identical(exercice, _absent) ? this.exercice : exercice as Exercice?,
    verdict: identical(verdict, _absent) ? this.verdict : verdict as Verdict?,
    messageIA: identical(messageIA, _absent) ? this.messageIA : messageIA as String?,
  );
}

const _absent = Object();

class _ReponseEnAttente {
  _ReponseEnAttente(this.carte, this.reponse, this.etatAvant);
  final RevisionDue carte;
  final ReponseCarte reponse;
  final EtatSession etatAvant;
}

class SessionNotifier extends StateNotifier<EtatSession> {
  SessionNotifier(this.ref) : super(const EtatSession());
  final Ref ref;
  Timer? _minuterie;
  _ReponseEnAttente? _attente;

  /// Session d'exercices : chaque mot traduit passe par l'exercice de production (US-06).
  bool _exercices = false;

  /// Phrases préparées à l'avance (par identifiant de révision) : la phrase de la carte
  /// suivante est générée pendant que l'utilisateur répond, pour ne pas attendre l'IA.
  final _preparees = <String, Future<Exercice>>{};

  Future<Exercice> _exercicePour(RevisionDue carte) =>
      _preparees.remove(carte.id) ?? _depot.creerExercice(carte.motId);

  void _prechargerSuivante() {
    final suivant = state.index + 1;
    if (!_exercices || suivant >= state.file.length || !_doitProduire(suivant)) return;
    preparer(state.file[suivant]);
  }

  /// Prépare la phrase d'une carte (accueil des révisions : la première carte est prête au
  /// moment de « Commencer »). Un échec est oublié pour être retenté au démarrage.
  void preparer(RevisionDue carte) {
    if (carte.traductionFr == null || _preparees.containsKey(carte.id)) return;
    final demande = _depot.creerExercice(carte.motId);
    _preparees[carte.id] = demande;
    demande.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_preparees[carte.id], demande)) _preparees.remove(carte.id);
      },
    );
  }

  DepotDonnees get _depot => ref.read(depotProvider);

  /// Démarre une session de mots_par_session mots au plus, du plus en retard au moins (REV-11).
  /// Avec [exercices], toutes les cartes dont le mot est traduit deviennent des exercices.
  Future<void> demarrer(List<RevisionDue> dues, {bool exercices = false}) async {
    _exercices = exercices;
    _preparees.removeWhere((id, _) => !dues.any((d) => d.id == id));
    state = EtatSession(file: List.of(dues));
    await _preparerCarte();
  }

  /// « Session suivante » : même mode que la session terminée.
  Future<void> continuer(List<RevisionDue> dues) => demarrer(dues, exercices: _exercices);

  bool _doitProduire(int index) {
    if (_exercices) return state.file[index].traductionFr != null;
    final reglages = ref.read(reglagesProvider).valueOrNull;
    if (reglages?.modeRevision != 'melange') return false;
    final carte = state.file[index];
    return carte.traductionFr != null && index % frequenceProduction == frequenceProduction - 1;
  }

  /// En mode mélange, environ un mot sur trois passe par l'exercice si l'IA répond (REV-12).
  Future<void> _preparerCarte() async {
    final carte = state.carte;
    if (carte == null || !_doitProduire(state.index)) return;
    state = state.copyWith(phase: PhaseExercice.chargement);
    try {
      final exercice = await _exercicePour(carte);
      if (!mounted || state.carte?.id != carte.id) return;
      state = state.copyWith(phase: PhaseExercice.saisie, exercice: exercice);
      // Après la phrase courante seulement : l'IA du PC traite mieux une demande à la fois.
      _prechargerSuivante();
    } catch (e) {
      if (!mounted) return;
      // Sans connexion au PC, inutile de retenter à chaque carte : le reste de la session
      // passe en mode rappel (mot masqué), qui fonctionne hors ligne.
      if (e is HorsLigneException || e is ReseauException) _exercices = false;
      // IA-23 : retour discret au mode rappel.
      state = state.copyWith(phase: PhaseExercice.indisponible, exercice: null);
    }
  }

  void reveler() {
    if (state.carte == null) return;
    state = state.copyWith(revele: true);
  }

  /// Réponse en mode rappel : « Je ne savais pas » (1), « Je savais » (4), « Facile » (5).
  void repondre(int qualite) {
    if (!state.revele || state.carte == null) return; // MAQ-06
    _enregistrer(ReponseCarte(qualite: qualite), qualite >= noteReussiteMin);
  }

  Future<void> evaluer(String reponse) async {
    final exercice = state.exercice;
    if (exercice == null || reponse.trim().isEmpty) return;
    state = state.copyWith(phase: PhaseExercice.evaluation);
    try {
      final verdict = await _depot.evaluerExercice(exercice.id, reponse.trim());
      if (!mounted) return;
      state = state.copyWith(phase: PhaseExercice.verdict, verdict: verdict, revele: true);
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        phase: PhaseExercice.indisponible,
        revele: false,
        messageIA: e is ErreurApi ? e.message : null,
      );
    }
  }

  /// Après le verdict : la note est déduite du verdict (F.2).
  void validerVerdict(String reponse) {
    final verdict = state.verdict;
    if (verdict == null) return;
    _enregistrer(
      ReponseCarte(verdict: verdict.verdict, reponse: reponse),
      Notes.verdicts[verdict.verdict]! >= noteReussiteMin,
    );
  }

  void _enregistrer(ReponseCarte reponse, bool reussite) {
    _envoyerAttente();
    final carte = state.carte!;
    _attente = _ReponseEnAttente(carte, reponse, state);
    final suivant = state.index + 1;
    state = EtatSession(
      file: state.file,
      index: suivant,
      enAttente: true,
      revises: state.revises + 1,
      reussites: state.reussites + (reussite ? 1 : 0),
      termine: suivant >= state.file.length,
    );
    _minuterie = Timer(delaiAnnulation, _envoyerAttente);
    unawaited(_preparerCarte());
  }

  /// « Annuler » pendant 5 s : la réponse n'a pas encore été envoyée (REV-15).
  void annuler() {
    final attente = _attente;
    if (attente == null) return;
    _minuterie?.cancel();
    _attente = null;
    state = attente.etatAvant.copyWith(enAttente: false);
  }

  void _envoyerAttente() {
    _minuterie?.cancel();
    final attente = _attente;
    _attente = null;
    if (attente == null) return;
    if (mounted) state = state.copyWith(enAttente: false);
    unawaited(
      _depot
          .repondre(attente.carte, attente.reponse)
          .then((_) {
            signalerEcriture(ref);
            final env = ref.read(environnementProvider);
            if (env.cache != null) {
              unawaited(env.notifications.reprogrammer(env.cache!, inclureAujourdhui: false));
            }
          })
          .catchError((Object _) {}),
    );
  }

  /// Retire un mot supprimé pendant la session (REV-18).
  void retirerMot(String motId) {
    final avant = state.file.take(state.index).where((c) => c.motId == motId).length;
    final file = state.file.where((c) => c.motId != motId).toList();
    state = state.copyWith(
      file: file,
      index: state.index - avant,
      termine: state.index - avant >= file.length,
    );
  }

  /// Termine la session : la réponse en attente est envoyée.
  void terminer() {
    _envoyerAttente();
    state = const EtatSession();
    ref.invalidate(revisionsDuesProvider);
  }

  @override
  void dispose() {
    _envoyerAttente();
    super.dispose();
  }
}

final sessionRevisionProvider = StateNotifierProvider<SessionNotifier, EtatSession>(
  (ref) => SessionNotifier(ref),
);
