import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The table drawn by the web page itself (web/table/table.js), laid over
/// the app: the browser draws its cards and moves them, the game behind it
/// stays here.
bool get tablePageAvailable {
  try {
    return globalContext.has('avalonTable');
  } catch (_) {
    return false;
  }
}

JSObject get _table => globalContext['avalonTable'] as JSObject;

/// Puts the table on screen; [host] answers what the page asks of the game
/// (a move, a sound, a page of the app to open).
void openTablePage(String Function(String type, String arg) host) {
  _table.callMethod(
      'open'.toJS,
      ((JSString type, JSString arg) =>
          host(type.toDart, arg.toDart).toJS).toJS);
}

/// The game as this player may see it, as JSON (see html_table_screen.dart).
void updateTablePage(String state) =>
    _table.callMethod('update'.toJS, state.toJS);

/// Something to show once (a line said aloud, a move refused), as JSON.
void tablePageEvent(String event) =>
    _table.callMethod('event'.toJS, event.toJS);

/// The app shows one of its own pages over the table (the rules, the
/// notebook): the table steps aside meanwhile.
void coverTablePage(bool covered) =>
    _table.callMethod('cover'.toJS, covered.toJS);

void closeTablePage() => _table.callMethod('close'.toJS);
