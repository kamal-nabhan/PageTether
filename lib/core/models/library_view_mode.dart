import 'package:flutter/material.dart';

/// How the library dashboard displays its books: a compact list, or a grid
/// at one of three tile densities. Purely a local display preference (no
/// backend/sync) — persisted via `LibraryStore.loadViewMode`/`saveViewMode`
/// under `pt.viewmode.v1` so the choice survives a restart (see
/// `ViewModeNotifier` in `features/library/library_providers.dart`), loaded
/// once in `main()` like the other persisted prefs.
enum LibraryViewMode {
  list,
  gridSmall,
  gridMedium,
  gridLarge;

  /// Display label for the view-mode picker (see `ViewModeControl`).
  String get label => switch (this) {
    LibraryViewMode.list => 'List',
    LibraryViewMode.gridSmall => 'Small grid',
    LibraryViewMode.gridMedium => 'Medium grid',
    LibraryViewMode.gridLarge => 'Large grid',
  };

  /// Icon shown both on the picker's trigger button (for whichever mode is
  /// currently selected) and next to each of its menu items.
  IconData get icon => switch (this) {
    LibraryViewMode.list => Icons.view_list_rounded,
    LibraryViewMode.gridSmall => Icons.apps_rounded,
    LibraryViewMode.gridMedium => Icons.grid_view_rounded,
    LibraryViewMode.gridLarge => Icons.window_rounded,
  };
}
