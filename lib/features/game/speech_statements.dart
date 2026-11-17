import '../solo/dialogue/bot_contract.dart';
import 'discussion_model.dart';
import 'game_model.dart';
import 'player_speech.dart';

// What a player's line means to the computers at the table, and how a
// statement travels (to the game review, and between the online referee and
// the computer players' server). No Flutter here: the server runs this too.

/// Whether the Lancelots had switched during each of the first [quests]
/// quests: a "switch" loyalty card turned over at the start of a quest
/// flips it for that quest and the ones after.
List<bool> switchStates(List<bool?> loyalty, int quests) {
  var switched = false;
  return [
    for (var q = 0; q < quests; q++)
      if (q < loyalty.length && loyalty[q] == true)
        switched = !switched
      else
        switched
  ];
}

/// The words used when a player picks a kind of line without typing one.
/// Empty for a remark with nothing typed. [ballot] is the last public vote
/// (needed for [PlayerSpeechKind.challengeVote]).
String speechText(PlayerSpeech speech, {ProposalRecord? ballot}) {
  final typed = speech.text?.trim();
  if (typed != null && typed.isNotEmpty) return typed;
  String who(int seat) => '${seat + 1}號';
  final t = speech.target;
  return switch (speech.kind) {
    PlayerSpeechKind.support => '我支持這隊。',
    PlayerSpeechKind.oppose => '這隊我想換人。',
    PlayerSpeechKind.suspect => '我懷疑${who(t!)}。',
    PlayerSpeechKind.trust => '我相信${who(t!)}是好人。',
    PlayerSpeechKind.ask => '${who(t!)}，你怎麼看？說說你的理由。',
    PlayerSpeechKind.challengeVote =>
      '${who(t!)}，第${ballot!.quest}次遠征的第${ballot.attempt}次提案，你投${ballot.votes[t] ? '贊成' : '反對'}的理由是什麼？',
    PlayerSpeechKind.claimGood => '我是好人，請相信我。',
    PlayerSpeechKind.claimPercival =>
      '我是派西維爾。${t == null ? '' : '${who(t)}是莫甘娜。'}',
    PlayerSpeechKind.ladyClaim =>
      '我用湖中女神查驗了${who(t!)}，他是${speech.claimsEvil == true ? '邪惡' : '正義'}陣營。',
    PlayerSpeechKind.remark => '',
  };
}

/// One statement for each thing [speech] says ([text] is its wording, the
/// same on all of them; the later ones are marked as continuing the first).
/// A Lady result counts as one only from the holder who checked that
/// player; from anyone else it is a plain word for or against them.
List<DiscussionStatement> statementsFromSpeech(
  PlayerSpeech speech,
  String text, {
  required int speaker,
  required int generation,
  required int quest,
  required int attempt,
  required List<int> team,
  required bool switched,
  required List<LadyCheck> ladyChecks,
  required List<bool?> loyalty,
  required int questsPlayed,
  ProposalRecord? ballot,
}) {
  if (text.isEmpty) return const [];
  // whether the Lancelots had switched when a Lady check was made after
  // quest [q] (before the next quest's loyalty card)
  bool switchedWhenChecked(int q) {
    final during = switchStates(loyalty, questsPlayed);
    return q >= 1 && q <= during.length ? during[q - 1] : switched;
  }

  return [
    for (final (index, point) in speech.points.indexed)
      () {
        final t = point.target;
        final check = point.kind == PlayerSpeechKind.ladyClaim && t != null
            ? ladyChecks
                .where((c) => c.holder == speaker && c.target == t)
                .lastOrNull
            : null;
        final kind = point.kind != PlayerSpeechKind.ladyClaim || check != null
            ? point.kind
            : point.claimsEvil == true
                ? PlayerSpeechKind.suspect
                : PlayerSpeechKind.trust;
        return DiscussionStatement(
            generation: generation,
            attempt: attempt,
            speaker: speaker,
            quest: quest,
            // a Lady result is about the sides when the check was made
            switched:
                check == null ? switched : switchedWhenChecked(check.quest),
            team: team,
            text: text,
            continues: index > 0,
            supportsTeam: switch (kind) {
              PlayerSpeechKind.support => true,
              PlayerSpeechKind.oppose => false,
              _ => index == 0 ? speech.supportsTeam : null,
            },
            intent: switch (kind) {
              PlayerSpeechKind.support => 'supportTeam',
              PlayerSpeechKind.oppose => 'opposeTeam',
              PlayerSpeechKind.suspect => 'accuse',
              PlayerSpeechKind.trust => 'defendOther',
              PlayerSpeechKind.ask => 'questionTeam',
              PlayerSpeechKind.challengeVote => 'challengeVote',
              PlayerSpeechKind.claimGood => 'defendSelf',
              PlayerSpeechKind.claimPercival =>
                DiscussionStatement.percivalClaim,
              PlayerSpeechKind.ladyClaim => 'interpretLady',
              PlayerSpeechKind.remark => 'opinion',
            },
            target: switch (kind) {
              PlayerSpeechKind.claimGood => speaker,
              _ => t,
            },
            claimedEvil: check == null ? null : point.claimsEvil,
            certainty: check == null
                ? DiscussionCertainty.tentative
                : DiscussionCertainty.certain,
            position: switch (kind) {
              PlayerSpeechKind.suspect => DiscussionPosition.suspect,
              PlayerSpeechKind.claimPercival when t != null =>
                DiscussionPosition.suspect,
              PlayerSpeechKind.trust => DiscussionPosition.defend,
              _ => null,
            },
            evidenceIds: [
              if (ballot != null && index == 0)
                BotEvidenceId(generation, BotEvidenceKind.ballot,
                        'q${ballot.quest}/a${ballot.attempt}')
                    .id,
              if (check != null)
                BotEvidenceId(generation, BotEvidenceKind.ladyUse,
                        'q${check.quest}/$speaker/${check.target}')
                    .id,
            ],
            questionTo: [PlayerSpeechKind.ask, PlayerSpeechKind.challengeVote]
                    .contains(kind)
                ? t
                : null);
      }()
  ];
}

