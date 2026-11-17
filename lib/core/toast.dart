import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

// A short message in the middle of the screen, the way iOS shows one: it
// fades in, growing a little, stays a moment and fades away. One at a
// time; a new one takes the place of the last. A tap sends it away.

OverlayEntry? _entry;
GlobalKey<_ToastState>? _current;

/// Shows [message] over everything for a moment. [title] and [image] (an
/// asset path: a card or token the message is about) are optional.
void showToast(BuildContext context, String message,
    {String? title, String? image, Duration? duration}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _dismissNow();
  final key = GlobalKey<_ToastState>();
  final entry = OverlayEntry(
      builder: (_) => _Toast(
          key: key,
          title: title,
          message: message,
          image: image,
          duration: duration ??
              Duration(
                  milliseconds: 2200 +
                      60 *
                          (message.length + (title?.length ?? 0)).clamp(0, 60)),
          onGone: () {
            if (_current == key) _dismissNow();
          }));
  _entry = entry;
  _current = key;
  overlay.insert(entry);
}

void _dismissNow() {
  _entry?.remove();
  _entry = null;
  _current = null;
}

class _Toast extends StatefulWidget {
  const _Toast(
      {super.key,
      required this.message,
      required this.duration,
      required this.onGone,
      this.title,
      this.image});
  final String message;
  final String? title, image;
  final Duration duration;
  final VoidCallback onGone;
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200))
    ..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _leave);
  }

  Future<void> _leave() async {
    _timer?.cancel();
    if (!mounted) return;
    await _motion.reverse();
    if (mounted) widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final s = (size.shortestSide / 390).clamp(.85, 1.25);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, child) {
              final t = _motion.status == AnimationStatus.reverse
                  ? _motion.value
                  : Curves.easeOutBack.transform(_motion.value);
              return Opacity(
                opacity: _motion.value.clamp(0.0, 1.0),
                child: Transform.scale(scale: .9 + .1 * t, child: child),
              );
            },
            child: GestureDetector(
              onTap: _leave,
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: (size.width * .6).clamp(240, 380),
                      minWidth: 180),
                  child: Container(
                    padding:
                        EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, 16 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xEE161B36),
                      borderRadius: BorderRadius.circular(18 * s),
                      border: Border.all(
                          color: AvalonTheme.gold.withValues(alpha: .45)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: .5),
                            blurRadius: 28 * s,
                            offset: Offset(0, 8 * s)),
                        BoxShadow(
                            color: AvalonTheme.gold.withValues(alpha: .12),
                            blurRadius: 24 * s),
                      ],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.image != null) ...[
                        Container(
                          width: 46 * s,
                          height: 60 * s,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8 * s),
                              border: Border.all(
                                  color:
                                      AvalonTheme.gold.withValues(alpha: .7))),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(7 * s),
                              child: Image.asset(widget.image!,
                                  fit: BoxFit.cover)),
                        ),
                        SizedBox(height: 10 * s),
                      ],
                      if (widget.title != null) ...[
                        Text(widget.title!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 15 * s,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                color: AvalonTheme.gold)),
                        SizedBox(height: 5 * s),
                      ],
                      Text(widget.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13.5 * s,
                              height: 1.45,
                              color: const Color(0xFFEDE4CF))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
