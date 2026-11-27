import 'web_page.dart';

/// What the screen is showing right now ('menu' off the table; at the table
/// the game's phase, or 'deal' / 'interlude' while those play), so the
/// frame-rate watcher (web_perf_web.dart) can tell where it was slow, and
/// the web page (web/pwa.js) offers a new version only off the table.
String get perfStage => _stage;
set perfStage(String stage) {
  if (stage == _stage) return;
  _stage = stage;
  showStage(stage);
}

String _stage = 'menu';

/// Something that happened (a voice starting, a sound, a new line), noted
/// with the time so that a stop of the screen right after it can be told
/// apart from the others (web_perf_web.dart sets [perfNoteSink]).
void perfNote(String what) => perfNoteSink?.call(what);
void Function(String what)? perfNoteSink;

/// The table is drawn by the web page (web/table/), not by the app: the
/// app builds nothing then, and that is not the screen standing still.
bool perfPageTable = false;
