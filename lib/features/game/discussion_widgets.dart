import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/game_sounds.dart';
import '../../core/theme.dart';
import 'discussion_model.dart';
import 'game_model.dart';
import 'game_session.dart';
import 'player_speech.dart';

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
                      if (game.isSolo && game.speaker == game.mySeat) ...[
                        PlayerSpeechBar(game: game),
                        const SizedBox(height: 6),
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
                      ],
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

/// Solo: what the player can say on their turn before taking a side.
/// Every line is public; computer players weigh it and may answer.
class PlayerSpeechBar extends StatelessWidget {
  const PlayerSpeechBar({super.key, required this.game});
  final GameSession game;

  Future<void> _say(BuildContext context, PlayerSpeech speech) async {
    try {
      await game.say(speech);
    } on GameMoveException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _type(BuildContext context) async {
    // typing takes a while: hold the clock and the computers meanwhile
    game.pauseAutomation(true);
    final String? text;
    try {
      text = await showDialog<String>(
          context: context,
          builder: (_) => _SpeechPage(game: game),
          useSafeArea: false);
    } finally {
      game.pauseAutomation(false);
    }
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    await _say(
        context, PlayerSpeech.parse(text, game.players, game.mySeat ?? -1));
  }

  @override
  Widget build(BuildContext context) {
    final mine = [
      for (final s in game.statements)
        if (s.speaker == game.mySeat &&
            s.quest == game.questNumber &&
            s.attempt == game.rejections + 1)
          s.text
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (mine.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('你說：${mine.join('　')}',
              key: const ValueKey('mySpeech'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AvalonTheme.gold)),
        ),
      FilledButton.tonalIcon(
          key: const ValueKey('speechType'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('我要發言'),
          onPressed: () => _type(context)),
    ]);
  }
}

/// What the computers will take from a typed line, in words.
String speechReading(PlayerSpeech speech, List<String> players) {
  final who = speech.target == null
      ? ''
      : playerLabel(speech.target!, players[speech.target!]);
  return switch (speech.kind) {
    PlayerSpeechKind.suspect => '你懷疑 $who',
    PlayerSpeechKind.trust => '你相信 $who 是好人',
    PlayerSpeechKind.ask => '你在問 $who，對方會回答',
    PlayerSpeechKind.challengeVote => '你在問 $who 的投票理由',
    PlayerSpeechKind.claimGood => '你說自己是好人',
    PlayerSpeechKind.claimPercival =>
      speech.target == null ? '你宣稱自己是派西維爾（電腦不一定相信）' : '你宣稱自己是派西維爾，並指 $who 是莫甘娜',
    PlayerSpeechKind.support => '你支持這隊',
    PlayerSpeechKind.oppose => '你想換人',
    PlayerSpeechKind.remark => '只是一句話（沒有點名，也沒有表態）',
  };
}

/// Full screen so the field stays above the keyboard on a landscape phone.
class _SpeechPage extends StatefulWidget {
  const _SpeechPage({required this.game});
  final GameSession game;
  @override
  State<_SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<_SpeechPage> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _send() => Navigator.pop(context, controller.text);

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final text = controller.text.trim();
    final reading = text.isEmpty
        ? null
        : speechReading(
            PlayerSpeech.parse(text, game.players, game.mySeat ?? -1),
            game.players);
    return Dialog.fullscreen(
        backgroundColor: AvalonTheme.bg,
        child: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        IconButton(
                            tooltip: '取消',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                        Expanded(
                            child: TextField(
                                key: const ValueKey('speechText'),
                                controller: controller,
                                autofocus: true,
                                maxLength: 60,
                                textInputAction: TextInputAction.send,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _send(),
                                decoration: const InputDecoration(
                                    hintText: '想說什麼都可以，例如：3號上一輪投了失敗的隊，我不信他'))),
                        const SizedBox(width: 8),
                        FilledButton(
                            key: const ValueKey('speechSend'),
                            onPressed: text.isEmpty ? null : _send,
                            child: const Text('說出來')),
                      ]),
                      Padding(
                          padding: const EdgeInsets.only(left: 48),
                          child: Text(
                              reading == null
                                  ? '計時已暫停。提到座位號碼或暱稱，再說懷疑、相信、為什麼或支持／反對，電腦就會回應。'
                                  : '電腦會理解成：$reading',
                              key: const ValueKey('speechReading'),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: reading == null
                                      ? AvalonTheme.muted
                                      : AvalonTheme.gold))),
                    ]))));
  }
}
