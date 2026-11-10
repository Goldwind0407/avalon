import 'dart:async';
import 'package:flutter/material.dart';

/// Controls decorative loops only. Finite gameplay animations must continue
/// while idle so their completion callbacks can advance the presentation.
class AmbientMotionScope extends InheritedWidget {
  const AmbientMotionScope(
      {super.key, required this.enabled, required super.child});
  final bool enabled;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AmbientMotionScope>()
          ?.enabled ??
      true;

  @override
  bool updateShouldNotify(AmbientMotionScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Lets the table rest during discussion without disabling game interactions.
class AmbientMotion extends StatefulWidget {
  const AmbientMotion(
      {super.key,
      required this.child,
      this.idleAfter = const Duration(seconds: 8)});
  final Widget child;
  final Duration idleAfter;

  @override
  State<AmbientMotion> createState() => _AmbientMotionState();
}

class _AmbientMotionState extends State<AmbientMotion>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  bool _active = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_foreground) _arm();
  }

  void _arm() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleAfter, () {
      if (mounted) setState(() => _active = false);
    });
  }

  void _wake() {
    if (!_foreground) return;
    if (!_active) setState(() => _active = true);
    _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _idleTimer?.cancel();
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _active = _foreground;
    });
    if (_foreground) _arm();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _wake(),
        child: TickerMode(
          enabled: _foreground,
          child: AmbientMotionScope(
            enabled: _foreground &&
                _active &&
                !MediaQuery.disableAnimationsOf(context),
            child: widget.child,
          ),
        ),
      );
}
