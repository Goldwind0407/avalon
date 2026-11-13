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
  final pauses = <bool>[];
  @override
  void pauseAutomation(bool paused) => pauses.add(paused);

  @override
  Future<void> say(PlayerSpeech speech) async {
    said.add(speech);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the player types freely, sees how it reads, and the clock holds',
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
    // no canned lines, just a way to speak
    expect(find.byKey(const ValueKey('speechSuspect')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('speechType')));
    await tester.pumpAndSettle();
    expect(game.pauses, [true]);
    // a landscape keyboard takes most of the screen; the field stays in view
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();
    final field = tester.getRect(find.byKey(const ValueKey('speechText')));
    expect(field.bottom, lessThan(120));
    await tester.enterText(
        find.byKey(const ValueKey('speechText')), '我覺得電腦2很可疑');
    await tester.pump();
    expect(find.text('電腦會理解成：你懷疑 3 號 【電腦2】'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('speechSend')));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(game.pauses, [true, false]);
    expect(game.said.single.kind, PlayerSpeechKind.suspect);
    expect(game.said.single.target, 2);
    expect(find.byKey(const ValueKey('mySpeech')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('speechType')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('speechText')), '4號你為什麼投贊成？');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(game.said.last.kind, PlayerSpeechKind.ask);
    expect(game.said.last.target, 3);
    expect(tester.takeException(), isNull);
  });
}
