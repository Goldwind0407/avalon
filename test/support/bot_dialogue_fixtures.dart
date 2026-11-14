import 'dart:convert';
import 'dart:math';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_catalog.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_dialogue_planner.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/generated/bot_dialogue_data.dart';

BotObservation observe({
  Role role = Role.loyal,
  bool evil = false,
  int generation = 4,
  int count = 7,
  int seat = 0,
  int leader = 1,
  int rejections = 0,
  GamePhase phase = GamePhase.discussion,
  bool switched = false,
  ExpansionSettings expansions = const ExpansionSettings(),
  List<int> team = const [0, 1, 2],
  List<int> visible = const [],
  List<QuestResult> history = const [],
  List<ProposalRecord> proposals = const [],
  List<LadyCheck> ladyChecks = const [],
  List<BotFact> facts = const [],
  List<DiscussionStatement> statements = const [],
  List<bool?> loyalty = const [],
  Map<int, bool> ownCards = const {},
  bool? plannedQuestSuccess,
  Set<Role>? configuredRoles,
  int? excaliburHolder,
}) =>
    BotObservation(
        seat: seat,
        role: role,
        evil: evil,
        count: count,
        leader: leader,
        quest: history.length + 1,
        rejections: rejections,
        failsRequired: count >= 7 && history.length == 3 ? 2 : 1,
        expansions: expansions,
        switched: switched,
        visible: visible,
        team: team,
        history: history,
        proposals: proposals,
        ladyPast: const [0],
        facts: facts,
        statements: statements,
        ownCards: ownCards,
        plannedQuestSuccess: plannedQuestSuccess,
        configuredRoles: configuredRoles,
        excaliburHolder: excaliburHolder,
        generation: generation,
        phase: phase,
        ladyChecks: ladyChecks,
        loyalty: loyalty,
        names: List.generate(count, (i) => i == 2 ? '小明' : '玩家${i + 1}'));

Map<String, dynamic> sourceRule(String id) =>
    Map<String, dynamic>.from((jsonDecode(botDialogueData)['rules'] as List)
        .firstWhere((r) => r['id'] == id));

BotDialogueCatalog catalogOf(List<Map<String, dynamic>> rules) =>
    BotDialogueCatalog.parse(jsonEncode({'schemaVersion': 1, 'rules': rules}));

BotDialoguePlanner plannerFor(String id,
        {Map<String, dynamic> overrides = const {}}) =>
    BotDialoguePlanner(Random(1),
        catalog: catalogOf([
          {...sourceRule(id), ...overrides}
        ]));

DiscussionStatement say(BotDialoguePlanner planner, BotObservation o,
        {bool approve = true}) =>
    planner.speak(o, approve, (team) => .3);

ProposalRecord proposal(int attempt, List<bool> votes, {int quest = 1}) =>
    ProposalRecord(
        quest: quest,
        attempt: attempt,
        leader: 1,
        team: [0, 1, 2],
        votes: votes);
