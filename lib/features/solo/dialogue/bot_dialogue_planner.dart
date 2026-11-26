import 'dart:math';
import '../../game/discussion_model.dart';
import '../bot_observation.dart';
import 'bot_catalog.dart';
import 'bot_contract.dart';
import 'bot_dialogue_context.dart';

class BotSpeechMemory {
  final _entries = <BotDialogueTrace>[];
  final _lines = <String>[];
  bool recentlySaid(String text) => _lines.contains(text);
  void rememberLine(String text) {
    _lines.add(text);
    if (_lines.length > 12) _lines.removeAt(0);
  }

  List<BotDialogueTrace> get entries => List.unmodifiable(_entries);
  void record(BotDialogueTrace entry) => _entries.add(entry);
  double penalty(String semanticKey, {String? ruleId}) {
    final proposals = _entries.map((e) => e.proposal).toSet().toList();
    final recent = proposals.reversed.take(2).toSet();
    if (_entries.any(
        (e) => recent.contains(e.proposal) && e.semanticKey == semanticKey)) {
      return 80;
    }
    // the same kind of remark again, only about someone else
    return ruleId != null &&
            _entries
                .any((e) => recent.contains(e.proposal) && e.ruleId == ruleId)
        ? 40
        : 0;
  }
}

/// No reflection/eval. Only registered predicates and finite placeholders can
/// produce text. The returned public statement has no private strategy fields.
class BotDialoguePlanner {
  BotDialoguePlanner(this.random, {BotDialogueCatalog? catalog})
      : catalog = catalog ?? BotDialogueCatalog.bundled;
  final Random random;
  final BotDialogueCatalog catalog;
  final memory = BotSpeechMemory();
  BotDialogueTrace? lastTrace;

  static String? render(String template, Map<String, String> bindings) {
    var valid = true;
    final result =
        template.replaceAllMapped(RegExp(r'\{\{([A-Za-z]+)\}\}'), (match) {
      final value = bindings[match[1]];
      if (value == null) valid = false;
      return value ?? '';
    });
    return valid && !result.contains('{{') && !result.contains('}}')
        ? result
        : null;
  }

