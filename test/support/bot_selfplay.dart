import 'dart:math';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/role_presets.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/bot_style.dart';
import 'package:avalon_shadow_council/features/solo/bot_vote_plan.dart';

/// What the bots did over many all-bot games (base game, no speeches).
/// Used to check that strategy changes keep play plausible.
class SelfPlayStats {
  SelfPlayStats(this.players, this.games);
  final int players, games;
  int goodWins = 0, evilByFails = 0, evilByRejections = 0, evilByStab = 0;
  int stabs = 0, quests = 0, proposals = 0;
  int firstProposals = 0, firstRejected = 0;
  int hammers = 0, hammerEvilRejects = 0;
  int evilLeads = 0, evilLeadsStacked = 0;
  int evilVotesOnClean = 0, evilApprovesClean = 0;
  int merlinVotes = 0, merlinTellingVotes = 0;
  int uselessLoneFails = 0;
  int certainCases = 0, certainMissed = 0;
  int utterances = 0, directResponses = 0, revisedVotes = 0;

  static String _pc(int a, int b) =>
      b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(0)}%';
  double get goodWinRate => goodWins / games;
  double get stabRate => stabs == 0 ? 0 : evilByStab / stabs;
  double get proposalsPerQuest => proposals / quests;

  @override
  String toString() => '''
== $players players, $games games
 good wins ${_pc(goodWins, games)} | evil: 3 fails ${_pc(evilByFails, games)}, 5 rejections ${_pc(evilByRejections, games)}, assassination ${_pc(evilByStab, games)}
 assassin hits Merlin ${_pc(evilByStab, stabs)} of $stabs (a random guess: ${_pc(1, players - Room.evilCount(players))})
 proposals per quest ${proposalsPerQuest.toStringAsFixed(2)} | first proposal rejected ${_pc(firstRejected, firstProposals)} | fifth proposal reached $hammers times
 evil rejects on the fifth proposal ${_pc(hammerEvilRejects, hammers)} | evil leader stacks 2+ evil ${_pc(evilLeadsStacked, evilLeads)}
 evil approves a clean team ${_pc(evilApprovesClean, evilVotesOnClean)} | Merlin's vote gives away what he sees ${_pc(merlinTellingVotes, merlinVotes)}
 lone useless Fail on two-Fail quests $uselessLoneFails | good unsure about the partner on a failed pair ${_pc(certainMissed, certainCases)} of $certainCases''';
}

