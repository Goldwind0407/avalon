import '../game/discussion_model.dart';
import 'game_review.dart';

/// A finished solo game written out as plain text: roles, every proposal
/// with what was said (and where each computer line came from), every
/// vote with the reason the computer had for it, the cards played, and
/// the end. Meant to be read by a person, or pasted to someone helping to
/// tune the computer players.
String reviewText(GameReview r, {String? difficulty, DateTime? endedAt}) {
  final out = StringBuffer();
  String seat(int s) => '${s + 1}號${r.players[s]}';
  String seats(Iterable<int> list) => list.map((s) => '${s + 1}').join('、');
  String two(int n) => n.toString().padLeft(2, '0');

  out.writeln('阿瓦隆 單人模式 復盤');
  if (endedAt != null) {
    final t = endedAt.toLocal();
    out.writeln(
        '時間：${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}');
  }
  out.writeln('人數：${r.players.length}'
      '${difficulty == null || difficulty.isEmpty ? '' : '　難度：$difficulty'}');
  final e = r.expansions;
  out.writeln('擴充：${[
    if (e.lady) '湖中女神',
    if (e.excalibur) '王者之劍',
    if (e.lancelot > 0) '蘭斯洛特變體${e.lancelot == 1 ? '一' : '二'}',
  ].join('、').ifEmpty('無')}');
  out.writeln('結果：${r.winner ?? '—'}勝　${r.result ?? ''}');
  out.writeln('你：${seat(r.mySeat)}（${r.roles[r.mySeat].label}）'
      '　${r.iWon ? '你贏了' : '你輸了'}');

  out.writeln('\n== 身分');
  for (var s = 0; s < r.players.length; s++) {
    out.writeln('${seat(s)}：${r.roles[s].label}'
        '${r.evil(s) ? '（邪惡' : '（正義'}'
        '${r.roles[s].isLancelot && r.switchedAtEnd ? '，結束時已換邊' : ''}）'
        '${s == r.mySeat ? '　← 你' : r.styles[s] == null ? '' : '　${r.styles[s]}'}');
  }

  out.writeln('\n== 你的表現');
  for (final score in r.scores) {
    out.writeln('${score.title}：${score.value}　${score.detail}');
  }

  for (final q in r.quests) {
    out.writeln('\n== 第${q.number}次遠征');
    for (final round in q.proposals) {
      final p = round.record;
      out.writeln(
          '\n-- 提案${p.attempt}：${seat(p.leader)}當隊長，帶 ${seats(p.team)}');
      for (final (i, line) in round.lines.indexed) {
        if (line.statement.continues) continue;
        out.writeln(_line(line, seat));
        if (line.source == null) {
          out.writeln('     （電腦理解成：${lineReading(round.lines, i)}）');
        }
      }
      out.writeln('   投票（${p.approved ? '通過' : '否決'}）：');
      for (var s = 0; s < p.votes.length; s++) {
        final d = round.decisions[s];
        final odd = d == null ? null : r.oddVote(s, p, d);
        final why = d == null
            ? ''
            : '　${voteReasonLabels[d.reason] ?? d.reason}'
                '${odd == null ? '' : '；$odd'}';
        out.writeln('   ${s + 1}${p.votes[s] ? '○' : '✕'}'
            '${s == r.mySeat ? '（你）' : ''}$why');
      }
    }
    if (q.result case final res?) {
      final cards = q.cards.entries
          .map((c) => '${c.key + 1}${c.value ? '成' : '敗'}')
          .join(' ');
      out.writeln('>> 任務${res.succeeded ? '成功' : '失敗'}'
          '（${res.fails} 張失敗）　原本出的牌：$cards');
      if (res.excaliburHolder case final h?) {
        out.writeln('>> 王者之劍：${seat(h)}持劍，'
            '${res.excaliburTarget == null ? '沒有翻牌' : '翻了${seat(res.excaliburTarget!)}的牌'}');
      }
    }
    for (final c in r.ladyChecks.where((c) => c.quest == q.number)) {
      out.writeln('>> 湖中女神：${seat(c.holder)}查驗${seat(c.target)}'
          '（實際：${r.evilIn(c.target, c.quest) ? '邪惡' : '正義'}）');
    }
  }

  if (r.endLines.isNotEmpty || r.assassinTarget != null) {
    out.writeln('\n== 結局');
    for (final line in r.endLines) {
      out.writeln(_line(line, seat));
    }
    if (r.assassinTarget case final t?) {
      out.writeln('刺客刺殺：${seat(t)}（${r.roles[t].label}）');
    }
  }
  return '$out';
}

String _line(ReviewLine line, String Function(int) seat) {
  final s = line.statement;
  final stance = switch (s.supportsTeam) {
    true => '（挺）',
    false => '（反）',
    null => '',
  };
  final source = line.source == null ? '你' : line.source!.label;
  final aim = s.target == null || s.position == null
      ? ''
      : s.position == DiscussionPosition.suspect
          ? '　→懷疑${s.target! + 1}號'
          : '　→辯護${s.target! + 1}號';
  return '   ${seat(s.speaker)}［$source］$stance：${s.text}$aim';
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
