import '../../game/discussion_model.dart';
import '../../game/game_model.dart';
import '../bot_observation.dart';
import 'bot_contract.dart';
import 'bot_conversation.dart';

/// Resolves a social scenario to concrete public speakers/events. Private
/// opening hints may guide selection; they never become public template values.
class BotSocialContext {
  BotSocialContext(this.o, this.id, this.approve, {int? chosenTarget})
      : conversation = BotConversation(
            ledger: o.publicLedger,
            statements: o.statements,
            history: o.history,
            quest: o.quest,
            attempt: o.proposalId.attempt) {
    if (!supported) return;
    final c = conversation;
    final accusations =
        c.accusations.where((e) => e.statement.speaker != o.seat).toList();
    PublicUtterance? accusation;
    if (['RMG05', 'RMD04', 'ROB03', 'RLG05', 'RLE06'].contains(id)) {
      accusation =
          c.latest(accusations.where((e) => e.statement.target == o.seat));
    } else if (id == 'RPC02') {
      accusation = c.latest(
          accusations.where((e) => o.visible.contains(e.statement.target)));
    } else if (['REV02', 'RAS04'].contains(id)) {
      accusation =
          c.latest(accusations.where((e) => knownEvil(e.statement.target!)));
    } else if (id == 'RME04') {
      accusation = c.latest(accusations.where((e) =>
          knownEvil(e.statement.target!) &&
          questFrom(e, e.statement.target!) != null));
    } else {
      accusation = c.latest(accusations);
    }
    final selfEndorsement = c.latest(c.endorsements.where(
        (e) => e.statement.speaker != o.seat && e.statement.target == o.seat));
    final questions = c.recent.where((e) =>
        e.statement.questionTo == o.seat &&
        !o.statements.any((s) => s.speaker == o.seat && s.replyTo == e.index));
    final question = c.latest(questions);
    final confident = c.latest(c.recent.where((e) =>
        e.statement.speaker != o.seat &&
        e.statement.quotedFrom == null &&
        e.statement.target != null &&
        e.statement.certainty != DiscussionCertainty.tentative));
    final strong = c.latest(accusations.where((e) =>
        e.statement.certainty != DiscussionCertainty.tentative &&
        !c.hasPublicGrounds(e)));
    final influence = c.influentialSeat(o.seat);
    final contradiction = c.contradictoryClaims(
        ladyOnly: id == 'XLD04',
        speakers: id == 'RPC07' ? o.visible.toSet() : null);
    final oldUses = o.publicLedger.events
        .where((e) =>
            e.id.kind == BotEvidenceKind.ladyUse &&
            c.alignmentMayDifferSince(e.quest))
        .toList();
    final oldUse = oldUses.isEmpty ? null : oldUses.last;
    final ladyClaims = c.all
        .where((e) =>
            e.statement.claimedEvil != null &&
            e.statement.quotedFrom == null &&
            c.ladySource(e) != null)
        .toList();

    // Every registered draft prerequisite is explicit. Unregistered conditions
    // still return null in the parent resolver and keep their scenario inactive.
    flags.addAll({for (final key in conditionKeys) key: false});
    switch (id) {
      case 'RLS05':
        matches = o.leader == o.seat;
      case 'RAS06':
        target = chosenTarget;
        matches = o.phase == GamePhase.assassination &&
            o.role == Role.assassin &&
            target != null &&
            target! >= 0 &&
            target! < o.count &&
            target != o.seat;
      case 'REV01':
        flags['evilPolicy=hide'] = o.evil && o.plannedQuestSuccess == true;
        matches = o.quest <= 2 && o.successes < 2 && o.failures < 2;
      case 'G18' ||
            'RME04' ||
            'RPC02' ||
            'REV02' ||
            'REV04' ||
            'RAS04' ||
            'RMG05' ||
            'RMD04' ||
            'ROB03' ||
            'RLG05' ||
            'RLE06':
        bind(accusation);
        if (accusation != null) {
          target = accusation.statement.target;
          referenceQuest = questFrom(accusation, target!);
          flags['publicAccusationExists'] = true;
          flags['anotherPlayerPublicAccusation'] = true;
          flags['privateCandidateAccused'] = o.visible.contains(target);
          flags['privateKnownAllyAccused'] = knownEvil(target!);
          flags['publicTargetAccused'] = true;
          flags['publicAccusationAgainstSelf'] = target == o.seat;
          if (referenceQuest != null &&
              c.alignmentMayDifferSince(referenceQuest!)) {
            flags['publicSwitchAfterReferencedQuest'] = true;
            addSwitches(referenceQuest!);
          }
          // A defense responds to a real accuser; it does not guarantee a role.
          questionTo = accusation.statement.speaker;
        }
      case 'RLS06':
        final defended = c.latest(c.endorsements.where((e) =>
            e.statement.speaker != o.seat &&
            c.accusations
                .any((a) => a.statement.target == e.statement.target)));
        bind(defended);
        if (defended != null) {
          target = defended.statement.target;
          defender = questionTo = defended.statement.speaker;
          flags['publicEndorsementEvent'] = true;
        }
      case 'RMD03' || 'ROB04':
        bind(selfEndorsement);
        target = o.seat;
        flags['publicSelfEndorsed'] = selfEndorsement != null;
      case 'G19' || 'XVR01':
        final prior = c.latest(c.all.where((e) =>
            (id == 'G19'
                ? e.statement.speaker == o.seat
                : e.statement.speaker != o.seat) &&
            e.statement.position == DiscussionPosition.defend &&
            // asking about oneself in the third person makes no sense
            (id == 'G19' || e.statement.target != o.seat) &&
            c.contraryQuest(e) != null));
        bind(prior);
        if (prior != null) {
          target = prior.statement.target;
          defender = questionTo = prior.statement.speaker;
          referenceQuest = c.contraryQuest(prior);
          flags['publicNewContraryEvidence'] = true;
          flags['publicEndorsementExists'] = true;
          flags['newContraryEvidence'] = true;
        }
      case 'G21':
        final aboutOther = c.latest(questions.where(
            (e) => e.statement.target != null && e.statement.target != o.seat));
        bind(aboutOther);
        target = aboutOther?.statement.target;
        flags['publicDirectQuestionAboutTarget'] = aboutOther != null;
      case 'RME05':
        bind(question);
        target = question?.statement.target;
        flags['privateKnownEvilTargeted'] =
            target != null && knownEvil(target!);
      case 'RME06':
        for (var i = o.history.length - 1; i >= 0; i--) {
          final q = o.history[i];
          if (q.fails > 0 &&
              q.team.every((s) => s == o.seat || !knownEvil(s))) {
            referenceQuest = i + 1;
            flags['publicEvidenceConflict'] = true;
            break;
          }
        }
        flags['privateIdentityExceptionsPossible'] =
            o.configuredRoles?.contains(Role.mordred) == true ||
                o.expansions.lancelot > 0;
      case 'RPC04' || 'ROB06':
        final claim = c.latest(c.recent.where((e) =>
            e.statement.speaker != o.seat &&
            e.statement.quotedFrom == null &&
            (e.statement.claimsOpeningKnowledge ||
                e.statement.claimedOriginalSuccess != null ||
                e.statement.claimedEvil != null)));
        bind(id == 'ROB06' ? c.latest(ladyClaims) : claim);
        if (id == 'ROB06') target = c.latest(ladyClaims)?.statement.target;
        flags['publicSecretKnowledgeClaim'] = claim != null;
        flags['ladyPublicClaimExists'] = ladyClaims.isNotEmpty;
      case 'RPC05' || 'RAS03' || 'RAS05' || 'RMG04':
        target = questionTo = influence;
        flags['publicOnePersonDominatesDiscussion'] = influence != null;
        flags['publicPlayerInfluential'] = influence != null;
        flags['publicInfluencerTarget'] = influence != null;
        for (final e in c.recent.where((e) =>
            e.statement.target == influence ||
            e.statement.questionTo == influence)) {
          references.addAll(c.references(e));
        }
      case 'RPC07' || 'RMG02' || 'XLD04':
        if (contradiction != null) {
          final (older, newer) = contradiction;
          bind(newer);
          references.addAll(c.references(older));
          claimant = questionTo = newer.statement.speaker;
          target =
              id == 'XLD04' ? newer.statement.target : newer.statement.speaker;
          flags['publicClaimContradiction'] = true;
          flags['publicCandidateClaimContradiction'] =
              older.statement.speaker != newer.statement.speaker;
          flags['publicSameTargetContradictoryClaims'] = true;
          flags['sameRelevantSwitchStateOrTimeQualified'] = true;
        } else {
          matches = false;
        }
      case 'RLS04' || 'RAS01':
        bind(strong);
        if (strong != null) {
          claimant = questionTo = strong.statement.speaker;
          target = id == 'RAS01'
              ? strong.statement.speaker
              : strong.statement.target;
          flags['publicStrongUnsupportedClaim'] = true;
          flags['suspectedMerlinTarget'] =
              knownEvil(strong.statement.target!) &&
                  !knownEvil(strong.statement.speaker);
        }
      case 'RAS02':
        final byLeader = <int, List<ProposalRecord>>{};
        for (final p in o.proposals.where(
            (p) => p.leader != o.seat && p.team.every((s) => !knownEvil(s)))) {
          byLeader.putIfAbsent(p.leader, () => []).add(p);
        }
        for (final entry in byLeader.entries) {
          if (entry.value.length < 2 ||
              entry.value
                      .map((p) => (p.team.toList()..sort()).join(','))
                      .toSet()
                      .length <
                  2) {
            continue;
          }
          target = questionTo = entry.key;
          flags['privateKnownEvilPattern'] =
              o.visible.isNotEmpty && !o.switched;
          flags['publicTeamSelectionPattern'] = true;
          for (final p in entry.value) {
            references.add(BotEvidenceId(o.generation, BotEvidenceKind.proposal,
                'q${p.quest}/a${p.attempt}'));
          }
          break;
        }
      case 'RMG06' || 'ROB05':
        for (var i = o.history.length - 1; i >= 0; i--) {
          final q = o.history[i];
          final choices =
              q.team.where((s) => s != o.seat && o.team.contains(s));
          if (q.fails > 0 && choices.isNotEmpty) {
            target = questionTo = choices.first;
            referenceQuest = i + 1;
            break;
          }
        }
        matches = target != null;
      case 'RMD05':
        flags['privateKnownAllyOnTeam'] =
            o.team.any((s) => s != o.seat && knownEvil(s));
        if (o.history.isNotEmpty) {
          referenceQuest = o.history.length;
          flags['publicTeamOverlapHigh'] = !o.history.last.succeeded &&
              o.team.where(o.history.last.team.contains).length >=
                  (o.team.length / 2).ceil();
        }
      case 'REV05':
        final pressured = c.latest(accusations.where((e) =>
            knownEvil(e.statement.target!) &&
            accusations
                    .where((a) => a.statement.target == e.statement.target)
                    .map((a) => a.statement.speaker)
                    .toSet()
                    .length >=
                2));
        bind(pressured);
        target = pressured?.statement.target;
        final different = c.latest(c.recent.where((e) =>
            e.statement.speaker == target && e.statement.supportsTeam == true));
        if (different != null) references.addAll(c.references(different));
        flags['privateKnownAllyOverexposed'] = pressured != null;
        flags['publicDifferentVoteOrClaim'] = different != null && !approve;
        matches = !approve;
      case 'RMG07':
        bind(confident);
        target = questionTo = confident?.statement.speaker;
        flags['publicConfidentClaimTarget'] = confident != null;
      case 'RLG04':
        final permanent = c.latest(c.recent.where((e) =>
            e.statement.quotedFrom == null &&
            e.statement.certainty == DiscussionCertainty.permanent));
        bind(permanent);
        flags['publicPermanentAlignmentClaim'] = permanent != null;
      case 'RLG02' || 'RLE05' || 'XLC02':
        if (oldUse != null) {
          references.add(oldUse.id);
          addSwitches(oldUse.quest);
          referenceQuest = oldUse.quest;
          target = oldUse.target;
          flags['publicOrSelfLadyHistory'] = true;
          flags['publicPastInspection'] = true;
          flags['publicSwitchAfterInspection'] = true;
          final claim = c.latest(
              ladyClaims.where((e) => c.ladySource(e)!.id == oldUse.id));
          if (claim != null) {
            references.addAll(c.references(claim));
            flags['publicLadyClaim'] = true;
            flags['switchOccurredAfterClaim'] = true;
          }
        }
      case 'RLE03':
        bind(question);
        final prior = c.latest(c.all.where((e) =>
            e.statement.speaker == o.seat &&
            e.statement.supportsTeam != null &&
            e.statement.supportsTeam != approve &&
            e.statement.switched != null &&
            e.statement.switched != o.switched));
        if (prior != null) references.addAll(c.references(prior));
        flags['publicChallengeOwnPriorPosition'] = question != null &&
            ['challengeVote', 'challengeClaim']
                .contains(question.statement.intent) &&
            prior != null;
      case 'RLE07':
        final debate = c.latest(
            c.recent.where((e) => e.statement.intent == 'discussLancelot'));
        bind(debate);
        flags['publicLancelotDebate'] = debate != null;
        flags['proposalUnderDiscussion'] =
            o.team.isNotEmpty && o.rejections > 0;
      case 'XLD05':
        final backed = c.latest(c.endorsements.where((e) =>
            e.statement.certainty != DiscussionCertainty.tentative &&
            !c.basis(e).any((b) =>
                b.id.kind == BotEvidenceKind.quest ||
                b.id.kind == BotEvidenceKind.ballot) &&
            ladyClaims.any((claim) =>
                claim.statement.target == e.statement.target &&
                claim.statement.claimedEvil == false &&
                claim.statement.speaker != e.statement.speaker &&
                e.statement.evidenceIds.contains(c.id(claim).id)) &&
            c.basis(e).any((b) =>
                b.id.kind == BotEvidenceKind.ladyUse &&
                b.actor != e.statement.speaker)));
        bind(backed);
        target = backed?.statement.target;
        flags['publicLadyEndorsementExists'] = backed != null;
      case 'XSW04' || 'XVR02':
        final claim = c.latest(c.recent.where((e) {
          final s = e.statement;
          if (s.speaker == o.seat || s.quotedFrom != null) return false;
          if (id == 'XSW04') {
            // only Excalibur hides an original card; "my card was a
            // Success" in a plain game is not a claim about one
            return o.expansions.excalibur &&
                s.claimedOriginalSuccess != null &&
                s.originalCardQuest! <= o.history.length &&
                !c.hasLegalCardSource(e);
          }
          return (s.claimsOpeningKnowledge ||
                  s.claimedOriginalSuccess != null ||
                  s.claimedEvil != null) &&
              !c.hasLegalCardSource(e) &&
              !c.basis(e).any((b) =>
                  (b.id.kind == BotEvidenceKind.ladyUse ||
                      b.id.kind == BotEvidenceKind.swordUse) &&
                  b.actor == s.speaker &&
                  b.target == s.target);
        }));
        bind(claim);
        target = claimant = questionTo = claim?.statement.speaker;
        referenceQuest = claim?.statement.originalCardQuest;
        flags['publicSwordOriginalClaim'] = claim != null;
        flags['claimantNotSwordHolder'] = claim != null;
        flags['publicClaimWithoutPublicBasis'] = claim != null;
      default:
        matches = false;
    }
    // Resolve referenced quest only after selecting a coherent event/subject.
    if (referenceQuest != null) {
      references.add(BotEvidenceId(
          o.generation, BotEvidenceKind.quest, 'q$referenceQuest'));
    }
  }

