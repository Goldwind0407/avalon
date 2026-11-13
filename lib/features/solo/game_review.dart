import '../game/discussion_model.dart';
import '../game/expansion_model.dart';
import '../game/game_model.dart';
import 'bot_brain.dart';
import 'bot_vote_plan.dart';

/// Why a bot voted the way it did, in words.
const voteReasonLabels = {
  'fifthProposal': '第五次提案，避免直接落敗',
  'concealAlly': '暫時與可疑隊友切割',
  'sabotageOpportunity': '隊伍有機會破壞任務',
  'evilBlend': '邪惡方評估偽裝與阻擋收益',
  'noviceSlip': '新手判斷失誤',
  'merlinDisguise': '梅林刻意偽裝',
  'acceptableRisk': '隊伍風險在可接受範圍',
  'unsafeTeam': '嫌疑或隊伍風險超過接受範圍',
};

class ReviewLine {
  const ReviewLine(this.statement, this.source);
  final DiscussionStatement statement;

  /// Where a bot's line came from; null for the player's own lines.
  final SpeechSource? source;
}

class ReviewProposal {
  const ReviewProposal(this.record, this.lines, this.decisions);
  final ProposalRecord record;
  final List<ReviewLine> lines;

  /// Each bot's final vote decision (private reasoning, shown after the game).
  final Map<int, BotVoteDecision> decisions;
}

class ReviewQuest {
  const ReviewQuest(this.number, this.proposals, this.result, this.cards);
  final int number;
  final List<ReviewProposal> proposals;
  final QuestResult? result;

  /// The card each member played, before any sword flip.
  final Map<int, bool> cards;
}

/// A line about the player's own play.
class ReviewScore {
  const ReviewScore(this.title, this.value, this.detail);
  final String title, value, detail;
}

/// Everything about a finished solo game, roles included.
class GameReview {
  GameReview({
    required this.players,
    required this.roles,
    required this.styles,
    required this.mySeat,
    required this.winner,
    required this.result,
    required this.quests,
    required this.endLines,
    required this.ladyChecks,
    required this.assassinTarget,
    required this.expansions,
  });

  final List<String> players;
  final List<Role> roles;
  final List<String?> styles;
  final int mySeat;
  final String? winner, result;
  final List<ReviewQuest> quests;

  /// Said after the last quest (the Assassin's declaration).
  final List<ReviewLine> endLines;
  final List<LadyCheck> ladyChecks;
  final int? assassinTarget;
  final ExpansionSettings expansions;

  /// Builds the review from what a solo session recorded.
  factory GameReview.build({
    required List<String> players,
    required List<Role> roles,
    required List<String?> styles,
    required int mySeat,
    required String? winner,
    required String? result,
    required List<ProposalRecord> proposals,
    required List<QuestResult> history,
    required List<DiscussionStatement> statements,
    required Map<int, SpeechSource> sources,
    required Map<int, Map<int, BotVoteDecision>> decisions,
    required Map<int, Map<int, bool>> cardsBySeat,
    required List<LadyCheck> ladyChecks,
    required int? assassinTarget,
    required ExpansionSettings expansions,
  }) {
    ReviewLine line(int i) => ReviewLine(statements[i], sources[i]);
    final quests = <ReviewQuest>[];
    final lastQuest = proposals.isEmpty ? 0 : proposals.last.quest;
    for (var q = 1; q <= lastQuest; q++) {
      final rounds = <ReviewProposal>[];
      for (final (index, p) in proposals.indexed) {
        if (p.quest != q) continue;
        rounds.add(ReviewProposal(
            p,
            [
              for (var i = 0; i < statements.length; i++)
                if (statements[i].quest == q &&
                    statements[i].attempt == p.attempt)
                  line(i)
            ],
            decisions[index] ?? const {}));
      }
      final done = q <= history.length ? history[q - 1] : null;
      quests.add(ReviewQuest(q, rounds, done, {
        if (done != null)
          for (final s in done.team)
            if (cardsBySeat[s]?[q] case final bool card) s: card
      }));
    }
    return GameReview(
        players: players,
        roles: roles,
        styles: styles,
        mySeat: mySeat,
        winner: winner,
        result: result,
        quests: quests,
        endLines: [
          for (var i = 0; i < statements.length; i++)
            if (statements[i].attempt == null) line(i)
        ],
        ladyChecks: ladyChecks,
        assassinTarget: assassinTarget,
        expansions: expansions);
  }

