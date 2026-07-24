// Basic smoke test for PageTether's Phase 1.1 shell: verifies the app boots
// into the library dashboard and shows its core chrome. Doesn't override
// libraryStoreProvider/libraryProvider, so the library legitimately starts
// empty here (no bundled-sample seeding happens outside main()'s bootstrap)
// — that's exactly the empty-state path Phase 1.1 added in place of the old
// hardcoded mock books.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pagetether/app.dart';

void main() {
  testWidgets('Library dashboard renders brand and empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PageTetherApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('PageTether'), findsOneWidget);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Open your first PDF'), findsWidgets);
  });
}