  final BotObservation o;
  final String id;
  final bool approve;
  final BotConversation conversation;
  bool matches = true;
  int? target, referenceQuest, questionTo, defender, claimant, responseTo;
  final references = <BotEvidenceId>{};
  final flags = <String, bool>{};
  bool get supported => supportedIds.contains(id);
  void bind(PublicUtterance? e) {
    if (e == null) {
      matches = false;
      return;
    }
    responseTo = e.index;
    references.addAll(conversation.references(e));
  }

  void addSwitches(int quest) =>
      references.addAll(conversation.switchesAfter(quest).map((e) => e.id));
  int? questFrom(PublicUtterance e, int subject) {
    final quests = conversation.basis(e).where((b) =>
        b.id.kind == BotEvidenceKind.quest &&
        b.team.contains(subject) &&
        b.fails! > 0);
    return quests.isEmpty ? null : quests.last.quest;
  }

  bool knownEvil(int seat) {
    if (seat == o.seat) return o.evil;
    for (final f in o.facts.reversed) {
      if (f.target != seat ||
          (f.switched != o.switched && o.expansions.lancelot > 0)) {
        continue;
      }
      if (f.evil != null) return f.evil!;
      if (f.originalCard == false) return true;
    }
    return (!o.switched || o.expansions.lancelot == 0) &&
        o.visible.contains(seat) &&
        (o.role == Role.merlin ||
            (o.role.isEvil &&
                o.role != Role.oberon &&
                o.role != Role.lancelotEvil));
  }

