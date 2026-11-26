import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether this page runs isolated from other sites (the headers that let
/// the WebAssembly renderer use several threads). Then Google's sign-in
/// window cannot report back to it, and signing in goes through
/// web/login/, which is not isolated.
bool get pageIsolated =>
    (globalContext['crossOriginIsolated'] as JSBoolean?)?.toDart ?? false;

/// A flag kept on this device (localStorage); false when unset or when
/// the browser keeps nothing (private browsing).
bool readFlag(String key) {
  try {
    final storage = globalContext['localStorage'] as JSObject;
    final value = storage.callMethod<JSAny?>('getItem'.toJS, key.toJS);
    return (value as JSString?)?.toDart == '1';
  } catch (_) {
    return false;
  }
}

void writeFlag(String key, bool value) {
  try {
    final storage = globalContext['localStorage'] as JSObject;
    if (value) {
      storage.callMethod<JSAny?>('setItem'.toJS, key.toJS, '1'.toJS);
    } else {
      storage.callMethod<JSAny?>('removeItem'.toJS, key.toJS);
    }
  } catch (_) {}
}

/// Goes to the separate sign-in page; it comes back to online play.
void openSignInPage() {
  final location = globalContext['location'] as JSObject;
  location.callMethod('assign'.toJS, 'login/'.toJS);
}

/// Tells the page around the game (web/pwa.js) what is on screen: a new
/// version is only offered off the table ('menu').
void showStage(String stage) {
  try {
    globalContext['avalonStage'] = stage.toJS;
  } catch (_) {}
}
