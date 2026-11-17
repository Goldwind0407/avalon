import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/bot_voices.dart';
import 'package:avalon_shadow_council/features/solo/voice_lines.dart';

/// An asset bundle that has recordings of [pieces] in chen's voice only.
class Recorded extends CachingAssetBundle {
  Recorded(Iterable<String> pieces)
      : assets = [
          for (final p in pieces) voiceAsset('chen', VoicePiece(p)),
          'assets/images/other.png',
        ];
  final List<String> assets;
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final a in assets)
          a: [
            {'asset': a}
          ]
      })!;
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(utf8.encode(jsonEncode({
        for (final a in assets) a: [a]
      })));
    }
    throw StateError('no asset $key');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a line is spoken only when every piece of it is recorded', () async {
    final voices = BotVoices(
        bundle: Recorded(['3號', '第1次', '出失敗時在隊上', '這次我反對']), persist: false);
    final line = '3號第1次出失敗時在隊上，這次我反對。';
    final assets = await voices.recordingsFor('chen', line);
    expect([for (final a in assets!) a.$2], [0, 0, 180, 350]);
    expect(assets.first.$1, 'assets/voice/chen/${voicePieceId('3號')}.mp3');
    // one piece not recorded: the whole line is left to be read
    expect(await voices.recordingsFor('chen', '4號第1次出失敗時在隊上，這次我反對。'), isNull);
    // another voice has nothing recorded yet
    expect(await voices.recordingsFor('yu', line), isNull);
    expect(await voices.recordingsFor('chen', '……'), isNull);
  });
}
