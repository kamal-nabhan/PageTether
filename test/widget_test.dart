// Basic smoke test for PageTether's Phase 1 shell: verifies the app boots
// into the library dashboard and shows its core chrome.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pagetether/app.dart';

void main() {
  testWidgets('Library dashboard renders brand and books', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PageTetherApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('PageTether'), findsOneWidget);
    expect(find.text('Your Library'), findsOneWidget);
    expect(find.text('Atomic Habits'), findsWidgets);
  });
}
