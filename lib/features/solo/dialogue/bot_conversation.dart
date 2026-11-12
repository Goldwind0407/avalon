import '../../game/discussion_model.dart';
import '../../game/game_model.dart';
import 'bot_contract.dart';
import 'bot_public_ledger.dart';

typedef PublicUtterance = ({int index, DiscussionStatement statement});

/// Structured public conversation only. No roles, private facts, or plans enter
/// this index; an assertion is never upgraded into a verified private result.
class BotConversation {
  BotConversation(
      {required this.ledger,
      required this.statements,
      required this.history,
      required this.quest,
      required this.attempt});
  final BotPublicLedger ledger;
  final List<DiscussionStatement> statements;
  final List<QuestResult> history;
  final int quest, attempt;

  List<PublicUtterance> get all =>
      [for (final (i, s) in statements.indexed) (index: i, statement: s)];
  List<PublicUtterance> get recent => all
      .where(
          (e) => e.statement.quest == quest && e.statement.attempt == attempt)
      .toList();
  List<PublicUtterance> get accusations => recent
      .where((e) =>
          e.statement.position == DiscussionPosition.suspect &&
          e.statement.quotedFrom == null &&
          e.statement.target != null &&
          e.statement.target != e.statement.speaker)
      .toList();
  List<PublicUtterance> get endorsements => recent
      .where((e) =>
          e.statement.position == DiscussionPosition.defend &&
          e.statement.quotedFrom == null &&
          e.statement.target != null &&
          e.statement.target != e.statement.speaker)
      .toList();

  List<BotPublicEvidence> basis(PublicUtterance e) => ledger.events
      .where((event) => e.statement.evidenceIds.contains(event.id.id))
      .toList();
  BotEvidenceId id(PublicUtterance e) => BotEvidenceId(
      ledger.generation, BotEvidenceKind.statement, 's${e.index}');
  List<BotEvidenceId> references(PublicUtterance e) =>
      [id(e), ...basis(e).map((b) => b.id)];
  PublicUtterance? latest(Iterable<PublicUtterance> values) =>
      values.isEmpty ? null : values.last;

  bool hasPublicGrounds(PublicUtterance e) => basis(e).any((b) =>
      b.id.kind == BotEvidenceKind.quest ||
      b.id.kind == BotEvidenceKind.ballot ||
      b.id.kind == BotEvidenceKind.ladyUse ||
      b.id.kind == BotEvidenceKind.swordUse);

  BotPublicEvidence? ladySource(PublicUtterance e) {
    final matches = basis(e).where((b) =>
        b.id.kind == BotEvidenceKind.ladyUse && b.target == e.statement.target);
    return matches.isEmpty ? null : matches.last;
  }

  List<BotPublicEvidence> switchesAfter(int completedQuest) => ledger.events
      .where((e) =>
          e.id.kind == BotEvidenceKind.loyalty &&
          e.switchOccurred == true &&
          e.quest > completedQuest)
      .toList();
  bool alignmentMayDifferSince(int completedQuest) =>
      switchesAfter(completedQuest).length.isOdd;

  int? contraryQuest(PublicUtterance e) {
    final s = e.statement;
    if (s.target == null || s.position != DiscussionPosition.defend) {
      return null;
    }
    for (var i = history.length - 1; i >= 0; i--) {
      if (i + 1 >= s.quest &&
          history[i].fails > 0 &&
          history[i].team.contains(s.target) &&
          !s.evidenceIds.contains('g${ledger.generation}/quest/q${i + 1}')) {
        return i + 1;
      }
    }
    return null;
  }

  (PublicUtterance, PublicUtterance)? contradictoryClaims(
      {Set<int>? speakers, bool ladyOnly = false}) {
    for (final newer in all.reversed) {
      final n = newer.statement;
      if (n.claimedEvil == null ||
          n.target == null ||
          n.switched == null ||
          n.quotedFrom != null ||
          (speakers != null && !speakers.contains(n.speaker))) {
        continue;
      }
      for (final older in all.take(newer.index).toList().reversed) {
        final s = older.statement;
        if (s.target != n.target ||
            s.claimedEvil == null ||
            s.claimedEvil == n.claimedEvil ||
            s.switched != n.switched ||
            s.quotedFrom != null ||
            (speakers != null && !speakers.contains(s.speaker))) {
          continue;
        }
        final a = ladySource(older), b = ladySource(newer);
        // Same action/time, two assertions. Never manufacture a second legal
        // Lady inspection of the same target or compare different time frames.
        if (a != null && b != null && a.id == b.id) return (older, newer);
        if (!ladyOnly && s.quest == n.quest && s.attempt == n.attempt) {
          return (older, newer);
        }
      }
    }
    return null;
  }

  int? influentialSeat(int observer) {
    final mentions = <int, Set<int>>{};
    for (final e in recent) {
      final s = e.statement;
      final target =
          s.position == DiscussionPosition.defend ? s.target : s.questionTo;
      if (target == null || target == observer || target == s.speaker) continue;
      mentions.putIfAbsent(target, () => {}).add(s.speaker);
    }
    final seats = mentions.keys.where((s) => mentions[s]!.length >= 2).toList()
      ..sort((a, b) => mentions[b]!.length.compareTo(mentions[a]!.length));
    return seats.isEmpty ? null : seats.first;
  }

  bool hasLegalCardSource(PublicUtterance e) {
    final s = e.statement, q = s.originalCardQuest;
    if (q == null || q > history.length || s.target == null) return false;
    final result = history[q - 1];
    return (s.speaker == s.target && result.team.contains(s.speaker)) ||
        (result.excaliburHolder == s.speaker &&
            result.excaliburTarget == s.target);
  }
}
