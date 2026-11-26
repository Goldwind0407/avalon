import 'package:flutter/foundation.dart' show ValueNotifier, kIsWasm, kIsWeb;
import 'package:flutter/widgets.dart' show Element, WidgetsBinding;
import 'web_page.dart';

/// Built with `--dart-define=WEB_FULL_EFFECTS=true`, the JavaScript web
/// build draws every effect too (to measure it against the others).
const _fullEffectsOnWeb = bool.fromEnvironment('WEB_FULL_EFFECTS');

/// Marked on a device whose browser could not keep up with every effect
/// (see web_perf_web.dart): it starts with the light table from then on.
const slowEffectsMark = 'avalon.slowEffects';

/// Whether the table is drawn light: no ambient loops, flights, glow or
/// soft shadows (cards are still gathered, shuffled and turned).
///
/// The apps never are. On the web: the WebAssembly build starts with every
/// effect (measured smoother than the JavaScript build's light table) and
/// the JavaScript build light; and a browser that turns out too slow for
/// every effect is switched to the light table while it plays, and starts
/// with it next time.
final effectsMode = ValueNotifier<bool>(_startLight());

bool get lightEffects => effectsMode.value;

bool _startLight() {
  if (!kIsWeb || _fullEffectsOnWeb) return false;
  if (!kIsWasm) return true;
  return readFlag(slowEffectsMark);
}

/// From now on, and on this device from its next start, the light table.
void useLightEffects() {
  writeFlag(slowEffectsMark, true);
  if (effectsMode.value) return;
  effectsMode.value = true;
  // everything on screen is drawn again, light, keeping where the game is
  void redraw(Element element) {
    element.markNeedsBuild();
    element.visitChildren(redraw);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) redraw(root);
}