  static const supportedIds = {
    'G18',
    'G19',
    'G21',
    'RLS04',
    'RLS05',
    'RLS06',
    'RME04',
    'RME05',
    'RME06',
    'RPC02',
    'RPC04',
    'RPC05',
    'RPC07',
    'REV01',
    'REV02',
    'REV04',
    'REV05',
    'RAS01',
    'RAS02',
    'RAS03',
    'RAS04',
    'RAS05',
    'RAS06',
    'RMG02',
    'RMG04',
    'RMG05',
    'RMG06',
    'RMG07',
    'RMD03',
    'RMD04',
    'RMD05',
    'ROB03',
    'ROB04',
    'ROB05',
    'ROB06',
    'RLG02',
    'RLG04',
    'RLG05',
    'RLE03',
    'RLE05',
    'RLE06',
    'RLE07',
    'XLD04',
    'XLD05',
    'XSW04',
    'XLC02',
    'XVR01',
    'XVR02'
  };
  static const conditionKeys = {
    'publicAccusationExists',
    'publicNewContraryEvidence',
    'publicDirectQuestionAboutTarget',
    'publicStrongUnsupportedClaim',
    'publicEndorsementEvent',
    'anotherPlayerPublicAccusation',
    'privateKnownEvilTargeted',
    'publicEvidenceConflict',
    'privateIdentityExceptionsPossible',
    'privateCandidateAccused',
    'publicSecretKnowledgeClaim',
    'publicOnePersonDominatesDiscussion',
    'publicCandidateClaimContradiction',
    'evilPolicy=hide',
    'privateKnownAllyAccused',
    'publicTargetAccused',
    'privateKnownAllyOverexposed',
    'publicDifferentVoteOrClaim',
    'suspectedMerlinTarget',
    'privateKnownEvilPattern',
    'publicTeamSelectionPattern',
    'publicPlayerInfluential',
    'publicInfluencerTarget',
    'publicClaimContradiction',
    'publicAccusationAgainstSelf',
    'publicConfidentClaimTarget',
    'publicSelfEndorsed',
    'privateKnownAllyOnTeam',
    'publicTeamOverlapHigh',
    'ladyPublicClaimExists',
    'publicOrSelfLadyHistory',
    'publicSwitchAfterInspection',
    'publicPermanentAlignmentClaim',
    'publicSwitchAfterReferencedQuest',
    'publicChallengeOwnPriorPosition',
    'publicPastInspection',
    'publicLancelotDebate',
    'proposalUnderDiscussion',
    'publicSameTargetContradictoryClaims',
    'sameRelevantSwitchStateOrTimeQualified',
    'publicLadyEndorsementExists',
    'publicSwordOriginalClaim',
    'claimantNotSwordHolder',
    'publicLadyClaim',
    'switchOccurredAfterClaim',
    'publicEndorsementExists',
    'newContraryEvidence',
    'publicClaimWithoutPublicBasis'
  };
}
