import '../../game/discussion_model.dart';
import '../../game/game_model.dart';
import '../bot_observation.dart';
import 'bot_catalog.dart';
import 'bot_contract.dart';
import 'bot_social_context.dart';

/// All bindings are selected from a public event or an authorized disclosure.
/// Role hints may affect selection, but never become arbitrary template values.
class BotDialogueContext {
  BotDialogueContext(
      this.o, this.approve, this.rule, this.risk, this.hasSpeechMemory,
      {int? chosenTarget}) {
    final needsSelf = ['G11', 'G12', 'G13', 'RLS03', 'REV03', 'ROB03', 'RLE06']
        .contains(rule.id);
    final quests = [for (var i = 0; i < o.history.length; i++) i]..sort((a, b) {
        double score(int index) {
          final q = o.history[index];
          return q.team.where(o.team.contains).length * 2 + index * .1;
        }

        return score(b).compareTo(score(a));
      });
    for (final index in quests) {
      final q = o.history[index];
      if (needsSelf && !q.team.contains(o.seat)) continue;
      if (rule.id == 'G14' &&
          (!q.succeeded || q.fails == 0 || q.excaliburTarget != null)) {
        continue;
      }
      if (rule.id == 'G15' && (!q.succeeded || q.fails != 0)) continue;
      if (['G11', 'G13', 'G24', 'REV03', 'ROB03', 'RLE06'].contains(rule.id) &&
          q.succeeded) {
        continue;
      }
      if (rule.id == 'XQT01' && !(o.count >= 7 && index == 3 && q.fails == 1)) {
        continue;
      }
      if (rule.id.startsWith('XSW') && q.excaliburTarget == null) continue;
      referenceQuest = index + 1;
      break;
    }
    final candidates = o.team
        .where((s) =>
            s != o.seat &&
            o.history.any((q) => q.fails > 0 && q.team.contains(s)))
        .toList();
    candidates.sort((a, b) => o.history
        .where((q) => q.fails > 0 && q.team.contains(b))
        .length
        .compareTo(
            o.history.where((q) => q.fails > 0 && q.team.contains(a)).length));
    if (candidates.isNotEmpty) target = candidates.first;
    if (o.proposals.isNotEmpty) previous = o.proposals.last;
    if (previous != null) {
      removed = previous!.team.where((s) => !o.team.contains(s)).toList();
      added = o.team.where((s) => !previous!.team.contains(s)).toList();
      reused = previous!.team.where(o.team.contains).toList();
    }
    if (rule.id == 'G08' && o.history.isNotEmpty) {
      reused = o.history.last.team.where(o.team.contains).toList();
    }
    if (['G08', 'G09', 'RLS03'].contains(rule.id) && o.history.isNotEmpty) {
      referenceQuest = o.history.length;
    }
    if (['G02', 'G10', 'RLS05'].contains(rule.id) && previous != null) {
      _references.add(BotEvidenceId(o.generation, BotEvidenceKind.proposal,
          'q${previous!.quest}/a${previous!.attempt}'));
    }
    final factCandidates = o.facts
        .where((f) =>
            rule.id.startsWith('XSW') ? f.originalCard != null : f.evil != null)
        .toList();
    for (final fact in factCandidates.reversed) {
      final kind = fact.evil != null
          ? BotEvidenceKind.ladyUse
          : BotEvidenceKind.swordUse;
      final proof = o.publicLedger.events.where((e) =>
          e.id.kind == kind &&
          e.actor == o.seat &&
          e.target == fact.target &&
          e.quest == fact.quest);
      if (proof.isNotEmpty) {
        disclosure = fact;
        if (rule.policy == BotClaimPolicy.privateTruthClaim ||
            rule.policy == BotClaimPolicy.explicitPrivateClaimLie) {
          target = fact.target;
          referenceQuest = fact.quest;
          _references.add(proof.first.id);
        }
        break;
      }
    }
    for (final (index, s) in o.statements.indexed) {
      if (s.speaker == o.seat &&
          disclosure != null &&
          s.target == disclosure!.target &&
          s.claimedEvil != null &&
          s.switched == disclosure!.switched) {
        declaredAlignment = s.claimedEvil;
      }
      if (s.questionTo == o.seat &&
          s.quest == o.quest &&
          s.attempt == o.proposalId.attempt &&
          !o.statements.any((r) => r.speaker == o.seat && r.replyTo == index)) {
        questionIndex = index;
      }
    }
    social = BotSocialContext(o, rule.id, approve, chosenTarget: chosenTarget);
    if (social.supported) {
      target = social.target;
      referenceQuest = social.referenceQuest;
      _references.addAll(social.references);
    }
    if (rule.id == 'G16') _selectVoteComparison();
    if (rule.intent == BotSpeechIntent.replyQuestion && questionIndex != null) {
      final question = o.statements[questionIndex!];
      target = question.speaker;
      referenceQuest = null;
      final event = o.publicLedger.events
          .firstWhere((e) => e.statementIndex == questionIndex);
      _references.add(event.id);
      for (final id in question.evidenceIds) {
        final refs = o.publicLedger.events.where(
            (e) => e.id.id == id && e.id.kind == BotEvidenceKind.proposal);
        if (refs.isNotEmpty) referencedProposal = refs.first;
      }
    }
    if (target != null && ['G04', 'RME02'].contains(rule.id)) {
      final matches = quests.where(
          (i) => o.history[i].fails > 0 && o.history[i].team.contains(target));
      if (matches.isNotEmpty) referenceQuest = matches.first + 1;
    }
    if (referenceQuest != null) {
      final refs = o.publicLedger.events.where((e) =>
          e.id.kind == BotEvidenceKind.quest && e.quest == referenceQuest);
      if (refs.isNotEmpty) _references.add(refs.first.id);
    }
    final current = o.publicLedger.events.where((e) =>
        e.id.kind == BotEvidenceKind.proposal &&
        e.quest == o.proposalId.quest &&
        e.attempt == o.proposalId.attempt);
    if (current.isNotEmpty) _references.add(current.first.id);
  }
  final BotObservation o;
  final bool approve, hasSpeechMemory;
  final BotSpeechRule rule;
  final double Function(List<int>) risk;
  late final BotSocialContext social;
  int? target, referenceQuest, questionIndex;
  ProposalRecord? previous;
  BotPublicEvidence? referencedProposal;
  BotFact? disclosure;
  bool? declaredAlignment;
  List<int> removed = const [], added = const [], reused = const [];
  final _references = <BotEvidenceId>{};
  List<BotEvidenceId> get references => List.unmodifiable(_references);
  QuestResult? get q =>
      referenceQuest == null ? null : o.history[referenceQuest! - 1];
  bool get publicTarget =>
      target != null &&
      o.history.any((q) => q.fails > 0 && q.team.contains(target));
  bool get hasSwitch => o.publicLedger.events.any(
      (e) => e.id.kind == BotEvidenceKind.loyalty && e.switchOccurred == true);
  bool get privateKnownEvilOnTeam =>
      o.team.any((s) => o.visible.contains(s)) &&
      (o.role == Role.merlin ||
          (o.role.isEvil &&
              o.role != Role.oberon &&
              o.role != Role.lancelotEvil)) &&
      !o.switched;

