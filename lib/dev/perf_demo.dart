// A table that plays itself, for measuring how smoothly the web build
// draws a real game: open the web build with `?demo` in the address (and
// `?demo&perf` to have web/perf.js report the frame times). Nothing here
// is reachable without that, and it changes no game.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import '../features/game/discussion_model.dart';
import '../features/game/expansion_model.dart';
import '../features/game/game_model.dart';
import '../features/game/game_screen.dart';
import '../features/lobby/role_presets.dart';
import '../features/lobby/room_model.dart';
import '../features/solo/persona/bot_persona.dart';
import '../features/solo/solo_session.dart';

/// Whether this page was opened to watch a self-playing table.
bool get perfDemoRequested =>
    kIsWeb && Uri.base.queryParameters.containsKey('demo');

/// Seven computers (the player's seat too) with the Lady, game after game.
class PerfDemo extends StatefulWidget {
  const PerfDemo({super.key});
  @override
  State<PerfDemo> createState() => _PerfDemoState();
}

class _PerfDemoState extends State<PerfDemo> {
  late SoloGameSession game;
  var round = 0;
  Timer? _next;

  @override
  void initState() {
    super.initState();
    _deal();
  }

  void _deal() {
    const count = 7;
    // the regulars, with their voices
    final cast = BotPersona.deal(count - 1, Random(round));
    final room = Room(code: '', players: [
      Player(id: '0', name: '你', isReady: true),
      for (final (i, p) in cast.indexed)
        Player(id: '${i + 1}', name: p.name, isReady: true)
    ])
      ..specialRoles.addAll([for (final r in rolePreset(count)!) r.label])
      ..discussion = DiscussionSettings.recommended
      ..expansions = const ExpansionSettings(lady: true);
    game = SoloGameSession(room,
        random: Random(round),
        personas: cast,
        autopilot: true,
        // the same pace as a real game (SoloGameSession's own defaults)
        )
      ..addListener(_onChanged);
  }

  /// The steps a person would tap through on the table.
  void _onChanged() {
    final phase = game.phase;
    _next?.cancel();
    if (phase == GamePhase.voteResult) {
      // about when a person reads the result and taps on
      _next = Timer(const Duration(milliseconds: 3500), game.continueVote);
    } else if (phase == GamePhase.questResult) {
      _next = Timer(const Duration(milliseconds: 6000), game.continueQuest);
    } else if (phase == GamePhase.finished) {
      _next = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        game.removeListener(_onChanged);
        final old = game;
        setState(() {
          round++;
          _deal();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      });
    }
  }

  @override
  void dispose() {
    _next?.cancel();
    game.removeListener(_onChanged);
    game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GameScreen.online(key: ValueKey(round), session: game);
}
