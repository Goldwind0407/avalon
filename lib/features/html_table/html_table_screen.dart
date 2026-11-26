import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/assets.dart';
import '../../core/bot_voices.dart';
import '../../core/game_sounds.dart';
import '../../core/perf_stage.dart';
import '../../core/sound_controls.dart';
import '../../core/theme.dart';
import '../game/discussion_widgets.dart' show speechReading;
import '../game/game_model.dart';
import '../game/game_session.dart';
import '../game/game_sound_events.dart';
import '../game/player_speech.dart';
import '../lobby/room_model.dart';
import '../notebook/notebook_screen.dart';
import '../rules/rules_screen.dart';
import '../solo/bot_difficulty.dart';
import '../solo/memory/match_repository.dart';
import '../solo/persona/bot_persona.dart';
import '../solo/review_screen.dart';
import '../solo/solo_session.dart';
import 'table_page.dart';

/// A game against the computers on a table the browser draws itself
/// (web/table/table.js), over this page: on an iPhone the app's own
/// drawing stops for a second at the big moments (votes turned over, the
/// quest's cards), the browser's does not.
///
/// The game is the same [SoloGameSession] as on [GameScreen]; this screen
/// hands the table what the player may see of it, makes the moves the
/// table asks for, reads the computers' lines aloud, and opens the app's
/// own pages (rules, notebook, review) when asked, the table stepping
/// aside meanwhile.
class HtmlTableScreen extends StatefulWidget {
  const HtmlTableScreen(
      {super.key,
      required this.room,
      this.difficulty = BotDifficulty.normal,
      this.cast,
      this.archive});
  final Room room;
  final BotDifficulty difficulty;
  final List<BotPersona>? cast;
  final MatchRepository? archive;

  /// Whether this device can play on the browser's table.
  static bool get available => kIsWeb && tablePageAvailable;

  @override
  State<HtmlTableScreen> createState() => _HtmlTableScreenState();
}

