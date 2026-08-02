// Widget test for AnnotationPanel's collapsed/expanded handle toggle — the
// cheap, meaningful bit of UI behavior to lock down without fighting pdfrx
// (the panel itself has no pdfrx dependency; it's a dumb, callback-driven
// widget owning no provider reads of its own — see its class doc in
// lib/features/reader/widgets/annotation_panel.dart). Only the universal
// "tap the handle" open gesture is exercised here — hover and right-click
// are covered by that doc comment's reasoning, not re-tested per platform.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pagetether/features/reader/widgets/annotation_panel.dart';

void main() {
  // ProviderScope is required here — the panel's nested "Sync notes" button
  // (_SyncNotesButton, a ConsumerWidget) reads syncRunProvider, so without a
  // ProviderScope ancestor it throws on build.
  Widget harness({
    required bool expanded,
    required ValueChanged<bool> onExpandedChanged,
  }) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: AnnotationPanel(
              expanded: expanded,
              onExpandedChanged: onExpandedChanged,
              selectedColorIndex: 0,
              onColorTap: (_) {},
              canCreate: true,
              onHighlight: () {},
              onUnderline: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('collapsed panel shows only the handle, no tools', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(expanded: false, onExpandedChanged: (_) {}),
    );

    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byTooltip('Highlight selected text'), findsNothing);
  });

  testWidgets('tapping the handle on a collapsed panel requests expansion', (
    tester,
  ) async {
    var expanded = false;
    await tester.pumpWidget(
      harness(expanded: false, onExpandedChanged: (v) => expanded = v),
    );

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();

    expect(expanded, isTrue);
  });

  testWidgets('expanded panel shows the highlight/underline tools', (
    tester,
  ) async {
    await tester.pumpWidget(harness(expanded: true, onExpandedChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Highlight selected text'), findsOneWidget);
    expect(find.byTooltip('Underline selected text'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('tapping the handle on an expanded panel requests collapse', (
    tester,
  ) async {
    var expanded = true;
    await tester.pumpWidget(
      harness(expanded: true, onExpandedChanged: (v) => expanded = v),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();

    expect(expanded, isFalse);
  });
}
