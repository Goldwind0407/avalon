import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/discussion_model.dart' show ProposalRecord;
import '../game/game_model.dart';
import 'bot_brain.dart';
import 'bot_vote_plan.dart';
import 'game_review.dart';

const _goodColor = Color(0xFF8FD0FF);
const _evilColor = Color(0xFFFF8A7E);
const _body = TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFFE8E2D2));
const _muted = TextStyle(fontSize: 11.5, color: AvalonTheme.muted);

/// Looking back at a finished solo game: how the player did, every vote with
/// its reasons, every line with where it came from, every card played.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.review});
  final GameReview review;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  /// 0: the player's own play; 1..n: quests; n+1: the end of the game.
  int page = 0;
  final _scroll = ScrollController();

  GameReview get r => widget.review;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _show(int p) {
    setState(() => page = p);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _seat(int s) =>
      '${s + 1}號 ${r.players[s]}（${r.roles[s].label}${r.styles[s] == null ? '' : '・${r.styles[s]}'}）';
  Color _side(int s) => r.evil(s) ? _evilColor : _goodColor;

  Widget _who(int s, {double size = 13.5, FontWeight? weight}) => Text(_seat(s),
      style: TextStyle(fontSize: size, color: _side(s), fontWeight: weight));

  List<(String, int)> get _pages => [
        ('你的表現', 0),
        for (final q in r.quests) ('第${q.number}次遠征', q.number),
        if (r.endLines.isNotEmpty || r.assassinTarget != null)
          ('結局', r.quests.length + 1),
      ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FantasyBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              IconButton(
                                  tooltip: '返回',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.arrow_back),
                                  color: AvalonTheme.gold,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 36, height: 36),
                                  padding: EdgeInsets.zero),
                              const SizedBox(width: 4),
                              const Text('複盤',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AvalonTheme.gold)),
                            ]),
                            const SizedBox(height: 6),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(children: [
                                  for (final (title, p) in _pages)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Material(
                                        color: p == page
                                            ? AvalonTheme.violet
                                                .withValues(alpha: .35)
                                            : AvalonTheme.raised
                                                .withValues(alpha: .7),
                                        borderRadius: BorderRadius.circular(9),
                                        child: InkWell(
                                          key: ValueKey('reviewPage$p'),
                                          borderRadius:
                                              BorderRadius.circular(9),
                                          onTap: () => _show(p),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 9),
                                            child: Text(title,
                                                style: TextStyle(
                                                    fontSize: 13.5,
                                                    color: p == page
                                                        ? AvalonTheme.gold
                                                        : Colors.white)),
                                          ),
                                        ),
                                      ),
                                    ),
                                ]),
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GoldPanel(
                        padding: EdgeInsets.zero,
                        child: Scrollbar(
                          controller: _scroll,
                          child: SingleChildScrollView(
                            key: ValueKey(page),
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: page == 0
                                    ? _summary()
                                    : page > r.quests.length
                                        ? _ending()
                                        : _quest(r.quests[page - 1])),
                          ),
                        ),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      );

  Widget _heading(String text, {Color color = AvalonTheme.gold}) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: color)),
      );

  List<Widget> _summary() => [
        _heading(r.iWon ? '你贏了' : '你輸了',
            color: r.iWon ? _goodColor : _evilColor),
        Text('${r.winner}陣營獲勝・${r.result ?? ''}', style: _body),
        const SizedBox(height: 4),
        Row(children: [
          const Text('你是 ', style: _body),
          _who(r.mySeat, weight: FontWeight.bold),
        ]),
        const SizedBox(height: 10),
        for (final score in r.scores)
          Container(
            key: ValueKey('score${score.title}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AvalonTheme.raised.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(
                width: 92,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(score.title, style: _muted),
                      Text(score.value,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AvalonTheme.gold)),
                    ]),
              ),
              Expanded(child: Text(score.detail, style: _body)),
            ]),
          ),
        _heading('全員身分'),
        Wrap(spacing: 10, runSpacing: 4, children: [
          for (var s = 0; s < r.players.length; s++) _who(s),
        ]),
        const SizedBox(height: 8),
        const Text('左邊選一次遠征，可以看每次提案的投票、電腦投票的原因、每句發言的出處，以及每個人實際出的牌。',
            style: _muted),
      ];

  List<Widget> _quest(ReviewQuest q) => [
        _heading('第${q.number}次遠征'),
        for (final round in q.proposals) ..._proposal(round),
        if (q.result case final result?) ...[
          _heading(result.succeeded ? '任務成功' : '任務失敗',
              color: result.succeeded ? _goodColor : _evilColor),
          Text(
              '收到 ${result.team.length - result.fails} 張成功、${result.fails} 張失敗',
              style: _body),
          const SizedBox(height: 4),
          for (final s in result.team)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                Expanded(child: _who(s)),
                Text(
                    switch (q.cards[s]) {
                      true => '出成功',
                      false => '出失敗',
                      null => '—',
                    },
                    style: TextStyle(
                        fontSize: 13.5,
                        color: q.cards[s] == false ? _evilColor : _goodColor)),
                if (result.excaliburTarget == s)
                  const Text('（被王者之劍翻轉）', style: _muted),
              ]),
            ),
          if (result.excaliburHolder != null)
            Text(
                result.excaliburTarget == null
                    ? '王者之劍：${_seat(result.excaliburHolder!)} 沒有使用'
                    : '王者之劍：${_seat(result.excaliburHolder!)} 翻轉了 ${_seat(result.excaliburTarget!)}',
                style: _muted),
        ],
        for (final check in r.ladyChecks.where((c) => c.quest == q.number))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '湖中女神：${_seat(check.holder)} 查驗 ${_seat(check.target)}，'
                '實際是${r.evil(check.target) ? '邪惡' : '正義'}',
                style: _muted),
          ),
      ];

  List<Widget> _proposal(ReviewProposal round) {
    final p = round.record;
    final yes = p.votes.where((v) => v).length;
    return [
      Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: AvalonTheme.raised.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '提案 ${p.attempt}・${p.approved ? '通過' : '否決'}（贊成 $yes：反對 ${p.votes.length - yes}）',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: p.approved ? AvalonTheme.gold : AvalonTheme.muted)),
          Row(children: [
            const Text('隊長 ', style: _muted),
            Flexible(child: _who(p.leader, size: 12.5)),
          ]),
          Wrap(spacing: 8, children: [
            const Text('隊伍', style: _muted),
            for (final s in p.team) _who(s, size: 12.5),
          ]),
        ]),
      ),
      if (round.lines.isNotEmpty) ...[
        const Text('討論', style: _muted),
        for (final l in round.lines) _line(l),
      ],
      const SizedBox(height: 4),
      const Text('投票', style: _muted),
      for (var s = 0; s < p.votes.length; s++) _vote(s, p, round.decisions[s]),
      const SizedBox(height: 6),
    ];
  }

  Widget _line(ReviewLine l) {
    final s = l.statement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '${s.speaker + 1}號 ${r.roles[s.speaker].label}：',
            style: TextStyle(color: _side(s.speaker), fontSize: 13.5)),
        TextSpan(text: s.text, style: _body),
        if (l.source case final SpeechSource source)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: '修改位置：${source.where}',
                triggerMode: TooltipTriggerMode.tap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: AvalonTheme.muted.withValues(alpha: .5)),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(source.label,
                      style: const TextStyle(
                          fontSize: 10.5, color: AvalonTheme.muted)),
                ),
              ),
            ),
          ),
      ])),
    );
  }

  Widget _vote(int s, ProposalRecord p, BotVoteDecision? decision) {
    final approve = p.votes[s];
    final odd = decision == null ? null : r.oddVote(s, p, decision);
    final reason = decision == null
        ? (s == r.mySeat ? '你' : '')
        : (voteReasonLabels[decision.reason] ?? decision.reason);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 34,
            child: Text(approve ? '贊成' : '反對',
                style: TextStyle(
                    fontSize: 13, color: approve ? _goodColor : _evilColor))),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _who(s, size: 13),
            if (reason.isNotEmpty)
              Text(
                  decision == null
                      ? reason
                      : '$reason・隊伍風險 ${(100 * decision.risk).round()}%',
                  style: _muted),
            if (odd != null)
              Text('⚠ $odd',
                  key: ValueKey('oddVote$s'),
                  style: const TextStyle(
                      fontSize: 12, color: Colors.orangeAccent)),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _ending() => [
        _heading('結局'),
        for (final l in r.endLines) _line(l),
        if (r.assassinTarget case final t?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '刺客刺殺 ${_seat(t)}：${r.roles[t] == Role.merlin ? '找到梅林，邪惡逆轉' : '沒找到梅林'}',
                style: _body),
          ),
        const SizedBox(height: 8),
        Text('${r.winner}陣營獲勝・${r.result ?? ''}', style: _body),
      ];
}