/// A statement as it is stored and sent (the keys of the game review).
Map<String, dynamic> statementToMap(DiscussionStatement s) => {
      'by': s.speaker,
      'q': s.quest,
      if (s.generation != null) 'g': s.generation,
      if (s.attempt != null) 'a': s.attempt,
      'text': s.text,
      if (s.target != null) 'to': s.target,
      if (s.claimedEvil != null) 'evil': s.claimedEvil,
      if (s.switched != null) 'switched': s.switched,
      if (s.position != null) 'pos': s.position!.name,
      if (s.certainty != DiscussionCertainty.tentative)
        'sure': s.certainty.name,
      if (s.supportsTeam != null) 'for': s.supportsTeam,
      if (s.team.isNotEmpty) 'team': s.team,
      if (s.intent != null) 'intent': s.intent,
      if (s.topic != null) 'topic': s.topic,
      if (s.questionTo != null) 'ask': s.questionTo,
      if (s.replyTo != null) 'reply': s.replyTo,
      if (s.quotedFrom != null) 'quote': s.quotedFrom,
      if (s.claimedOriginalSuccess != null) 'cardOk': s.claimedOriginalSuccess,
      if (s.originalCardQuest != null) 'cardQ': s.originalCardQuest,
      if (s.claimsOpeningKnowledge) 'opening': true,
      if (s.continues) 'cont': true,
      if (s.evidenceIds.isNotEmpty) 'ev': s.evidenceIds,
    };

DiscussionStatement statementFromMap(Map m) => DiscussionStatement(
    speaker: (m['by'] as num).toInt(),
    quest: (m['q'] as num).toInt(),
    generation: (m['g'] as num?)?.toInt(),
    attempt: (m['a'] as num?)?.toInt(),
    text: m['text'] as String,
    target: (m['to'] as num?)?.toInt(),
    claimedEvil: m['evil'] as bool?,
    switched: m['switched'] as bool?,
    position: m['pos'] == null
        ? null
        : DiscussionPosition.values.byName(m['pos'] as String),
    certainty: m['sure'] == null
        ? DiscussionCertainty.tentative
        : DiscussionCertainty.values.byName(m['sure'] as String),
    supportsTeam: m['for'] as bool?,
    team: [for (final s in m['team'] as List? ?? const []) (s as num).toInt()],
    intent: m['intent'] as String?,
    topic: m['topic'] as String?,
    questionTo: (m['ask'] as num?)?.toInt(),
    replyTo: (m['reply'] as num?)?.toInt(),
    quotedFrom: (m['quote'] as num?)?.toInt(),
    claimedOriginalSuccess: m['cardOk'] as bool?,
    originalCardQuest: (m['cardQ'] as num?)?.toInt(),
    claimsOpeningKnowledge: m['opening'] == true,
    continues: m['cont'] == true,
    evidenceIds: [for (final e in m['ev'] as List? ?? const []) e as String]);
