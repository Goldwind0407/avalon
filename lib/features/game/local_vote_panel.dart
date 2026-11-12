import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/game_sounds.dart';
import '../../core/theme.dart';
import 'game_model.dart';

/// Shared-phone players publicly record all ballots in one operation.
class LocalVotePanel extends StatefulWidget {
  const LocalVotePanel(
      {super.key,
      required this.players,
      required this.leader,
      required this.team,
      required this.onSubmit});
  final List<String> players;
  final int leader;
  final List<int> team;
  final Future<void> Function(List<bool>) onSubmit;
  @override
  State<LocalVotePanel> createState() => _LocalVotePanelState();
}

class _LocalVotePanelState extends State<LocalVotePanel> {
  late final votes = List<bool?>.filled(widget.players.length, null);
  bool busy = false;
  String? error;
  Future<void> submit() async {
    if (busy || votes.any((v) => v == null)) return;
    setState(() {
      busy = true;
      error = null;
    });
    GameSounds.instance.play(GameSound.seal);
    try {
      await widget.onSubmit(votes.cast<bool>().toList());
    } catch (_) {
      if (mounted) setState(() => error = '投票未送出，請重試');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final scale = min(c.maxHeight / 330, c.maxWidth / 780).clamp(.65, 1.3);
        final rows = (votes.length / 2).ceil();
        final completed = votes.where((v) => v != null).length;
        return Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Container(
                    padding: EdgeInsets.all(14 * scale),
                    decoration: BoxDecoration(
                        color: AvalonTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AvalonTheme.gold)),
                    child: Column(children: [
                      Text('公開投票登記',
                          style: TextStyle(
                              fontSize: 23 * scale,
                              fontWeight: FontWeight.bold,
                              color: AvalonTheme.gold)),
                      const SizedBox(height: 4),
                      Text(
                          '隊長 ${playerLabel(widget.leader, widget.players[widget.leader])}　隊伍：${widget.team.map((i) => '${i + 1} 號').join('、')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13 * scale)),
                      SizedBox(height: 8 * scale),
                      Expanded(
                          child: Column(children: [
                        for (var row = 0; row < rows; row++)
                          Expanded(
                              child: Padding(
                                  padding: EdgeInsets.only(bottom: 5 * scale),
                                  child: Row(children: [
                                    for (var col = 0; col < 2; col++) ...[
                                      if (col > 0) SizedBox(width: 10 * scale),
                                      Expanded(
                                          child: row * 2 + col < votes.length
                                              ? _player(row * 2 + col, scale)
                                              : const SizedBox()),
                                    ]
                                  ])))
                      ])),
                      if (error != null)
                        Text(error!,
                            style: const TextStyle(color: Colors.redAccent)),
                      Row(children: [
                        TextButton(
                            key: const ValueKey('allApprove'),
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      votes.fillRange(0, votes.length, true);
                                    }),
                            child: const Text('全員贊成')),
                        TextButton(
                            key: const ValueKey('allReject'),
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                      votes.fillRange(0, votes.length, false);
                                    }),
                            child: const Text('全員反對')),
                        const Spacer(),
                        Text('$completed/${votes.length}',
                            style: TextStyle(fontSize: 13 * scale)),
                        SizedBox(width: 10 * scale),
                        ElevatedButton(
                            key: const ValueKey('submitLocalVotes'),
                            style: ElevatedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 18 * scale,
                                    vertical: 12 * scale)),
                            onPressed: !busy && completed == votes.length
                                ? submit
                                : null,
                            child: Text(busy ? '登記中…' : '確認票型',
                                style: TextStyle(fontSize: 15 * scale))),
                      ]),
                    ]))));
      });
  Widget _player(int seat, double scale) => Container(
      key: ValueKey('localBallot$seat'),
      padding: EdgeInsets.symmetric(horizontal: 8 * scale),
      decoration: BoxDecoration(
          color: AvalonTheme.raised, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(
            child: Tooltip(
                message: playerLabel(seat, widget.players[seat]),
                child: Text(playerLabel(seat, widget.players[seat]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14 * scale)))),
        for (final yes in [true, false])
          Padding(
              padding: EdgeInsets.only(left: 4 * scale),
              child: Semantics(
                  selected: votes[seat] == yes,
                  button: true,
                  child: TextButton(
                      key: ValueKey('localVote$seat/$yes'),
                      onPressed: busy
                          ? null
                          : () {
                              GameSounds.instance.play(GameSound.tap);
                              setState(() => votes[seat] = yes);
                            },
                      style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: EdgeInsets.symmetric(
                              horizontal: 10 * scale, vertical: 6 * scale),
                          backgroundColor: votes[seat] == yes
                              ? (yes ? AvalonTheme.green : Colors.redAccent)
                                  .withValues(alpha: .3)
                              : null),
                      child: Text(yes ? '贊成' : '反對',
                          style: TextStyle(
                              fontSize: 13 * scale,
                              color: votes[seat] == yes
                                  ? Colors.white
                                  : AvalonTheme.muted))))),
      ]));
}
