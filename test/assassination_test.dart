import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';

Future<void> advance(WidgetTester tester, int ms) async {
  for (var elapsed = 0; elapsed < ms; elapsed += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final count in [5, 10]) {
    for (final targetRole in [Role.merlin, Role.oberon]) {
      testWidgets(
          '$count players can target ${targetRole.name} without alignment hints',
          (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final room = Room(
            code: '123456',
            players: List.generate(
                count,
                (i) => Player(
                    id: '$i',
                    name: count == 10 ? '玩家$i甲乙丙丁戊己庚辛壬癸甲乙丙' : '玩家$i',
                    isReady: true)));
        room.specialRoles.add('奧伯倫');
        await tester.pumpWidget(
            MaterialApp(theme: AvalonTheme.dark, home: GameScreen(room: room)));
        await advance(tester, 3500);
        final dynamic screen = tester.state(find.byType(GameScreen));
        final AvalonGame game = screen.game as AvalonGame;
        screen.act(() {
          for (var i = 0; i < count; i++) {
            game.confirmIdentity();
          }
          for (var quest = 0; quest < 3; quest++) {
            game.proposeTeam(List.generate(game.requiredTeam, (i) => i));
            for (var i = 0; i < count; i++) {
              game.vote(true);
            }
            game.continueVote();
            while (game.phase == GamePhase.quest) {
              game.playQuest(true);
            }
            game.continueQuest();
          }
        });
        await advance(tester, 1500);
        await tester.tap(find.text('我是本人，開啟秘密畫面'));
        await advance(tester, 1800);
        String label(int i) => '${i + 1} 號 · ${game.players[i]}';
        for (var i = 0; i < count; i++) {
          expect(find.text(label(i)),
              game.roles[i] == Role.assassin ? findsNothing : findsOneWidget);
        }
        // No actual character names appear in the candidate buttons.
        expect(find.text('奧伯倫'), findsNothing);
        expect(find.text('梅林'), findsNothing);
        final target = game.roles.indexOf(targetRole);
        await tester.ensureVisible(find.text(label(target)));
        await tester.tap(find.text(label(target)));
        await advance(tester, 300);
        await tester.ensureVisible(find.text('確認刺殺'));
        await tester.tap(find.text('確認刺殺'));
        await advance(tester, 4600);
        final hit = targetRole == Role.merlin;
        expect(game.phase, GamePhase.finished);
        expect(game.winner, hit ? '邪惡' : '正義');
        expect(find.text(hit ? '梅林遇刺' : '刺殺失敗'), findsOneWidget);
        await tester.tap(find.text('揭曉全員身分'));
        await advance(tester, 4500);
        expect(find.text('${game.winner}陣營獲勝'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
