import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/library/library_screen.dart';

/// Root widget: wires up [MaterialApp] with the premium dark theme and
/// starts the user on the library dashboard.
///
/// Phase 1 has exactly one entry point (the library) and pushes the reader
/// on top of it via [Navigator], so no routing package is needed yet.
class PageTetherApp extends StatelessWidget {
  const PageTetherApp({super.key});

  @override
  Widget build(BuildContext context) {
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
