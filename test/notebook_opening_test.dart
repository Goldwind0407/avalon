import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/notebook/notebook_model.dart';
import 'notebook_model_test.dart' show MemoryNotebookStorage;

LocalGameSession deal(Set<String> roles,
    {int count = 7, ExpansionSettings e = const ExpansionSettings()}) {
  final room = Room(
      code: '',
      players: List.generate(
          count, (i) => Player(id: 'p$i', name: '玩家$i', isReady: true)))
    ..specialRoles.addAll(roles)
    ..expansions = e;
  return LocalGameSession(room, random: Random(5));
}

void main() {
  test('each role gets its own opening knowledge on the player pages', () {
    final s = deal({'派西維爾', '莫甘娜'},
        count: 8, e: const ExpansionSettings(lancelot: 1));
    final roles = s.game.roles;
    int seat(Role r) => roles.indexOf(r);

    final merlin = s.openingNotes(seat(Role.merlin));
    expect(merlin[seat(Role.merlin)]!.text, '我：梅林');
    for (final v in visibleSeats(roles, seat(Role.merlin))) {
      expect(merlin[v]!.side, SuspectedSide.evil);
      expect(merlin[v]!.text, '開局看到：邪惡');
    }
    expect(merlin.length, visibleSeats(roles, seat(Role.merlin)).length + 1);

    final percival = s.openingNotes(seat(Role.percival));
    for (final v in visibleSeats(roles, seat(Role.percival))) {
      expect(percival[v]!.side, isNull, reason: 'Merlin or Morgana');
      expect(percival[v]!.text, contains('梅林候選人'));
    }

    final assassin = s.openingNotes(seat(Role.assassin));
    expect(assassin[seat(Role.lancelotEvil)]!.text, '邪惡同伴（邪惡蘭斯洛特）');
    expect(assassin[seat(Role.morgana)]!.text, '邪惡同伴');
    expect(assassin[seat(Role.morgana)]!.side, SuspectedSide.evil);

    // no knowledge, no notes but one's own page
    expect(s.openingNotes(roles.indexOf(Role.loyal)).length, 1);
    expect(s.openingNotes(seat(Role.lancelotEvil)).length, 1);
  });

  test('opening notes fill empty pages once and never overwrite the player',
      () async {
    final storage = MemoryNotebookStorage();
    final book = GameNotebook(storage: storage);
    await book.bind('room/me/1');
    await book.setPlayerText('u2', '我自己寫的');
    await book.mark('u3', SuspectedSide.good);
    const notes = {
      'u1': PlayerNote(text: '開局看到：邪惡', side: SuspectedSide.evil),
      'u2': PlayerNote(text: '開局看到：邪惡', side: SuspectedSide.evil),
      'u3': PlayerNote(text: '開局看到：邪惡', side: SuspectedSide.evil),
    };
    await book.synchronize('room/me/1',
        opening: '梅林', proposals: const [], openingNotes: notes);
    expect(book.player('u1').text, '開局看到：邪惡');
    expect(book.player('u1').side, SuspectedSide.evil);
    expect(book.player('u2').text, '我自己寫的');
    expect(book.player('u2').side, SuspectedSide.evil);
    expect(book.player('u3').text, '開局看到：邪惡');
    expect(book.player('u3').side, SuspectedSide.good, reason: 'own mark kept');

    // removing a mark by hand sticks: notes are only applied once
    await book.mark('u1', SuspectedSide.evil);
    await book.synchronize('room/me/1',
        opening: '梅林', proposals: const [], openingNotes: notes);
    expect(book.player('u1').side, isNull);

    // survives reopening; clearing the notebook brings them back
    final reopened = GameNotebook(storage: storage);
    await reopened.bind('room/me/1');
    expect(reopened.player('u1').text, '開局看到：邪惡');
    expect(reopened.openingNotesApplied, isTrue);
    await reopened.clear();
    expect(reopened.player('u1').text, isEmpty);
    await reopened.synchronize('room/me/1',
        opening: '梅林', proposals: const [], openingNotes: notes);
    expect(reopened.player('u1').side, SuspectedSide.evil);
  });
}