  void _selectVoteComparison() {
    for (var i = o.proposals.length - 1; i > 0; i--) {
      final newer = o.proposals[i], older = o.proposals[i - 1];
      if (newer.team.length != older.team.length ||
          newer.team.where(older.team.contains).length <
              newer.team.length - 1) {
        continue;
      }
      for (var s = 0; s < o.count; s++) {
        if (s == o.seat || !older.votes[s] || newer.votes[s]) continue;
        target = s;
        referencedProposal = o.publicLedger.events.firstWhere((e) =>
            e.id.kind == BotEvidenceKind.ballot &&
            e.quest == newer.quest &&
            e.attempt == newer.attempt);
        for (final p in [older, newer]) {
          _references.add(BotEvidenceId(o.generation, BotEvidenceKind.ballot,
              'q${p.quest}/a${p.attempt}'));
        }
        return;
      }
    }
  }

  /// Finite registered predicates. Unknown fields are false, never interpreted
  /// as code or treated as an optional successful check.
  bool predicate(String key) => _evaluatePredicate(key) ?? false;
  bool get hasRegisteredGuards =>
      _evaluateTrigger != null &&
      rule.requires.every((key) => _evaluatePredicate(key) != null);
  bool? _evaluatePredicate(String key) =>
      social.flags[key] ??
      switch (key) {
        'cachedVote=approve' => approve,
        'cachedVote=reject' => !approve,
        'alignment=good' || 'currentAlignment=good' => !o.evil,
        'alignment=evil' || 'currentAlignment=evil' => o.evil,
        'rejections=4' => o.rejections == 4,
        'phase=discussion' => o.phase == GamePhase.discussion,
        'phase=assassination' => o.phase == GamePhase.assassination,
        'assassinAuthorized' => o.role == Role.assassin,
        'isLeader' => o.leader == o.seat,
        'onProposedTeam' => o.team.contains(o.seat),
        'teamComparisonAvailable' =>
          previous != null && risk(o.team) < risk(previous!.team),
        'previousQuestExists' => o.history.isNotEmpty,
        'previousQuestFailed' =>
          o.history.isNotEmpty && !o.history.last.succeeded,
        'publicOwnPriorApprove' => referenceQuest == o.history.length &&
            o.proposals.any((p) =>
                p.quest == referenceQuest && p.approved && p.votes[o.seat]),
        'teamChangedSubstantially' => o.history.isNotEmpty &&
            o.team.where((s) => !o.history.last.team.contains(s)).length >
                o.team.length / 2,
        'reusedMemberExists' => o.history.isNotEmpty &&
            o.history.last.succeeded &&
            o.team.any(o.history.last.team.contains),
        'oneSeatChanged' ||
        'publicOldAndNew' =>
          added.length == 1 && removed.length == 1,
        'newMemberAdded' => added.isNotEmpty,
        'selfWasOnFailQuest' =>
          q != null && !q!.succeeded && q!.team.contains(o.seat),
        'publicOtherTeammateExists' =>
          q != null && q!.team.any((s) => s != o.seat),
        'publicRepeatedFailOverlap' => target != null &&
            o.history
                    .where((result) =>
                        result.fails > 0 && result.team.contains(target))
                    .length >=
                2,
        'teamOverlapHigh' => q != null &&
            q!.team.where(o.team.contains).length >= (o.team.length / 2).ceil(),
        'publicQuestReference' || 'publicPriorQuestReference' => q != null,
        'selfQuestOriginal=success' =>
          referenceQuest != null && o.ownCards[referenceQuest] == true,
        'ownCardNotFlipped' => q != null && q!.excaliburTarget != o.seat,
        'questCompleted' => q != null,
        'publicFailCount>0' => q != null && q!.fails > 0,
        'publicFailCount=0' => q != null && q!.fails == 0 && q!.succeeded,
        'publicFailCount=1' => q != null && q!.fails == 1,
        'questFailThreshold=2' => referenceQuest == 4 && o.count >= 7,
        'publicVoteHistory' => o.proposals.length >= 2,
        'similarProposal' ||
        'publicTargetVoteChanged' =>
          rule.id == 'G16' && referencedProposal != null,
        'publicEvidenceForTarget' => publicTarget,
        'publicDirectQuestionToSelf' ||
        'publicQuestionToSelf' =>
          questionIndex != null,
        'publicEventReferenceOptional' => true,
        'speechMemory' => hasSpeechMemory,
        'recentSemanticRepeat' => o.statements.length >= 2 &&
            o.statements.reversed
                    .take(4)
                    .where((s) =>
                        s.intent != null &&
                        s.intent == o.statements.last.intent &&
                        s.target == o.statements.last.target)
                    .length >=
                2,
        'goodQuestWins=2' => o.successes == 2,
        'evilQuestWins=2' => o.failures == 2,
        'goodQuestWins=2 or evilQuestWins=2' =>
          o.successes == 2 || o.failures == 2,
        'privateKnownEvilOnTeam' => privateKnownEvilOnTeam,
        'noSafePublicEvidence' => !publicTarget,
        'privateEstimatedSafeTeam' => risk(o.team) < .5,
        'privateMerlinCandidateCount=2' =>
          o.role == Role.percival && o.visible.length == 2,
        'privateMerlinCandidateCount=1' =>
          o.role == Role.percival && o.visible.length == 1,
        'privateBothCandidatesOnTeam' =>
          o.visible.length == 2 && o.visible.every(o.team.contains),
        'assassinThreatRelevant' => true,
        'candidateMerlinUncertain' => o.role == Role.assassin,
        'noPrivateEvilTeammateList' => o.visible.isEmpty,
        'candidateTeamHasUnknownMembers' =>
          o.team.any((s) => s != o.seat && !o.visible.contains(s)),
        'publicLancelotModeEnabled' => o.expansions.lancelot > 0,
        'publicLancelotSwitchEvent' || 'publicSwitchEvent' => hasSwitch,
        'mustFail=true' => o.mustFail,
        'publicSwordUsed' => q?.excaliburTarget != null,
        'selfNotPrivatelySawTargetOriginal' => q?.excaliburTarget != null &&
            q!.excaliburHolder != o.seat &&
            q!.excaliburTarget != o.seat,
        'selfWasSwordHolder' => disclosure?.originalCard != null,
        'selfSawOriginalCard=fail' => disclosure?.originalCard == false,
        'selfSawOriginalCard=success' => disclosure?.originalCard == true,
        'publicDisclosureChosen' =>
          rule.policy == BotClaimPolicy.privateTruthClaim && disclosure != null,
        'selfLadyInspected' => disclosure?.evil != null,
        'inspectedValue=good' => disclosure?.evil == false,
        'inspectedValue=evil' => disclosure?.evil == true,
        'publicClaimMode=truth' =>
          disclosure?.evil != null && declaredAlignment == disclosure!.evil,
        'publicClaimMode=lie' => disclosure?.evil != null &&
            declaredAlignment != null &&
            declaredAlignment != disclosure!.evil,
        'ambiguousFailAttribution' =>
          q != null && q!.fails > 0 && q!.team.length > 1,
        _ => null,
      };