/// [good] and [evil] set the level of the seats dealt to each side, so one
/// side's skill can be measured against the other's. [roles] replaces the
/// recommended special roles for [n] players.
SelfPlayStats selfPlay(int n, int games,
    {BotDifficulty good = BotDifficulty.normal,
    BotDifficulty evil = BotDifficulty.normal,
    Set<Role>? roles,
    bool withDiscussion = false,
    StringSink? transcript}) {
  final stats = SelfPlayStats(n, games);
  for (var g = 0; g < games; g++) {
    final rng = Random(g * 31 + n);
    final room = Room(
        code: '',
        players: List.generate(
            n, (i) => Player(id: '$i', name: 'P$i', isReady: true)))
      ..specialRoles.addAll([for (final r in roles ?? rolePreset(n)!) r.label])
      ..expansions = const ExpansionSettings();
    final game = AvalonGame(room, random: rng);
    final styles = BotStyle.deal(n, rng);
    final brains = [
      for (var i = 0; i < n; i++)
        BotBrain(Random(rng.nextInt(1 << 30)),
            style: styles[i], difficulty: game.roles[i].isEvil ? evil : good)
    ];
    final own = [for (var i = 0; i < n; i++) <int, bool>{}];
    final statements = <DiscussionStatement>[];
    for (var i = 0; i < n; i++) {
      game.confirmIdentity();
    }
    transcript?.writeln('===== 第 ${g + 1} 局：${[
      for (var i = 0; i < n; i++)
        '${i + 1}號${game.roles[i].label}(${styles[i].label})'
    ].join(' ')}');
    BotObservation see(int s, GamePhase phase) => BotObservation(
        seat: s,
        role: game.roles[s],
        evil: game.evilNow(s),
        count: n,
        leader: game.leader,
        quest: game.questNumber,
        rejections: game.rejections,
        failsRequired: game.failsRequired,
        expansions: game.expansions,
        switched: false,
        visible: visibleSeats(game.roles, s),
        team: game.team,
        history: game.history,
        proposals: game.proposals,
        ladyPast: const [],
        facts: const [],
        statements: statements,
        ownCards: own[s],
        phase: phase);
    bool isEvil(int s) => game.roles[s].isEvil;
    final merlin = game.roles.indexOf(Role.merlin);
    var guard = 0;
    while (game.phase != GamePhase.finished) {
      if (guard++ > 500) throw StateError('game does not end');
      switch (game.phase) {
        case GamePhase.team:
          final l = game.leader;
          final team =
              brains[l].chooseTeam(see(l, GamePhase.team), game.requiredTeam);
          if (isEvil(l)) {
            stats.evilLeads++;
            if (team.where(isEvil).length >= 2) stats.evilLeadsStacked++;
          }
          game.proposeTeam(team);
          transcript?.writeln(
              '-- 第${game.questNumber}次遠征 提案${game.rejections + 1}：${l + 1}號帶 ${team.map((s) => s + 1).join('、')}');
        case GamePhase.vote:
          final dirty = game.team.any(isEvil);
          final seen =
              game.team.any((s) => isEvil(s) && game.roles[s] != Role.mordred);
          final votes = <bool>[];
          if (withDiscussion) {
            final plans = [
              for (var s = 0; s < n; s++) BotVotePlan(rng.nextInt(1 << 30))
            ];
            for (var s = 0; s < n; s++) {
              plans[s].evaluate(brains[s], see(s, GamePhase.discussion));
            }
            for (var offset = 1; offset <= n; offset++) {
              final s = (game.leader + offset) % n;
              final view = see(s, GamePhase.discussion);
              final decision = plans[s].evaluate(brains[s], view);
              final statement = brains[s].speech(view, decision.approve);
              statements.add(statement);
              transcript?.writeln(
                  '   ${s + 1}號[${brains[s].lastSpeechSource?.label}]：${statement.text}');
              stats.utterances++;
              if (statement.replyTo != null) stats.directResponses++;
            }
            // Simultaneous final views: never expose submitted ballots.
            for (var s = 0; s < n; s++) {
              final finalVote = plans[s]
                  .evaluate(brains[s], see(s, GamePhase.vote), lock: true);
              votes.add(finalVote.approve);
              if (finalVote.approve != plans[s].initial!.approve) {
                stats.revisedVotes++;
              }
            }
          } else {
            for (var s = 0; s < n; s++) {
              votes.add(brains[s].vote(see(s, GamePhase.vote)));
            }
          }
          stats.proposals++;
          final first = game.rejections == 0;
          if (first) stats.firstProposals++;
          if (game.rejections == 4) {
            stats.hammers++;
            if ([for (var s = 0; s < n; s++) s]
                .any((s) => isEvil(s) && !votes[s])) {
              stats.hammerEvilRejects++;
            }
          } else {
            stats.merlinVotes++;
            if (votes[merlin] == !seen) stats.merlinTellingVotes++;
            if (!dirty) {
              for (var s = 0; s < n; s++) {
                if (!isEvil(s)) continue;
                stats.evilVotesOnClean++;
                if (votes[s]) stats.evilApprovesClean++;
              }
            }
          }
          for (final v in votes) {
            game.vote(v);
          }
          transcript?.writeln('   票：${[
            for (var s = 0; s < n; s++) '${s + 1}${votes[s] ? '○' : '✕'}'
          ].join(' ')}');
          if (first && !game.teamApproved) stats.firstRejected++;
          game.continueVote();
        case GamePhase.quest:
          final q = game.questNumber, team = [...game.team];
          final needed = game.failsRequired;
          var fails = 0;
          while (game.phase == GamePhase.quest) {
            final s = game.questActor;
            final card = brains[s].questCard(see(s, GamePhase.quest));
            own[s][q] = card;
            if (!card) fails++;
            game.playQuest(card);
          }
          stats.quests++;
          if (needed == 2 && fails == 1) stats.uselessLoneFails++;
          transcript
              ?.writeln('   >> 任務${fails >= needed ? '失敗' : '成功'}，$fails 張失敗牌');
          game.continueQuest();
          // a good player on a failed pair knows the partner is evil
          if (team.length == 2 && fails == 1 && game.phase == GamePhase.team) {
            for (final s in team.where((s) => !isEvil(s))) {
              stats.certainCases++;
              final partner = team.firstWhere((x) => x != s);
              if (brains[s].suspicion(see(s, GamePhase.team))[partner] < .95) {
                stats.certainMissed++;
              }
            }
          }
        case GamePhase.assassination:
          final a = game.roles.indexOf(Role.assassin);
          stats.stabs++;
          game.assassinate(
              brains[a].assassinate(see(a, GamePhase.assassination)));
          if (game.winner == '邪惡') stats.evilByStab++;
        default:
          throw StateError('unexpected ${game.phase}');
      }
    }
    if (game.winner == '正義') {
      stats.goodWins++;
    } else if (game.result.contains('五次')) {
      stats.evilByRejections++;
    } else if (game.result.contains('三次任務失敗')) {
      stats.evilByFails++;
    }
  }
  return stats;
}
