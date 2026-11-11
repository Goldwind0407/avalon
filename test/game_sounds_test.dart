import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/game_sounds.dart';
import 'package:avalon_shadow_council/core/sound_output.dart';
import 'package:avalon_shadow_council/core/sound_controls.dart';
import 'package:flutter/material.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/game_sound_events.dart';
import 'package:avalon_shadow_council/features/table/card_reveal.dart';

class FakeOutput extends SoundOutput {
  final played = <(String, double, bool)>[];
  int stops = 0;
  bool fail = false;
  @override
  Future<void> play(String name, double volume, bool important) async {
    if (fail) throw StateError('audio unavailable');
    played.add((name, volume, important));
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all cues have valid, short PCM assets with headroom', () {
    for (final cue in GameSound.values) {
      final bytes = File('assets/audio/${cue.name}.wav').readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF', reason: cue.name);
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint16(34, Endian.little), 16);
      final duration = header.getUint32(40, Endian.little) /
          header.getUint32(28, Endian.little);
      expect(duration, inInclusiveRange(.05, 3), reason: cue.name);
      for (var i = 44; i < bytes.length; i += 2) {
        expect(header.getInt16(i, Endian.little).abs(), lessThan(32767));
      }
    }
  });

  test('mute, zero volume, background and same-frame dedup suppress cues',
      () async {
    final output = FakeOutput();
    final sound = GameSounds(output: output);
    await sound.initialize(persist: false);
    sound.play(GameSound.flip);
    sound.play(GameSound.flip);
    await Future<void>.delayed(Duration.zero);
    expect(output.played.length, 1);
    sound.setEnabled(false);
    sound.play(GameSound.goodWin);
    expect(output.played.length, 1);
    sound.setEnabled(true);
    sound.setVolume(0);
    sound.play(GameSound.evilWin);
    expect(output.played.length, 1);
    sound.setVolume(.4);
    sound.didChangeAppLifecycleState(AppLifecycleState.paused);
    sound.play(GameSound.turn);
    expect(output.played.length, 1);
    sound.didChangeAppLifecycleState(AppLifecycleState.resumed);
    sound.play(GameSound.success);
    expect(output.played.last, ('success', .4, true));
    expect(output.stops, greaterThanOrEqualTo(3));
    output.fail = true;
    sound.play(GameSound.failure);
    await Future<void>.delayed(Duration.zero);
    sound.dispose();
  });

  test('secret phases and pending results cannot play result cues', () {
    for (final phase in [
      GamePhase.identity,
      GamePhase.voteResult,
      GamePhase.questResult,
      GamePhase.finished
    ]) {
      expect(phaseSound(phase), isNull);
    }
    expect(phaseSound(GamePhase.ladyResult), GameSound.flip);
    expect(phaseSound(GamePhase.excaliburResult), GameSound.flip);
    expect(phaseSound(GamePhase.quest), GameSound.questStart);
  });

  testWidgets(
      'skipping public reveal plays verdict once without a burst of card sounds',
      (tester) async {
    var flips = 0, verdicts = 0, shuffles = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardReveal(
                items: List.generate(
                    3,
                    (_) => RevealItem(
                        front: (_) => const SizedBox(),
                        back: (_) => const SizedBox(),
                        glow: const Color(0xFFFFFFFF))),
                cardWidth: 60,
                scale: .8,
                caption: '測試揭曉',
                verdict: '任務成功',
                verdictColor: Colors.green,
                detail: '',
                button: '繼續',
                onContinue: () {},
                onReveal: (_) => flips++,
                onVerdict: () => verdicts++,
                onShuffle: () => shuffles++))));
    await tester.tap(find.byType(CardReveal));
    await tester.pump(const Duration(seconds: 2));
    expect(flips, 0);
    expect(shuffles, 0);
    expect(verdicts, 1);
    await tester.tap(find.byType(CardReveal));
    await tester.pump();
    expect(verdicts, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('audio settings mute immediately without changing voice controls',
      (tester) async {
    final events = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundOutput.channel, (call) async {
      events.add(call);
      return null;
    });
    await GameSounds.instance.initialize(persist: false);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SoundSettingsButton())));
    await tester.tap(find.byTooltip('音效設定'));
    await tester.pumpAndSettle();
    expect(find.text('只影響遊戲音效，不會關閉多人語音。'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(GameSounds.instance.enabled, isFalse);
    expect(events.any((e) => e.method == 'stop'), isTrue);
    final played = events.where((e) => e.method == 'play').length;
    await tester.tap(find.text('試聽'));
    await tester.pump();
    expect(events.where((e) => e.method == 'play').length, played);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('試聽'));
    await tester.pump();
    expect(events.last.method, 'play');
    await tester.pumpWidget(const SizedBox());
    GameSounds.instance.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SoundOutput.channel, null);
  });
}