  /// Prose trigger conditions omitted from draft prerequisite lists must also
  /// be enforced. Explicit allowlist: unimplemented scenarios stay disabled.
  bool get matchesTrigger => _evaluateTrigger ?? false;
  bool? get _evaluateTrigger => social.supported
      ? social.matches
      : switch (rule.id) {
          'G01' || 'RLS01' || 'ROB01' => o.quest == 1 && o.history.isEmpty,
          'G02' => true,
          'G03' => o.history.isEmpty,
          'G04' => !approve && publicTarget,
          'G05' => !approve && !publicTarget,
          'G06' ||
          'G07' ||
          'G09' ||
          'G10' ||
          'G11' ||
          'G12' ||
          'G13' ||
          'G16' ||
          'G17' ||
          'G22' ||
          'G24' ||
          'RLS02' ||
          'RME01' ||
          'RME02' ||
          'RME03' ||
          'RME07' ||
          'RPC01' ||
          'RPC03' ||
          'RPC06' ||
          'REV03' ||
          'REV06' ||
          'RAS07' ||
          'RMG03' ||
          'RMD02' ||
          'RMD06' ||
          'RLG01' ||
          'RLG03' ||
          'RLG06' ||
          'RLE01' ||
          'RLE02' ||
          'RLE04' ||
          'XLD01' ||
          'XLD02' ||
          'XLD03' ||
          'XSW01' ||
          'XSW02' ||
          'XSW03' ||
          'XLC01' ||
          'XQT01' ||
          'XQT02' =>
            true,
          'G08' => o.history.isNotEmpty && o.history.last.succeeded,
          'G14' => q != null &&
              q!.succeeded &&
              q!.fails > 0 &&
              q!.excaliburTarget == null,
          'G15' => q != null && q!.succeeded && q!.fails == 0,
          'G20' => hasSpeechMemory,
          'RLS03' => q != null && !q!.succeeded,
          'RMG01' || 'RMD01' || 'ROB02' => o.quest == 1,
          'ROB07' => !approve && publicTarget,
          _ => null,
        };

  Map<String, String> get bindings {
    String label(int s) => playerLabel(s, o.names[s]);
    final values = <String, String>{
      if (target != null) 'target': label(target!),
      if (q != null) 'quest': '$referenceQuest',
      if (q != null) 'fails': '${q!.fails}',
      if (q != null)
        'otherMembers': q!.team.where((s) => s != o.seat).map(label).join('、'),
      if (referencedProposal?.attempt != null)
        'attempt': '${referencedProposal!.attempt}',
      if (rule.id == 'RLS05' && reused.isNotEmpty)
        'oldMember': reused.map(label).join('、')
      else if (removed.length == 1)
        'oldMember': label(removed.single),
      if (added.length == 1) 'newMember': label(added.single),
      if (reused.isNotEmpty) 'reusedMembers': reused.map(label).join('、'),
      if (declaredAlignment != null && disclosure?.evil != null)
        'claimedAlignment': declaredAlignment! ? '邪惡陣營' : '正義陣營',
      if (social.defender != null) 'defender': label(social.defender!),
      if (social.claimant != null) 'claimant': label(social.claimant!),
    };
    return Map.unmodifiable(values);
  }
}
