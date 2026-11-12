import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/intro/intro_screen.dart';
import 'package:avalon_shadow_council/main.dart';

void main() {
  testWidgets('the opening animation plays, then the home screen appears',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AvalonApp());
    expect(find.byType(IntroScreen), findsOneWidget);
    expect(find.text('AVALON'), findsNothing);
    // halfway: still writing the signature
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(IntroScreen), findsOneWidget);
    // after the animation and the fade, the home screen takes over
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.text('AVALON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping skips the opening animation', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AvalonApp());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(const Offset(400, 200));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.text('AVALON'), findsOneWidget);
    // the timeline finishing later must not push a second home screen
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('AVALON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
