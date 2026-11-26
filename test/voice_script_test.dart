// Writes the recording script for the computer players' voices: every piece
// their lines are said in (lib/features/solo/voice_lines.dart), with the
// file name each recording must have. Not a test; run it on purpose:
//
//   VOICE_SCRIPT_OUT=tool/voice/script.csv VOICE_SCRIPT_GAMES=3000 \
//     flutter test test/voice_script_test.dart
//
// Pieces come from three places: games played out with talk on (the
// computers keep their memory from one game to the next, so the lines
// about earlier games come up too); every line of the dialogue catalogue
// with each kind of value in its blanks; every line about an earlier game;
// and every number in each form it is said. tool/voice/make_voices.py turns the script into recordings.
import 'dart:io';
import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/role_presets.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_catalog.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_archive.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_repository.dart';
import 'package:avalon_shadow_council/features/solo/memory/social_memory.dart';
import 'package:avalon_shadow_council/features/solo/persona/bot_persona.dart';
import 'package:avalon_shadow_council/features/solo/persona/persona_lines.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';
import 'package:avalon_shadow_council/features/solo/voice_lines.dart';
import 'balance_test.dart' show randomSetup;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['VOICE_SCRIPT_OUT'];
  final games = int.tryParse(Platform.environment['VOICE_SCRIPT_GAMES'] ?? '');

  test('voice script', () async {
    final count = <String, int>{}, from = <String, Set<String>>{};
    // pieces of one regular's own wordings, and pieces anyone may say
    final own = <String, Set<String>>{}, everyone = <String>{};
    void add(String line, String source, {String? persona}) {
      for (final piece in voicePieces(line)) {
        count[piece.text] = (count[piece.text] ?? 0) + 1;
        (from[piece.text] ??= {}).add(source);
        if (persona != null) {
          (own[piece.text] ??= {}).add(persona);
        } else if (source != 'games') {
          everyone.add(piece.text);
        }
      }
    }

    // every number, in each form it is said
    for (var n = 1; n <= 10; n++) {
      for (final unit in ['號', '次', '張', '人', '票', '分', '秒', '輪', '位', '']) {
        add('$n$unit', 'number');
      }
    }
    for (var n = 1; n <= 5; n++) {
      add('第$n次', 'number');
    }

    // the catalogue, each blank filled with each kind of value it takes
    final fills = <String, List<String>>{
      'target': ['3號'],
      'defender': ['3號'],
      'claimant': ['3號'],
      'quest': ['2'],
      'fails': ['1'],
      'attempt': ['2'],
      'otherMembers': ['3號、4號'],
      'reusedMembers': ['3號、4號'],
      'oldMember': ['3號', '我', '你自己'],
      'newMember': ['3號', '我', '你自己'],
      'claimedAlignment': ['邪惡陣營', '正義陣營'],
    };
    final blank = RegExp(r'\{\{(\w+)\}\}');
    for (final rule in BotDialogueCatalog.bundled.rules) {
      for (final template in rule.templates) {
        var lines = [template];
        for (final name in {
          for (final m in blank.allMatches(template)) m.group(1)!
        }) {
          lines = [
            for (final line in lines)
              for (final value in fills[name] ?? ['3號'])
                line.replaceAll('{{$name}}', value)
          ];
        }
        for (final line in lines) {
          // the one swapped out is never the one swapped in
          if (line.contains('我換成我') || line.contains('你自己換成你自己')) continue;
          add(line, 'catalog');
        }
      }
    }

    // each regular's own wordings, blanks filled the same way
    for (final p in BotPersona.cast) {
      final lines = PersonaLines.of(p.id)!;
      for (final line in [
        lines.openers,
        lines.approve,
        lines.oppose,
        lines.firstApprove,
        lines.firstOppose,
        lines.firstAgain,
      ].expand((l) => l)) {
        add(line, 'persona', persona: p.id);
      }
      for (final line in [...lines.join, ...lines.agree]) {
        add(PersonaLines.fill(line, {'who': '3號'}), 'persona', persona: p.id);
      }
      for (final line in lines.lady) {
        for (final then in ['', '當時']) {
          for (final side in ['正義', '邪惡']) {
            add(
                PersonaLines.fill(
                    line, {'who': '3號', 'then': then, 'side': side}),
                'persona',
                persona: p.id);
          }
        }
      }
      for (final template in lines.rules.values.expand((l) => l)) {
        var filled = [template];
        for (final name in {
          for (final m in blank.allMatches(template)) m.group(1)!
        }) {
          filled = [
            for (final line in filled)
              for (final value in fills[name] ?? ['3號'])
                line.replaceAll('{{$name}}', value)
          ];
        }
        for (final line in filled) {
          if (line.contains('我換成我') || line.contains('你自己換成你自己')) continue;
          add(line, 'persona', persona: p.id);
        }
      }
    }

    // every way a computer brings up an earlier game (the player is named
    // by seat: the number is a piece of its own)
    for (final kind in EpisodeKind.values) {
      for (final when in [memoryWhen(0), memoryWhen(1)]) {
        for (final line in memoryLines(kind, when, '1號')) {
          add(line, 'memory');
        }
      }
    }

    // games with talk on, the regulars remembering earlier games
    final archive = MatchRepository(storage: MemoryMatchStorage());
    final r = Random(7);
    for (var g = 0; g < (games ?? 0); g++) {
      final setup = randomSetup(r);
      final cast = BotPersona.deal(setup.count - 1, Random(g));
      final room = Room(code: '', players: [
        Player(id: '0', name: '玩家', isReady: true),
        for (final (i, p) in cast.indexed)
          Player(id: '${i + 1}', name: p.name, isReady: true)
      ])
        ..specialRoles.addAll([
          for (final role in rolePreset(setup.count,
              lancelot: setup.expansions.lancelot > 0)!)
            role.label
        ])
        ..discussion = DiscussionSettings.recommended
        ..expansions = setup.expansions;
      final lines = <String>[];
      final speakers = <String?>[];
      fakeAsync((time) {
        final s = SoloGameSession(room,
            random: Random(g),
            personas: cast,
            archive: archive,
            difficulty: BotDifficulty.values[g % 3],
            botDelay: const Duration(milliseconds: 1),
            speechDuration: const Duration(milliseconds: 1),
            autopilot: true);
        time.flushMicrotasks();
        var steps = 0;
        while (s.phase != GamePhase.finished && steps++ < 20000) {
          if (s.phase == GamePhase.voteResult) s.continueVote();
          if (s.phase == GamePhase.questResult) s.continueQuest();
          time.elapse(const Duration(milliseconds: 1));
          time.flushMicrotasks();
        }
        time.elapse(const Duration(milliseconds: 50));
        time.flushMicrotasks();
        // seat 0 is the player's: their lines are their own to say
        for (final st in s.statements) {
          if (st.speaker != 0 && !st.continues) {
            lines.add(st.text);
            speakers.add(s.persona(st.speaker)?.id);
          }
        }
        s.dispose();
        time.flushMicrotasks();
      });
      for (final (i, line) in lines.indexed) {
        add(line, 'games');
        // heard in a game from someone whose own wording it is not: anyone's
        for (final piece in voicePieces(line)) {
          if (!(own[piece.text]?.contains(speakers[i]) ?? false)) {
            everyone.add(piece.text);
          }
        }
      }
    }

    if (out == null) {
      // run as a plain test: just show that it works
      expect(count, isNotEmpty);
      return;
    }
    final rows = count.keys.toList()
      ..sort((a, b) => count[b]!.compareTo(count[a]!));
    String cell(String v) =>
        v.contains(RegExp(r'[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    // voices: who records the piece (empty: every regular)
    final csv = StringBuffer('id,text,uses,source,voices\n');
    for (final text in rows) {
      csv.writeln([
        voicePieceId(text),
        cell(text),
        count[text],
        (from[text]!.toList()..sort()).join('+'),
        everyone.contains(text) || !own.containsKey(text)
            ? ''
            : (own[text]!.toList()..sort()).join('+'),
      ].join(','));
    }
    File(out)
      ..createSync(recursive: true)
      ..writeAsStringSync(csv.toString());
    // ignore: avoid_print
    print('${rows.length} pieces written to $out');
  }, timeout: Timeout.none);
}
