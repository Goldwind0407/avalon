// How a computer player's line is cut into pieces that are recorded once
// and joined when it is spoken. Lines are put together during the game
// ("3號第1次出失敗時在隊上，…"), so whole sentences cannot all be recorded;
// the pieces between punctuation and numbers can (about 1,400), plus each
// number in the forms it is said ("3號", "第1次", …).
//
// A piece's id comes from its words alone, so the same words always find
// the same recording, whoever wrote the line and however it was put
// together. Recordings live at assets/voice/<persona>/<id>.mp3.
// No Flutter here: the recording script tool uses this too.

/// One recorded piece of a line.
class VoicePiece {
  const VoicePiece(this.text, {this.pause = 0});

  /// The words, as they are to be read.
  final String text;

  /// A short silence after it, in milliseconds (at a comma, a full stop).
  final int pause;

  String get id => voicePieceId(text);
  @override
  bool operator ==(Object other) =>
      other is VoicePiece && other.text == text && other.pause == pause;
  @override
  int get hashCode => Object.hash(text, pause);
  @override
  String toString() => pause == 0 ? text : '$text|$pause';
}

/// Numbers are said with what follows (or comes before) them.
final _number = RegExp(r'第\s*(\d+)\s*次|(\d+)\s*(號|次|張|人|票|分|秒|輪|位)|(\d+)');
final _stop = RegExp(r'[。！？!?；;]');
final _comma = RegExp(r'[，,、：:]');
final _ignored = RegExp(r'[\s「」『』（）()…—\-~～"“”‘’《》〈〉]+');

/// The pieces [line] is said in, in order. Punctuation is not read; it
/// becomes a pause.
List<VoicePiece> voicePieces(String line) {
  final pieces = <VoicePiece>[];
  final buffer = StringBuffer();
  void flush([int pause = 0]) {
    final text = buffer.toString().replaceAll(_ignored, '');
    buffer.clear();
    if (text.isNotEmpty) {
      pieces.add(VoicePiece(text, pause: pause));
    } else if (pause > 0 && pieces.isNotEmpty) {
      // punctuation after a number: the pause goes after the number
      final last = pieces.removeLast();
      pieces.add(VoicePiece(last.text,
          pause: last.pause > pause ? last.pause : pause));
    }
  }

  var i = 0;
  while (i < line.length) {
    final number = _number.matchAsPrefix(line, i);
    if (number != null) {
      flush();
      final spoken = number.group(1) != null
          ? '第${number.group(1)}次'
          : number.group(2) != null
              ? '${number.group(2)}${number.group(3)}'
              : number.group(4)!;
      pieces.add(VoicePiece(spoken));
      i = number.end;
      continue;
    }
    final char = line[i];
    if (_stop.hasMatch(char)) {
      flush(350);
    } else if (_comma.hasMatch(char)) {
      flush(180);
    } else {
      buffer.write(char);
    }
    i++;
  }
  flush();
  return pieces;
}

/// A stable name for the recording of [text]: "v" and 8 hex digits
/// (FNV-1a over its UTF-16 code units).
String voicePieceId(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'v${hash.toRadixString(16).padLeft(8, '0')}';
}

/// Where the recording of [piece] in [persona]'s voice is kept.
String voiceAsset(String persona, VoicePiece piece) =>
    'assets/voice/$persona/${piece.id}.mp3';
