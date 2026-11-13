import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/game/player_speech.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';
import 'solo_session_test.dart' show soloRoom;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final names = ['你', '電腦1', '電腦2', '電腦3', '電腦4', '電腦5', '電腦6', '電腦10'];

  test('typed speech is read for a seat and what is said about it', () {
    PlayerSpeech read(String text) => PlayerSpeech.parse(text, names, 0);
    expect(read('我懷疑3號').kind, PlayerSpeechKind.suspect);
    expect(read('我懷疑3號').target, 2);
    expect(read('3 號是壞人吧').target, 2);
    expect(read('電腦4 很可疑').target, 4);
    // the longest nickname wins: 電腦10 is not 電腦1
    expect(read('電腦10 有問題').target, 7);
    expect(read('我不相信 2號').kind, PlayerSpeechKind.suspect);
    expect(read('2號不是壞人').kind, PlayerSpeechKind.trust);
    expect(read('我相信 5 號').kind, PlayerSpeechKind.trust);
    expect(read('4號你為什麼投贊成？').kind, PlayerSpeechKind.ask);
    expect(read('我是好人').kind, PlayerSpeechKind.claimGood);
    expect(read('這隊我反對').kind, PlayerSpeechKind.oppose);
    expect(read('我支持這隊').kind, PlayerSpeechKind.support);
    expect(read('今天天氣不錯').kind, PlayerSpeechKind.remark);
    // talking about yourself is not an accusation of anyone
    expect(read('我懷疑1號').target, isNull);
    expect(read('懷疑大家').kind, PlayerSpeechKind.remark);
  });

  test('the player speaks several times, bots weigh it and answer questions',
      () {
    fakeAsync((time) {
      for (var seed = 0; seed < 40; seed++) {
        final s = SoloGameSession(soloRoom(7, const ExpansionSettings()),
            random: Random(seed),
            botDelay: const Duration(milliseconds: 1),
            speechDuration: const Duration(milliseconds: 1));
        var steps = 0;
        // play until it is the player's turn to speak
        while (!(s.phase == GamePhase.discussion && s.speaker == 0) &&
            s.phase != GamePhase.finished &&
            steps++ < 400) {
          if (s.hasPrivateInput) {
            switch (s.phase) {
              case GamePhase.identity:
                s.confirmIdentity(0);
              case GamePhase.team:
                s.proposeTeam(List.generate(s.requiredTeam, (i) => i));
              case GamePhase.vote:
                s.vote(0, true);
              case GamePhase.quest:
                s.playQuest(0, !s.evilNow(0)!);
              default:
                break;
            }
          } else if ([GamePhase.voteResult, GamePhase.questResult]
              .contains(s.phase)) {
            s.phase == GamePhase.voteResult
                ? s.continueVote()
                : s.continueQuest();
          } else {
            time.elapse(const Duration(milliseconds: 1));
          }
          time.flushMicrotasks();
        }
        if (s.phase != GamePhase.discussion) {
          s.dispose();
          continue;
        }
        final version = s.speechVersion;
        s.say(const PlayerSpeech(PlayerSpeechKind.suspect, target: 2));
        s.say(const PlayerSpeech(PlayerSpeechKind.ask, target: 3));
        expect(() => s.say(const PlayerSpeech(PlayerSpeechKind.suspect)),
            throwsA(isA<GameMoveException>()));
        expect(s.speechVersion, version,
            reason: 'saying does not end the turn');
        final accuse = s.statements[s.statements.length - 2];
        expect(accuse.position, DiscussionPosition.suspect);
        expect(accuse.target, 2);
        expect(accuse.text, contains('3 號'));
        final question = s.statements.last;
        expect(question.questionTo, 3);
        final asked = s.statements.length - 1;
        s.expressOpinion(false);
        // let the remaining bots speak
        for (var i = 0; i < 200 && s.phase == GamePhase.discussion; i++) {
          time.elapse(const Duration(milliseconds: 1));
          time.flushMicrotasks();
        }
        final answered = s.statements.any((r) =>
            r.speaker == 3 && r.replyTo == asked && r.quest == question.quest);
        final spoke = s.statements.any((r) =>
            r.speaker == 3 &&
            r.quest == question.quest &&
            r.attempt == question.attempt &&
            s.statements.indexOf(r) > asked);
        if (spoke) expect(answered, isTrue, reason: 'seed $seed');
        s.dispose();
        time.flushMicrotasks();
        return;
      }
      fail('the player never got to speak');
    });
  });
}
