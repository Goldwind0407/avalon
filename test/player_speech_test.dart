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

  test('each player named gets what is said about them', () {
    List<(PlayerSpeechKind, int?, bool?)> read(String text) => [
          for (final p in PlayerSpeech.parse(text, names, 0).points)
            (p.kind, p.target, p.claimsEvil)
        ];
    const suspect = PlayerSpeechKind.suspect,
        trust = PlayerSpeechKind.trust,
        lady = PlayerSpeechKind.ladyClaim,
        ask = PlayerSpeechKind.ask;
    // the line that was read as "2 is evil"
    expect(read('湖中女神驗出2號是好人所以5號是壞人'), [(lady, 1, false), (suspect, 4, null)]);
    expect(read('我查驗了3號，他是壞人'), [(lady, 2, true)]);
    expect(read('女神查到4號是正義的，我比較懷疑6號'), [(lady, 3, false), (suspect, 5, null)]);
    expect(read('2號是好人，我懷疑5號'), [(trust, 1, null), (suspect, 4, null)]);
    expect(read('我相信2號，但5號很可疑'), [(trust, 1, null), (suspect, 4, null)]);
    expect(read('我覺得3號和5號都很可疑'), [(suspect, 2, null), (suspect, 4, null)]);
    expect(read('上次5號投贊成，很可疑'), [(suspect, 4, null)]);
    expect(read('3號，你為什麼反對？'), [(ask, 2, null)]);
    expect(read('5號是壞人，2號沒問題'), [(suspect, 4, null), (trust, 1, null)]);
    // the Lady word goes with the first player after it, not the rest
    expect(read('我驗了2號是好人，5號是壞人'), [(lady, 1, false), (suspect, 4, null)]);
    // a team vote alongside, only when the line is about this team
    final both = PlayerSpeech.parse('5號是壞人，這隊我反對', names, 0);
    expect(both.kind, suspect);
    expect(both.supportsTeam, isFalse);
    expect(PlayerSpeech.parse('我同意3號說的，5號可疑', names, 0).supportsTeam, isNull);
    // negations, questions and other people's words are not accusations
    expect(read('我不懷疑3號'), [(trust, 2, null)]);
    expect(read('我不覺得3號可疑'), [(trust, 2, null)]);
    expect(read('我不同意3號是壞人'), [(trust, 2, null)]);
    expect(read('我不相信3號是好人'), [(suspect, 2, null)]);
    expect(read('3號是壞人嗎？'), [(ask, 2, null)]);
    // ruling out one role says nothing about the side
    expect(PlayerSpeech.parse('3號不是刺客', names, 0).kind,
        PlayerSpeechKind.remark);
    expect(read('3號不是壞人'), [(trust, 2, null)]);
    expect(PlayerSpeech.parse('4號說3號是壞人', names, 0).kind,
        PlayerSpeechKind.remark);
    expect(PlayerSpeech.parse('有人認為3號有問題', names, 0).kind,
        PlayerSpeechKind.remark);
    // a Percival claim names Morgana only when the line does
    final claim = PlayerSpeech.parse('我是派西維爾，2號是梅林，4號是莫甘娜', names, 0);
    expect(claim.kind, PlayerSpeechKind.claimPercival);
    expect(claim.target, 3);
  });

  test('a Lady result the player saw is a claim; one they did not is not', () {
    fakeAsync((time) {
      var checked = 0;
      for (var seed = 0; seed < 200 && checked < 3; seed++) {
        final s = SoloGameSession(
            soloRoom(7, const ExpansionSettings(lady: true)),
            random: Random(seed),
            botDelay: const Duration(milliseconds: 1),
            speechDuration: const Duration(milliseconds: 1));
        var steps = 0;
        bool ready() =>
            s.phase == GamePhase.discussion &&
            s.speaker == 0 &&
            s.ladyChecks.any((c) => c.holder == 0);
        while (!ready() && s.phase != GamePhase.finished && steps++ < 3000) {
          if (s.phase == GamePhase.discussion && s.speaker == 0) {
            // not yet holding a result: pass this turn
            s.expressOpinion(true);
          } else if (s.hasPrivateInput) {
            switch (s.phase) {
              case GamePhase.identity:
                s.confirmIdentity(0);
              case GamePhase.team:
                s.proposeTeam(List.generate(s.requiredTeam, (i) => i));
              case GamePhase.vote:
                s.vote(0, true);
              case GamePhase.quest:
                s.playQuest(0, !s.evilNow(0)!);
              case GamePhase.lady:
                s.useLady([1, 2, 3, 4, 5, 6]
                    .firstWhere((t) => !s.ladyPast.contains(t)));
              case GamePhase.ladyResult:
                s.continueLady();
              case GamePhase.assassination:
                s.assassinate(1);
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
        if (!ready()) {
          s.dispose();
          continue;
        }
        checked++;
        final seen = s.ladyChecks.lastWhere((c) => c.holder == 0).target;
        final other = [1, 2, 3, 4, 5, 6].firstWhere(
            (t) => t != seen && !s.ladyChecks.any((c) => c.target == t));
        final before = s.statements.length;
        s.say(PlayerSpeech.parse(
            '湖中女神驗出${seen + 1}號是好人所以${other + 1}號是壞人', s.players, 0));
        final said = s.statements.sublist(before);
        expect(said, hasLength(2));
        expect(said[0].target, seen);
        expect(said[0].claimedEvil, isFalse);
        expect(said[0].certainty, DiscussionCertainty.certain);
        expect(said[0].continues, isFalse);
        expect(said[1].target, other);
        expect(said[1].position, DiscussionPosition.suspect);
        expect(said[1].continues, isTrue);
        // the player never checked [other]: calling that a Lady result
        // makes it only a word against them
        final again = s.statements.length;
        s.say(PlayerSpeech.parse('女神查到${other + 1}號是壞人', s.players, 0));
        final plain = s.statements[again];
        expect(plain.claimedEvil, isNull);
        expect(plain.position, DiscussionPosition.suspect);
        expect(plain.target, other);
        s.dispose();
      }
      expect(checked, greaterThan(0));
    });
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
        expect(accuse.text, contains('3號'));
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