class _HtmlTableScreenState extends State<HtmlTableScreen>
    with WidgetsBindingObserver {
  late final SoloGameSession game;
  bool _queued = false, _closed = false, _background = false;
  int _holds = 0;

  /// How many lines of the record the table has already taken in.
  int _heard = 0;
  String? _spokenKey;
  GamePhase? _phase;

  @override
  void initState() {
    super.initState();
    game = SoloGameSession(widget.room,
        difficulty: widget.difficulty,
        personas: widget.cast,
        archive: widget.archive ?? MatchRepository.shared);
    _heard = game.statements.length;
    _phase = game.phase;
    perfPageTable = true;
    perfStage = _stage;
    game.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    openTablePage(_host);
    _send();
  }

  @override
  void dispose() {
    _close();
    game.removeListener(_changed);
    game.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    perfPageTable = false;
    perfStage = 'menu';
    closeTablePage();
    unawaited(GameSounds.instance.stop());
    unawaited(BotVoices.instance.stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    perfNote('life:${state.name}');
    // a page only 'inactive' (lost the focus) is still in view
    _background = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    _pause();
  }

  void _pause() => game.pauseAutomation(_background || _holds > 0);

  Future<T> _held<T>(Future<T> Function() work) async {
    _holds++;
    _pause();
    try {
      return await work();
    } finally {
      _holds--;
      if (mounted) _pause();
    }
  }

  String get _stage {
    final name = game.phase.name;
    return 'h${name[0].toUpperCase()}${name.substring(1)}';
  }

  void _changed() {
    if (_closed) return;
    final phase = game.phase;
    _speakLine();
    if (phase != _phase) {
      _phase = phase;
      unawaited(GameSounds.instance.stop());
      final cue = phaseSound(phase);
      if (cue != null) GameSounds.instance.play(cue);
    }
    perfStage = _stage;
    _send();
  }

  /// One update a turn of the event loop, however many changes it held
  /// (and never in the middle of the table's own call into the game).
  void _send() {
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_closed) updateTablePage(jsonEncode(_snapshot()));
    });
  }

  void _event(Map<String, Object?> event) {
    if (!_closed) tablePageEvent(jsonEncode(event));
  }

  String _player(int i) => playerLabel(i, game.players[i]);
  static String _url(String asset) => 'assets/$asset';

  /// A computer's line, said aloud once when it appears; a new turn cuts
  /// off the last one. A line said outside a speaking turn (what the Lady
  /// showed, the Assassin's choice) is also shown for a moment.
  void _speakLine() {
    final record = game.statements;
    if (record.length > _heard) {
      final fresh = record.sublist(min(_heard, record.length));
      _heard = record.length;
      final aside = game.phase == GamePhase.discussion
          ? null
          : fresh
              .where((s) =>
                  !s.continues &&
                  s.speaker != game.mySeat &&
                  (game.isComputer(s.speaker) || s.intent == 'interpretLady'))
              .lastOrNull;
      if (aside != null) {
        _spokenKey = null;
        unawaited(
            BotVoices.instance.speak(game.voiceOf(aside.speaker), aside.text));
        _event({
          'type': 'toast',
          'title': _player(aside.speaker),
          'text': aside.text,
          'image': aside.intent == 'interpretLady'
              ? _url(Assets.ladyOfTheLake)
              : null,
        });
        return;
      }
    }
    final speaker = game.speaker, line = game.currentStatement;
    final turn = '${game.generation}/${game.speechVersion}';
    if (game.phase != GamePhase.discussion ||
        speaker == null ||
        line == null ||
        !game.isComputer(speaker)) {
      if (_spokenKey != null && !_spokenKey!.startsWith('$turn/')) {
        _spokenKey = null;
        unawaited(BotVoices.instance.stop());
      }
      return;
    }
    final key = '$turn/$line';
    if (key == _spokenKey) return;
    _spokenKey = key;
    perfNote('line');
    final version = game.speechVersion;
    unawaited(
        BotVoices.instance.speak(game.voiceOf(speaker), line).then((heard) {
      if (heard && !_closed) game.lineHeard(version);
    }));
  }

  int? get _expansionActor => switch (game.phase) {
        GamePhase.lady || GamePhase.ladyResult => game.ladyHolder,
        GamePhase.excalibur ||
        GamePhase.excaliburResult =>
          game.excaliburHolder,
        _ => null,
      };

  /// This player has a secret move to make now.
  bool get _pending {
    final me = game.mySeat!;
    if (!game.hasPrivateInput || game.roleOf(me) == null) return false;
    return switch (game.phase) {
      GamePhase.identity => !game.confirmedSeats.contains(me),
      GamePhase.vote => !game.votedSeats.contains(me),
      GamePhase.quest =>
        game.team.contains(me) && !game.playedSeats.contains(me),
      GamePhase.assassination => game.roleOf(me) == Role.assassin,
      GamePhase.lady || GamePhase.excalibur => _expansionActor == me,
      GamePhase.ladyResult ||
      GamePhase.excaliburResult =>
        _expansionActor == me && game.latestReveal != null,
      _ => false,
    };
  }

  /// The game as the player in seat 1 may see it.
  Map<String, Object?> _snapshot() {
    final me = game.mySeat!;
    final phase = game.phase;
    final role = game.roleOf(me);
    final finished = phase == GamePhase.finished;
    final reveal = game.latestReveal;
    final attempt = game.rejections + 1;
    final thisRound = [
      for (final s in game.statements)
        if (s.quest == game.questNumber && s.attempt == attempt) s
    ];
    Map<String, Object?>? identity;
    if (role != null) {
      final info = roleInformation(role,
          configuredRoles: game.configuredRoles, expansions: game.expansions);
      final lancelot = game.knownLancelotSeat(me);
      identity = {
        'label': role.label,
        'evil': role.isEvil,
        'lancelot': role.isLancelot,
        'assassin': role == Role.assassin,
        'art': _url(game.roleArt(me)!),
        'heading': info.heading,
        'lists': info.listsPlayers,
        'seen': [
          for (final s in game.visiblePlayers(me))
            knownSeatLabel(s, game.players[s], lancelot: lancelot)
        ],
        'reminder': [
          if (info.reminder.isNotEmpty) info.reminder,
          if (lancelot != null) lancelotAllyReminder,
        ].join('\n'),
      };
    }
    return {
      'gen': game.generation,
      'turn': '${game.generation}|${phase.name}|${game.history.length}|'
          '${game.rejections}|${game.speechVersion}',
      'phase': phase.name,
      'names': game.players,
      'me': me,
      'leader': game.leader,
      'rejections': game.rejections,
      'team': game.team,
      'votes': phase == GamePhase.voteResult ? game.votes : const <bool>[],
      'approved': phase == GamePhase.voteResult && game.teamApproved,
      'history': [
        for (final q in game.history)
          {
            'team': q.team,
            'fails': q.fails,
            'ok': q.succeeded,
            'swordHolder': q.excaliburHolder,
            'swordTarget': q.excaliburTarget,
          }
      ],
      'quest': game.questNumber,
      'need': game.requiredTeam,
      'failsNeeded': game.failsRequired,
      'winner': game.winner,
      'result': game.result,
      'assassinTarget': game.assassinTarget,
      'confirmed': game.confirmedSeats.toList(),
      'voted': game.votedSeats.toList(),
      'played': game.playedSeats.toList(),
      'speaker': game.speaker,
      'speechVersion': game.speechVersion,
      'deadline': game.speechDeadline,
      'speechSeconds': game.discussionSettings.speechSeconds,
      'talk': game.discussionSettings.enabled,
      'line': game.currentStatement,
      'mine': [
        for (final s in thisRound)
          if (s.speaker == me && !s.continues) s.text
      ],
      'revised': {
        for (final s in thisRound)
          if (s.intent == 'reassess' && s.supportsTeam != null) s.speaker
      }.length,
      'pending': _pending,
      'paused': _holds > 0 || _background,
      'identity': identity,
      'evilNow': game.evilNow(me),
      'mustFail': game.mustFail(me),
      'lady': game.expansions.lady,
      'lancelot': game.expansions.lancelot,
      'excalibur': game.expansions.excalibur,
      'loyalty': game.loyalty,
      'switched': game.lancelotSwitched,
      'ladyHolder': game.ladyHolder,
      'ladyPast': game.ladyPast,
      'ladyCheck': game.ladyChecks.isEmpty
          ? null
          : {
              'holder': game.ladyChecks.last.holder,
              'target': game.ladyChecks.last.target,
            },
      'swordHolder': game.excaliburHolder,
      'reveal': reveal == null
          ? null
          : {
              'kind': reveal.kind,
              'target': reveal.target,
              'evil': reveal.evil,
              'card': reveal.card,
            },
      'roles': finished
          ? [
              for (var i = 0; i < game.players.length; i++)
                {
                  'art': _url(game.roleArt(i) ?? Assets.cardBackRole),
                  'label': game.roleOf(i)?.label,
                  'merlin': game.roleOf(i) == Role.merlin,
                  'moved': (game.roleOf(i)?.isLancelot ?? false) &&
                      game.lancelotSwitched,
                  'style': game.seatStyle(i),
                }
            ]
          : null,
      // the whole game, roles and reasons, once it is over
      'review': finished,
    };
  }

  /// What the table asks of the game. Moves answer at once (an empty
  /// string); the table hears of the new state in the next update.
  String _host(String type, String arg) {
    if (_closed) return '';
    switch (type) {
      case 'act':
        unawaited(_act(jsonDecode(arg) as Map<String, dynamic>));
      case 'read':
        final text = arg.trim();
        return text.isEmpty
            ? ''
            : speechReading(
                PlayerSpeech.parse(text, game.players, game.mySeat!),
                game.players);
      case 'log':
        return jsonEncode([
          for (final line in game.statements.reversed)
            if (!line.continues)
              {
                'heading': '第 ${line.quest} 次遠征・第 ${line.attempt} 次提案・'
                    '${_player(line.speaker)}'
                    '${line.intent == 'reassess' ? '（改口）' : ''}',
                'text': line.text,
                'now': line.quest == game.questNumber &&
                    line.attempt == game.rejections + 1,
              }
        ]);
      case 'sound':
        final sound =
            GameSound.values.where((s) => s.name == arg).firstOrNull;
        if (sound != null) GameSounds.instance.play(sound);
      case 'hold':
        if (arg == '1') {
          _holds++;
        } else {
          _holds = max(0, _holds - 1);
        }
        _pause();
        _send();
      case 'open':
        unawaited(_open(arg));
      case 'leave':
        _close();
        if (mounted) Navigator.of(context).pop();
      case 'note':
        perfNote(arg);
    }
    return '';
  }

  Future<void> _act(Map<String, dynamic> m) async {
    final me = game.mySeat!;
    try {
      switch (m['move']) {
        case 'confirm':
          await game.confirmIdentity(me);
        case 'propose':
          await game.proposeTeam(
              [for (final s in m['team'] as List) (s as num).toInt()],
              excalibur: (m['sword'] as num?)?.toInt());
        case 'vote':
          await game.vote(me, m['approve'] == true);
        case 'endSpeech':
          await game.endSpeech((m['version'] as num).toInt());
        case 'express':
          await game.expressOpinion(m['approve'] == true);
        case 'say':
          final text = (m['text'] as String).trim();
          if (text.isEmpty) return;
          await game.say(PlayerSpeech.parse(text, game.players, me));
        case 'quest':
          await game.playQuest(me, m['success'] == true);
        case 'continueVote':
          await game.continueVote();
        case 'continueQuest':
          await game.continueQuest();
        case 'assassinate':
          await game.assassinate((m['target'] as num).toInt());
        case 'lady':
          await game.useLady((m['target'] as num).toInt());
        case 'announceLady':
          await game.announceLady(m['evil'] == true);
          await game.continueLady();
        case 'continueLady':
          await game.continueLady();
        case 'excalibur':
          await game.useExcalibur((m['target'] as num?)?.toInt());
        case 'continueExcalibur':
          await game.continueExcalibur();
        case 'restart':
          await game.restart();
      }
    } on GameMoveException catch (e) {
      _event({'type': 'refused', 'text': e.message});
    }
    _send();
  }

  /// One of the app's own pages over the table, the game held meanwhile.
  Future<void> _open(String what) async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    Future<void> page(Widget Function() build) =>
        navigator.push(MaterialPageRoute<void>(builder: (_) => build()));
    coverTablePage(true);
    try {
      await _held(() async {
        switch (what) {
          case 'rules':
            await RulesScreen.open(
                context,
                switch (game.phase) {
                  GamePhase.lady || GamePhase.ladyResult => RulesTopic.lady,
                  GamePhase.excalibur ||
                  GamePhase.excaliburResult =>
                    RulesTopic.excalibur,
                  GamePhase.identity => RulesTopic.roles,
                  _ => RulesTopic.round,
                });
          case 'notebook':
            GameSounds.instance.play(GameSound.page);
            await page(() => NotebookScreen(session: game));
          case 'review':
            final review = game.review;
            if (review != null) {
              await page(() => ReviewScreen(
                  review: review,
                  online: false,
                  difficulty: widget.difficulty.label));
            }
          case 'sound':
            await showSoundSettings(context);
        }
      });
    } finally {
      if (!_closed) {
        coverTablePage(false);
        _send();
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          // the table asks first (its own dialog)
          if (!didPop && !_closed) _event({'type': 'back'});
        },
        // under the table: nothing that moves, so nothing here is drawn
        // while it is on screen (the app's own pages open over this)
        child: const ColoredBox(color: AvalonTheme.bg),
      );
}
