import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/game_sounds.dart';
import '../../core/theme.dart';
import 'discussion_model.dart';
import 'game_model.dart';
import 'game_session.dart';

Future<DiscussionSettings?> editDiscussion(
        BuildContext context, DiscussionSettings initial) =>
    showDialog<DiscussionSettings>(
        context: context, builder: (_) => _DiscussionSettingsDialog(initial));

class _DiscussionSettingsDialog extends StatefulWidget {
  const _DiscussionSettingsDialog(this.initial);
  final DiscussionSettings initial;
  @override
  State<_DiscussionSettingsDialog> createState() =>
      _DiscussionSettingsDialogState();
}

class _DiscussionSettingsDialogState extends State<_DiscussionSettingsDialog> {
  late bool enabled = widget.initial.enabled;
  late bool selectionFree = widget.initial.selectionFree;
  late bool free = widget.initial.freeSeconds > 0;
  late double seconds = widget.initial.speechSeconds.toDouble();
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('發言設定'),
          content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('依序發言'),
                    subtitle: const Text('隊長下一家開始，隊長最後總結'),
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v)),
                Text('每人 ${seconds.round()} 秒'),
                Slider(
                    value: seconds,
                    min: 30,
                    max: 90,
                    divisions: 4,
                    onChanged:
                        enabled ? (v) => setState(() => seconds = v) : null),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('選隊時自由發言'),
                    value: selectionFree,
                    onChanged: enabled
                        ? (v) => setState(() => selectionFree = v)
                        : null),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('投票前自由討論 60 秒'),
                    value: free,
                    onChanged:
                        enabled ? (v) => setState(() => free = v) : null),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(
                    context,
                    DiscussionSettings(
                        enabled: enabled,
                        speechSeconds: seconds.round(),
                        selectionFree: selectionFree,
                        freeSeconds: free ? 60 : 0)),
                child: const Text('儲存'))
          ]);
}

/// Only this small panel ticks; the session owns deadline advancement.
class DiscussionPanel extends StatefulWidget {
  const DiscussionPanel({super.key, required this.game});
  final GameSession game;
  @override
  State<DiscussionPanel> createState() => _DiscussionPanelState();
}

class _DiscussionPanelState extends State<DiscussionPanel> {
  Future<void> _express(bool approve) async {
    final game = widget.game;
    if (game.phase != GamePhase.discussion || game.speaker != game.mySeat) {
      return;
    }
    try {
      await game.expressOpinion(approve);
    } on GameMoveException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Timer? _ticker;
  int? _lastSecond;
  int get _remaining => max(
          0,
          ((widget.game.speechDeadline ?? widget.game.nowMillis) -
                  widget.game.nowMillis) /
              1000)
      .ceil();
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _remaining;
      if (remaining > 0 && remaining <= 5 && remaining != _lastSecond) {
        GameSounds.instance.play(GameSound.tick);
      }
      _lastSecond = remaining;
      setState(() {});
    });
    if (widget.game.phase == GamePhase.freeDiscussion) {
      GameSounds.instance.play(GameSound.freeDiscussion);
    } else if (!widget.game.hasOwnSeat ||
        widget.game.mySeat == widget.game.speaker) {
      GameSounds.instance.play(GameSound.turn);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final free = game.phase == GamePhase.freeDiscussion;
    final botSpeaking = game.isSolo && !free && game.speaker != game.mySeat;
    final remaining = max(0,
            ((game.speechDeadline ?? game.nowMillis) - game.nowMillis) / 1000)
        .ceil();
    final total = free
        ? game.discussionSettings.freeSeconds
        : game.discussionSettings.speechSeconds;
    final name =
        free ? '自由討論' : playerLabel(game.speaker!, game.players[game.speaker!]);
    return LayoutBuilder(
        builder: (_, constraints) => Center(
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                    width: min(constraints.maxWidth, 430),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.record_voice_over,
                          color: AvalonTheme.gold, size: 36),
                      const SizedBox(height: 8),
                      Text(name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AvalonTheme.gold)),
                      Text(botSpeaking ? '稍後自動過麥' : '$remaining 秒',
                          style: TextStyle(
                              fontSize: botSpeaking ? 18 : 36,
                              color: remaining <= 5
                                  ? Colors.redAccent
                                  : Colors.white)),
                      if (!botSpeaking)
                        LinearProgressIndicator(
                            value: total == 0
                                ? 0
                                : (remaining / total).clamp(0, 1),
                            color: remaining <= 5
                                ? Colors.redAccent
                                : AvalonTheme.gold),
                      const SizedBox(height: 10),
                      if (game.currentStatement != null) ...[
                        Text(game.currentStatement!,
                            key: const ValueKey('botSpeech'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color: Colors.white)),
                        const SizedBox(height: 10),
                      ],
                      if (game.isSolo && game.speaker == game.mySeat)
                        Wrap(spacing: 8, children: [
                          ActionChip(
                              key: const ValueKey('soloSupport'),
                              label: const Text('我支持這隊'),
                              onPressed: () => _express(true)),
                          ActionChip(
                              key: const ValueKey('soloOppose'),
                              label: const Text('我想換人'),
                              onPressed: () => _express(false)),
                        ]),
                      Text(
                          free
                              ? '時間到後自動開始投票'
                              : game.speaker == game.leader
                                  ? '隊長最後總結'
                                  : '依座位順序發言，隊長最後總結',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AvalonTheme.muted)),
                    ])))));
  }
}