  /// [cleared] and [condemned]: seats this (good) speaker is all but sure
  /// are good, or evil. He does not point at the first nor speak up for the
  /// second, whatever line would otherwise fit.
  DiscussionStatement speak(
      BotObservation o, bool approve, double Function(List<int>) risk,
      {int? chosenTarget,
      Set<int> cleared = const {},
      Set<int> condemned = const {}}) {
    final role = BotDialogueRole.forPlayer(o.role, o.evil);
    // What others already said about this proposal: never repeat a line,
    // and prefer a different kind of remark.
    final round = [
      for (final s in o.statements)
        if (s.quest == o.quest &&
            s.attempt == o.proposalId.attempt &&
            s.speaker != o.seat)
          s
    ];
    final saidLines = {for (final s in round) s.text};
    // ...and about the earlier proposals of this quest: the same remark
    // again one proposal later is still a repeat
    final heard = {
      for (final s in o.statements)
        if (s.generation == o.generation &&
            s.quest == o.quest &&
            s.attempt != o.proposalId.attempt &&
            s.speaker != o.seat)
          s.text
    };
    final saidIntents = <String, int>{};
    for (final s in round) {
      if (s.intent != null) {
        saidIntents.update(s.intent!, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final candidates = <(BotSpeechRule, BotDialogueContext, String, double)>[];
    for (final rule in catalog.rules) {
      if (rule.phase != o.phase ||
          (rule.role != BotDialogueRole.all && rule.role != role)) {
        continue;
      }
      if (rule.intent == BotSpeechIntent.supportTeam && !approve) continue;
      if (rule.intent == BotSpeechIntent.opposeTeam && approve) continue;
      final context = BotDialogueContext(
          o, approve, rule, risk, memory.entries.isNotEmpty,
          chosenTarget: chosenTarget);
      if (!context.matchesTrigger ||
          !rule.requires.every(context.predicate) ||
          !o.publicLedger.permitsAll(context.references)) {
        continue;
      }
      // Pointing at a member of the team one is about to back, or speaking
      // up for one of the team one is about to turn down, says the
      // opposite of the vote.
      if (context.target != null &&
          context.target != o.seat &&
          o.team.contains(context.target) &&
          (approve
              ? rule.intent == BotSpeechIntent.accuse ||
                  ['G04', 'RME02', 'RLS02', 'ROB05'].contains(rule.id)
              : rule.intent == BotSpeechIntent.defendOther)) {
        continue;
      }
      final aimed = context.target;
      if (aimed != null &&
          aimed != o.seat &&
          ((cleared.contains(aimed) &&
                  (rule.intent == BotSpeechIntent.accuse ||
                      ['G04', 'RME02', 'RLS02', 'ROB05'].contains(rule.id))) ||
              (condemned.contains(aimed) &&
                  rule.intent == BotSpeechIntent.defendOther))) {
        continue;
      }
      // Private facts can only be expressed as claims with a matching public
      // action by THIS holder. Otherwise only public-grounded opinions render.
      if (rule.policy == BotClaimPolicy.privateTruthClaim &&
          rule.id != 'G12' &&
          context.disclosure == null) {
        continue;
      }
      if (rule.policy == BotClaimPolicy.explicitPrivateClaimLie &&
          (!o.evil ||
              context.disclosure?.evil == null ||
              context.declaredAlignment == null)) {
        continue;
      }
      final lines = [
        for (final template in rule.templates)
          if (render(template, context.bindings) case final String text)
            if (!saidLines.any((said) => said.endsWith(text))) text
      ];
      if (lines.isEmpty) continue;
      // Someone already used this rule about this proposal: four people
      // saying the same thing in other words is still the same thing.
      final echoes = [
        for (final template in rule.templates)
          if (render(template, context.bindings) case final String text)
            if (saidLines.any((said) => said.endsWith(text))) text
      ].length;
      final key = '${rule.intent.name}/${context.target}/'
          '${context.references.where((r) => r.kind != BotEvidenceKind.proposal).map((r) => r.id).join(',')}';
      final score = rule.priority -
          memory.penalty(key, ruleId: rule.priority >= 85 ? null : rule.id) -
          (lines.every(memory.recentlySaid) ? 100 : 0) -
          12 * (saidIntents[rule.intent.name] ?? 0) -
          (rule.priority >= 85 ? 0 : 45 * echoes) -
          (rule.priority >= 85
              ? 0
              : 20 *
                  [
                    for (final template in rule.templates)
                      if (render(template, context.bindings)
                          case final String text)
                        if (heard.any((said) => said.endsWith(text))) text
                  ].length) +
          random.nextDouble() * 8 -
          4;
      candidates.add((rule, context, key, score));
    }
    candidates.sort((a, b) => b.$4.compareTo(a.$4));
    // Nothing left but a remark the table has just heard, or one this
    // seat keeps making: a plain word on the team is better than that.
    if (candidates.isEmpty || candidates.first.$4 < 0) {
      lastTrace = null;
      final alternatives = approve
          ? [
              '這隊我先贊成，回來再看結果。',
              '目前我願意讓這組試一次。',
              '這次我支持，但不替任何人的身分保證。',
              '我先過這隊，結果出來再調整。',
              '沒什麼要補充的，這隊我贊成。',
              '我的看法跟大家差不多，讓它出發吧。',
              '這組我沒意見，投贊成。',
            ]
          : [
              '這次我先反對，想再比較其他組合。',
              '目前這份名單我不放心，先換人吧。',
              '我還不想讓這隊出發，這票反對。',
              '這次我想再組一次，不會投贊成。',
              '大家講的我都聽了，這隊我還是不放心。',
              '這組我先不放，看看下一個隊長怎麼排。',
              '我沒有新的理由，但這隊我不想投贊成。',
            ];
      final fresh = alternatives
          .where((s) => !memory.recentlySaid(s) && !saidLines.contains(s))
          .toList();
      final choices = fresh.isEmpty ? alternatives : fresh;
      final text = choices[random.nextInt(choices.length)];
      memory.rememberLine(text);
      return DiscussionStatement(
          speaker: o.seat,
          quest: o.quest,
          generation: o.generation,
          attempt: o.proposalId.attempt,
          text: text,
          supportsTeam: approve,
          team: o.team,
          intent: 'opinion');
    }
    final (rule, context, semanticKey, _) = candidates.first;
    final lines = [
      for (final t in rule.templates)
        if (render(t, context.bindings) case final String text)
          if (!saidLines.any((said) => said.endsWith(text))) (t, text)
    ];
    final fresh = lines.where((line) => !memory.recentlySaid(line.$2)).toList();
    final choices = fresh.isEmpty ? lines : fresh;
    final (template, text) = choices[random.nextInt(choices.length)];
    memory.rememberLine(text);
    final trace = BotDialogueTrace(
        ruleId: rule.id,
        proposal: o.proposalId,
        intent: rule.intent,
        policy: rule.policy,
        plannedApprove: approve,
        publicEvidence: context.references,
        semanticKey: semanticKey);
    memory.record(trace);
    lastTrace = trace;
    final question = [
      BotSpeechIntent.questionTeam,
      BotSpeechIntent.challengeVote,
      BotSpeechIntent.challengeClaim
    ].contains(rule.intent);
    final publicTarget = switch (rule.intent) {
      BotSpeechIntent.defendSelf => o.seat,
      BotSpeechIntent.replyQuestion => context.target,
      BotSpeechIntent.interpretLady => context.social.supported
          ? context.social.target
          : context.disclosure?.target,
      BotSpeechIntent.discussSword =>
        rule.policy == BotClaimPolicy.privateTruthClaim
            ? context.disclosure?.target
            : context.q?.excaliburTarget,
      BotSpeechIntent.questionTeam => context.social.questionTo ??
          (template.contains('{{target}}') ? context.target : o.leader),
      BotSpeechIntent.accuse =>
        template.contains('{{target}}') || context.social.responseTo != null
            ? context.target
            : null,
      BotSpeechIntent.defendOther ||
      BotSpeechIntent.assassinate =>
        context.target,
      _ => template.contains('{{target}}') || question ? context.target : null,
    };
    final alignmentClaim = ['XLD01', 'XLD02', 'XLD03'].contains(rule.id) &&
        context.disclosure?.evil != null;
    final declaresPosition = [
          BotSpeechIntent.supportTeam,
          BotSpeechIntent.opposeTeam,
          BotSpeechIntent.warnFifthVote
        ].contains(rule.intent) ||
        rule.id == 'REV05';
    final position = publicTarget == null
        ? null
        : rule.intent == BotSpeechIntent.defendOther
            ? DiscussionPosition.defend
            : rule.intent == BotSpeechIntent.accuse ||
                    (['G04', 'RME02', 'RLS02', 'ROB05'].contains(rule.id) &&
                        template.contains('{{target}}'))
                ? DiscussionPosition.suspect
                : null;
    final original = rule.id == 'G12'
        ? true
        : rule.policy == BotClaimPolicy.privateTruthClaim &&
                rule.intent == BotSpeechIntent.discussSword
            ? context.disclosure?.originalCard
            : null;
    return DiscussionStatement(
        speaker: o.seat,
        quest: rule.intent == BotSpeechIntent.assassinate
            ? o.activeQuest
            : o.quest,
        generation: o.generation,
        attempt: rule.intent == BotSpeechIntent.assassinate
            ? null
            : o.proposalId.attempt,
        text: text,
        supportsTeam: declaresPosition ? approve : null,
        team: o.team,
        intent: rule.intent.name,
        target: publicTarget,
        position: position,
        certainty: original != null || alignmentClaim
            ? DiscussionCertainty.certain
            : DiscussionCertainty.tentative,
        questionTo: question
            ? context.social.questionTo ?? publicTarget ?? o.leader
            : null,
        replyTo: context.social.responseTo ??
            (rule.intent == BotSpeechIntent.replyQuestion
                ? context.questionIndex
                : null),
        claimedEvil: alignmentClaim ? context.declaredAlignment : null,
        switched: alignmentClaim ? context.disclosure!.switched : o.switched,
        claimedOriginalSuccess: original,
        originalCardQuest: original == null ? null : context.referenceQuest,
        evidenceIds: context.references.map((r) => r.id).toList());
  }
}