  bool evil(int seat) => roles[seat].isEvil;
  bool get iAmEvil => evil(mySeat);
  bool get iWon => winner != null && (winner == '邪惡') == iAmEvil;

  /// Something about a bot's vote worth a second look, or null.
  String? oddVote(int seat, ProposalRecord p, BotVoteDecision d) {
    if (evil(seat)) return null;
    if (const ['fifthProposal', 'merlinDisguise', 'noviceSlip']
        .contains(d.reason)) {
      return null;
    }
    final doubted = [
      for (final s in p.team)
        if (s != seat && evil(s) && d.suspicion[s] >= .5) s
    ];
    if (d.approve && doubted.isNotEmpty) {
      return '放行了自己懷疑的人（${doubted.map((s) => '${s + 1}號').join('、')}）';
    }
    return null;
  }

  /// How the player did, from their own side's point of view.
  List<ReviewScore> get scores {
    final me = mySeat, mine = iAmEvil;
    var votes = 0, helpful = 0;
    var led = 0, ledClean = 0;
    for (final q in quests) {
      for (final round in q.proposals) {
        final p = round.record;
        final dirty = p.team.any(evil);
        if (p.attempt < 5) {
          votes++;
          if (p.votes[me] == (mine ? dirty : !dirty)) helpful++;
        }
        if (p.leader == me) {
          led++;
          if (mine ? dirty : !dirty) ledClean++;
        }
      }
    }
    var calls = 0, rightCalls = 0;
    for (final q in quests) {
      for (final round in q.proposals) {
        for (final l in round.lines) {
          final s = l.statement;
          if (s.speaker != me || s.target == null || s.position == null) {
            continue;
          }
          calls++;
          final isEvil = evil(s.target!);
          if ((s.position == DiscussionPosition.suspect) == isEvil) {
            rightCalls++;
          }
        }
      }
    }
    final lastDecisions = quests.reversed
        .expand((q) => q.proposals.reversed)
        .map((r) => r.decisions)
        .firstWhere((d) => d.isNotEmpty, orElse: () => const {});
    final goodViews = [
      for (final e in lastDecisions.entries)
        if (!evil(e.key)) e.value.suspicion[me]
    ];
    String pct(int a, int b) => b == 0 ? '—' : '${(100 * a / b).round()}%';
    return [
      ReviewScore(
          '投票',
          pct(helpful, votes),
          mine
              ? '$votes 次投票中，$helpful 次對邪惡有利（贊成有壞人的隊、反對乾淨的隊）。'
              : '$votes 次投票中，$helpful 次判斷正確（贊成乾淨的隊、反對有壞人的隊）。第五次提案不計。'),
      ReviewScore(
          '當隊長',
          led == 0 ? '—' : '$ledClean／$led',
          led == 0
              ? '這局你沒有當過隊長。'
              : mine
                  ? '你帶的 $led 支隊伍中，$ledClean 支有壞人上隊。'
                  : '你帶的 $led 支隊伍中，$ledClean 支完全沒有壞人。'),
      ReviewScore(
          '點名',
          pct(rightCalls, calls),
          calls == 0
              ? '這局你沒有用「懷疑／相信」點名任何人。'
              : '你點名 $calls 次，$rightCalls 次說中（懷疑的是壞人、相信的是好人）。'),
      if (goodViews.isNotEmpty)
        ReviewScore(
            '電腦怎麼看你',
            '${(100 * goodViews.reduce((a, b) => a + b) / goodViews.length).round()}%',
            mine
                ? '最後一次投票時，好人電腦對你的平均懷疑程度。越低代表你藏得越好。'
                : '最後一次投票時，好人電腦對你的平均懷疑程度。越低代表大家越信任你。'),
      if (roles[me] == Role.merlin && assassinTarget != null)
        ReviewScore('梅林', assassinTarget == me ? '被刺殺' : '安全',
            assassinTarget == me ? '刺客找到了你。下次可以藏得更深一點。' : '刺客沒有認出你。'),
    ];
  }
}
