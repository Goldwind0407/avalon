import 'dart:io';
import 'package:avalon_shadow_council/features/solo/memory/match_archive.dart';
import 'package:avalon_shadow_council/features/solo/memory/social_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/solo/voice_lines.dart';

List<String> said(String line) => [for (final p in voicePieces(line)) '$p'];

void main() {
  scriptCoverage();
  test('a line is cut at punctuation and numbers; numbers keep their unit', () {
    expect(
        said('3號第1次出失敗時在隊上，這次我反對。'), ['3號', '第1次', '出失敗時在隊上|180', '這次我反對|350']);
    expect(said('我帶自己和1號、2號：1號、2號還沒出過任務'),
        ['我帶自己和', '1號|180', '2號|180', '1號|180', '2號', '還沒出過任務']);
    expect(said('他有2次不在隊上卻投贊成'), ['他有', '2次', '不在隊上卻投贊成']);
    expect(said('第 4 次要兩張失敗'), ['第4次', '要兩張失敗']);
    expect(said('10號，你怎麼看？'), ['10號|180', '你怎麼看|350']);
    // quotes and spaces are not read
    expect(said('「這隊我過」 先出任務吧！'), ['這隊我過先出任務吧|350']);
    expect(said(''), isEmpty);
    expect(said('……'), isEmpty);
  });

  test('the same words find the same recording, whoever says them', () {
    final a = voicePieces('第2次那組成功了，我會比較信一點。');
    final b = voicePieces('3號說得對，我會比較信一點。');
    expect(a.last.id, b.last.id);
    expect(a.first.id, isNot(b.first.id));
    expect(voicePieceId('3號'), matches(RegExp(r'^v[0-9a-f]{8}$')));
    // fixed for good: recordings are named by it
    expect(voicePieceId('3號'), voicePieceId('3號'));
    expect(voicePieceId(''), 'v811c9dc5');
    expect(voiceAsset('chen', const VoicePiece('3號')),
        'assets/voice/chen/${voicePieceId('3號')}.mp3');
  });
}

void scriptCoverage() {
  test('every line about an earlier game can be said from the script', () {
    final script = File('tool/voice/script.csv')
        .readAsLinesSync()
        .skip(1)
        .map((l) => l.split(',').first)
        .toSet();
    final missing = <String>{};
    for (final kind in EpisodeKind.values) {
      for (final ago in [0, 1]) {
        for (final who in ['1號', '6號']) {
          for (final line in memoryLines(kind, memoryWhen(ago), who)) {
            for (final piece in voicePieces(line)) {
              if (!script.contains(piece.id)) missing.add(piece.text);
            }
          }
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'rerun test/voice_script_test.dart and record the new pieces');
  });
}
