import 'dart:math';
import '../../game/discussion_model.dart';
import '../bot_observation.dart';
import 'bot_catalog.dart';
import 'bot_contract.dart';
import 'bot_dialogue_context.dart';

class BotSpeechMemory {
  final _entries = <BotDialogueTrace>[];
  List<BotDialogueTrace> get entries => List.unmodifiable(_entries);
  void record(BotDialogueTrace entry) => _entries.add(entry);
  double penalty(String semanticKey) {
    final proposals = _entries.map((e) => e.proposal).toSet().toList();
    final recent = proposals.reversed.take(2).toSet();
    return _entries.any(
            (e) => recent.contains(e.proposal) && e.semanticKey == semanticKey)
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

  DiscussionStatement speak(
      BotObservation o, bool approve, double Function(List<int>) risk,
      {int? chosenTarget}) {
    final role = BotDialogueRole.forPlayer(o.role, o.evil);
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
          if (render(template, context.bindings) case final String text) text
      ];
      if (lines.isEmpty) continue;
      final key =
          '${rule.intent.name}/${context.referenceQuest}/${context.target}';
      final score =
          rule.priority - memory.penalty(key) + random.nextDouble() * 8 - 4;
      candidates.add((rule, context, key, score));
    }
    if (candidates.isEmpty) {
      lastTrace = null;
      return DiscussionStatement(
          speaker: o.seat,
          quest: o.quest,
          generation: o.generation,
          attempt: o.proposalId.attempt,
          text: approve ? '我會支持這次提案，先看接下來的結果。' : '這次我先投反對，希望再比較其他組合。',
          supportsTeam: approve,
          team: o.team,
          intent: 'opinion');
    }
    candidates.sort((a, b) => b.$4.compareTo(a.$4));
    final (rule, context, semanticKey, _) = candidates.first;
    final lines = [
      for (final t in rule.templates)
        if (render(t, context.bindings) case final String text) (t, text)
    ];
    final (template, text) = lines[random.nextInt(lines.length)];
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
        (rule.id == 'REV05' && template.contains('不會直接跟'));
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
