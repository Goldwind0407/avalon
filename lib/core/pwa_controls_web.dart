import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool get hasOfflineControls =>
    globalContext.hasProperty('openAvalonOffline'.toJS).toDart;

void openOfflineControls() =>
    globalContext.callMethod('openAvalonOffline'.toJS);
