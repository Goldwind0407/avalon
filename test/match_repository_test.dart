import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_archive.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_repository.dart';

/// Storage whose reads of some keys fail while [failing] says so.
class FlakyStorage extends MemoryMatchStorage {
  final failing = <String>{};
  @override
  Future<String?> read(String key) async {
    if (failing.contains(key)) throw StateError('storage unavailable');
    return super.read(key);
  }
}

const indexKey = 'avalon.solo.matches.v1';
String matchKey(String id) => 'avalon.solo.match.v1/$id';

MatchArchive game(String id, {int minute = 0}) => MatchArchive(
    id: id,
    endedAt: DateTime(2026, 11, 16, 12, minute),
    difficulty: '一般',
    personas: [null, 'kai', null, null, null],
    review: GameReview.build(
        players: ['你', '甲', '乙', '丙', '丁'],
        roles: const [
          Role.loyal,
          Role.merlin,
          Role.percival,
          Role.assassin,
          Role.morgana
        ],
        styles: List.filled(5, null),
        mySeat: 0,
        winner: '正義',
        result: '',
        proposals: [
          ProposalRecord(
              quest: 1,
              attempt: 1,
              leader: 1,
              team: [1, 2],
              votes: List.filled(5, true))
        ],
        history: [
          QuestResult([1, 2], 0, true)
        ],
        statements: [
          DiscussionStatement(
              speaker: 0,
              quest: 1,
              attempt: 1,
              text: '4號可疑',
              target: 3,
              position: DiscussionPosition.suspect)
        ],
        sources: const {},
        decisions: const {},
        cardsBySeat: const {},
        ladyChecks: const [],
        assassinTarget: null,
        expansions: const ExpansionSettings()));

List<String> ids(String? index) =>
    [for (final e in jsonDecode(index!) as List) (e as Map)['id'] as String];

void main() {
  test('a failed read of the list of games never writes over it', () async {
    final storage = FlakyStorage();
    final repository = MatchRepository(storage: storage);
    await repository.save(game('oldA'));
    await repository.save(game('oldB', minute: 1));
    expect(ids(storage.values[indexKey]), ['oldB', 'oldA']);
    // the list cannot be read just now: the new game is not remembered,
    // and the old ones are not forgotten
    storage.failing.add(indexKey);
    await repository.save(game('newC', minute: 2));
    await repository.delete('oldA');
    await repository.clear();
    expect(await repository.summaries(), isEmpty);
    storage.failing.clear();
    expect(ids(storage.values[indexKey]), ['oldB', 'oldA']);
    expect(
        [for (final s in await repository.summaries()) s.id], ['oldB', 'oldA']);
    // once it reads again, saving works as before
    await repository.save(game('newC', minute: 2));
    expect(ids(storage.values[indexKey]), ['newC', 'oldB', 'oldA']);
  });

  test('an entry this version cannot read is kept as it is', () async {
    final storage = FlakyStorage();
    final repository = MatchRepository(storage: storage);
    await repository.save(game('oldA'));
    final index = jsonDecode(storage.values[indexKey]!) as List;
    final strange = {'id': 'fromTheFuture', 'shape': 'unknown'};
    index.add(strange);
    storage.values[indexKey] = jsonEncode(index);
    await repository.save(game('newB', minute: 1));
    final stored = jsonDecode(storage.values[indexKey]!) as List;
    expect(stored.last, strange);
    expect(
        [for (final s in await repository.summaries()) s.id], ['newB', 'oldA']);
  });

  test('old summaries are upgraded one by one; a failed one waits', () async {
    final storage = FlakyStorage();
    final repository = MatchRepository(storage: storage);
    for (final (i, id) in ['a', 'b', 'c'].indexed) {
      await repository.save(game(id, minute: i));
    }
    // make all three look like they came from the previous version, with
    // stale habit counts
    final index = jsonDecode(storage.values[indexKey]!) as List;
    for (final e in index) {
      (e as Map)
        ..remove('sv')
        ..['traits'] = {'gc': 100, 'gcR': 0};
    }
    storage.values[indexKey] = jsonEncode(index);
    // the newest game's record is damaged; the next one cannot be read
    // just now
    storage.values[matchKey('c')] = '{not json';
    storage.failing.add(matchKey('b'));
    final list = await repository.summaries();
    final byId = {for (final s in list) s.id: s};
    // the readable one is upgraded with today's counts
    expect(byId['a']!.version, MatchSummary.currentVersion);
    expect(byId['a']!.traits!['gc'], 1);
    // the two others are not learned from until they can be redone
    expect(byId['b']!.traits, isNull);
    expect(byId['c']!.traits, isNull);
    final stored = {
      for (final e in jsonDecode(storage.values[indexKey]!) as List)
        (e as Map)['id']: e
    };
    expect(stored['a']!['sv'], MatchSummary.currentVersion);
    expect(stored['b']!['sv'], isNot(MatchSummary.currentVersion),
        reason: 'stored as it was, to be tried again');
    // the record comes back: next time it is upgraded too
    storage.failing.clear();
    final again = {for (final s in await repository.summaries()) s.id: s};
    expect(again['b']!.version, MatchSummary.currentVersion);
    expect(again['b']!.traits!['gc'], 1);
  });
}
