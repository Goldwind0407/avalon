import '../../game/discussion_model.dart';
import '../../game/game_model.dart';
import 'bot_contract.dart';

/// Constructed exclusively from public values. Pending ballots and private
/// reveals have no constructor argument, so they cannot become evidence here.
class BotPublicLedger {
  BotPublicLedger(
      {required this.generation,
      required int count,
      required List<ProposalRecord> proposals,
      required List<QuestResult> history,
      required List<LadyCheck> ladyChecks,
      required List<bool?> loyalty,
      required int activeQuest,
      required List<DiscussionStatement> statements,
      required BotProposalId currentProposal,
      required List<int> currentTeam,
      required int leader}) {
    void add(BotPublicEvidence event) {
      if (event.id.generation != generation ||
          _events.containsKey(event.id.id)) {
        throw ArgumentError('Duplicate or foreign public evidence');
      }
      _events[event.id.id] = event;
    }

    for (final p in proposals) {
      if (p.votes.length != count) {
        throw ArgumentError('Ballots are not public until complete');
      }
      final key = 'q${p.quest}/a${p.attempt}';
      add(BotPublicEvidence(
          id: BotEvidenceId(generation, BotEvidenceKind.proposal, key),
          quest: p.quest,
          attempt: p.attempt,
          actor: p.leader,
          team: p.team));
      add(BotPublicEvidence(
          id: BotEvidenceId(generation, BotEvidenceKind.ballot, key),
          quest: p.quest,
          attempt: p.attempt,
          actor: p.leader,
          team: p.team,
          ballots: p.votes));
    }
    if (currentTeam.isNotEmpty &&
        !_events.containsKey(BotEvidenceId(generation, BotEvidenceKind.proposal,
                'q${currentProposal.quest}/a${currentProposal.attempt}')
            .id)) {
      add(BotPublicEvidence(
          id: BotEvidenceId(generation, BotEvidenceKind.proposal,
              'q${currentProposal.quest}/a${currentProposal.attempt}'),
          quest: currentProposal.quest,
          attempt: currentProposal.attempt,
          actor: leader,
          team: currentTeam));
    }
    for (final (index, q) in history.indexed) {
      add(BotPublicEvidence(
          id: BotEvidenceId(generation, BotEvidenceKind.quest, 'q${index + 1}'),
          quest: index + 1,
          team: q.team,
          fails: q.fails,
          succeeded: q.succeeded));
      if (q.excaliburTarget != null) {
        add(BotPublicEvidence(
            id: BotEvidenceId(
                generation, BotEvidenceKind.swordUse, 'q${index + 1}'),
            quest: index + 1,
            actor: q.excaliburHolder,
            target: q.excaliburTarget,
            team: q.team));
      }
    }
    for (final check in ladyChecks) {
      add(BotPublicEvidence(
          id: BotEvidenceId(generation, BotEvidenceKind.ladyUse,
              'q${check.quest}/${check.holder}/${check.target}'),
          quest: check.quest,
          actor: check.holder,
          target: check.target));
    }
    // Face-up FUTURE variant-2 cards are public, but are not past switch events.
    for (var q = 0; q < loyalty.length && q < activeQuest; q++) {
      if (loyalty[q] != null) {
        add(BotPublicEvidence(
            id: BotEvidenceId(generation, BotEvidenceKind.loyalty, 'q${q + 1}'),
            quest: q + 1,
            switchOccurred: loyalty[q]));
      }
    }
    for (final (index, s) in statements.indexed) {
      if (s.generation != null && s.generation != generation) {
        throw ArgumentError('Statement belongs to another game');
      }
      add(BotPublicEvidence(
          id: BotEvidenceId(generation, BotEvidenceKind.statement, 's$index'),
          quest: s.quest,
          attempt: s.attempt,
          actor: s.speaker,
          target: s.target,
          team: s.team,
          statementIndex: index));
    }
  }
  final int generation;
  final _events = <String, BotPublicEvidence>{};
  List<BotPublicEvidence> get events => List.unmodifiable(_events.values);
  BotPublicEvidence? resolve(BotEvidenceId id) =>
      id.generation == generation ? _events[id.id] : null;
  bool permitsAll(Iterable<BotEvidenceId> references) =>
      references.every((id) => resolve(id) != null);
}
