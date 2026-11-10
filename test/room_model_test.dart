import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';

void main() {
  test('本機房間能重新開啟且不會重複加入房主', () {
    final repo = LocalRoomRepository();
    final room = repo.create('騎士');
    expect(repo.join(room.code, '騎士'), same(room));
    expect(room.players.length, 1);
    expect(repo.join('000000', '騎士'), isNull);
  });
  test('新建房間為六位數且包含房主', () {
    final repo = LocalRoomRepository();
    final room = repo.create('騎士');
    expect(RegExp(r'^\d{6}$').hasMatch(room.code), isTrue);
    expect(room.players.single.isHost, isTrue);
    expect(room.specialRoles, containsAll(['梅林', '刺客']));
  });

  test('測試玩家至多十位', () {
    final repo = LocalRoomRepository();
    final room = repo.create('騎士');
    for (var i = 0; i < 15; i++) {
      repo.addDemoPlayer(room);
    }
    expect(room.players.length, 10);
  });
}
