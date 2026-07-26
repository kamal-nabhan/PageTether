import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/fullscreen/fullscreen_service.dart';
import 'core/storage/library_store.dart';
import 'features/library/library_bootstrap.dart';
import 'features/library/library_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // No-ops on every platform except Windows/macOS/Linux — safe to always
  // call. Must happen before runApp so the reader's fullscreen toggle can
  // use window_manager immediately.
  await FullscreenService.initializeForDesktop();

  final prefs = await SharedPreferences.getInstance();
  final store = LibraryStore(prefs);
  final initialBooks = await loadInitialLibrary(store);
  final initialCollections = await store.loadCollections();

  runApp(
    ProviderScope(
      overrides: [
        libraryStoreProvider.overrideWithValue(store),
        libraryProvider.overrideWith(() => LibraryNotifier(initialBooks)),
        collectionsProvider.overrideWith(
          () => CollectionsNotifier(initialCollections),
        ),
      ],
      child: const PageTetherApp(),
    ),
  );
}
