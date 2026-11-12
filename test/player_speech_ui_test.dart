import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/discussion_widgets.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/game/player_speech.dart';

class SpeakingSession extends GameSession {
  final said = <PlayerSpeech>[];
  @override
  List<String> get players => ['你', '電腦1', '電腦2', '電腦3', '電腦4'];
  @override
  int? get mySeat => 0;
  @override
  int get questNumber => 1;
  @override
  int get rejections => 0;
  @override
  List<DiscussionStatement> get statements => [
        for (final s in said)
          DiscussionStatement(
              speaker: 0,
              quest: 1,
              attempt: 1,
              text: s.text ?? '${s.kind.name}${s.target}')
      ];
  @override
  Future<void> say(PlayerSpeech speech) async {
    said.add(speech);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the player can doubt, ask or type before taking a side',
      (tester) async {
    tester.view.physicalSize = const Size(667, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = SpeakingSession();
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: Scaffold(
            body: Center(
                child: ListenableBuilder(
                    listenable: game,
                    builder: (_, __) => PlayerSpeechBar(game: game))))));
    await tester.tap(find.byKey(const ValueKey('speechSuspect')));
    await tester.pumpAndSettle();
    // the player cannot point at themselves
    expect(find.byKey(const ValueKey('speechSeat0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('speechSeat2')));
    await tester.pumpAndSettle();
    expect(game.said.single.kind, PlayerSpeechKind.suspect);
    expect(game.said.single.target, 2);
    expect(find.byKey(const ValueKey('mySpeech')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('speechType')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('speechText')), '4號你為什麼投贊成？');
    await tester.tap(find.byKey(const ValueKey('speechSend')));
    await tester.pumpAndSettle();
    expect(game.said.last.kind, PlayerSpeechKind.ask);
    expect(game.said.last.target, 3);
    expect(tester.takeException(), isNull);
  });
}
