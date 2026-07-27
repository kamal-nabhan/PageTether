import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/library/library_screen.dart';
import 'features/settings/sync_controller.dart';

/// Root widget: wires up [MaterialApp] with the premium dark theme and
/// starts the user on the library dashboard.
///
/// Phase 1 has exactly one entry point (the library) and pushes the reader
/// on top of it via [Navigator], so no routing package is needed yet.
///
/// A [ConsumerWidget] (rather than a plain [StatelessWidget]) purely so it
/// can `ref.watch(syncControllerProvider)` — see that provider's doc — which
/// keeps the Phase 4b auto-sync controller alive for the whole app session,
/// regardless of which screen/route is currently on top. This widget itself
/// never rebuilds from that watch (the controller's state is `void`), so
/// this costs nothing beyond making sure the controller exists.
class PageTetherApp extends ConsumerWidget {
  const PageTetherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncControllerProvider);
    return MaterialApp(
      title: 'PageTether',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const LibraryScreen(),
    );
  }
}
