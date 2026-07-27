import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/auth/auth_state.dart';
import '../library/library_providers.dart';
import 'settings_providers.dart';

/// App-level owner of the Phase 4b automatic-sync triggers.
///
/// **Why this exists**: Phase 4b originally wired its auto-sync triggers as
/// widget-scoped `ref.listen`s inside `_LibraryScreenState`
/// (`library_screen.dart`). That works fine for changes made *while the
/// library screen itself is the current route*, but reading happens in
/// [ReaderScreen] (`features/reader/reader_screen.dart`), pushed on top of
/// the library via `Navigator.push` — a separate route, not a rebuild of
/// `LibraryScreen`. A reading-position change there calls
/// `libraryProvider.notifier.recordProgress`, which correctly updates
/// `libraryProvider`'s state, but `LibraryScreen`'s `ref.listen`s don't
/// reliably drive the debounced auto-push while some other screen is on top
/// — so progress made in the reader was never auto-pushed, and only the
/// manual "Sync now" button (which reads state fresh regardless of route)
/// worked.
///
/// The fix: move the "on becoming ready" and "on local change" triggers into
/// this plain (non-autoDispose) [Notifier], instantiated once at app root
/// (see `app.dart`) so it's alive for the entire app session regardless of
/// which route is on top. `ref.listen` on a provider-level [Notifier] fires
/// for every state change anywhere in the app, not just while some
/// particular widget happens to be mounted — so a `recordProgress` call from
/// deep inside [ReaderScreen] now reaches the same debounced auto-push as a
/// favorite toggle made from the library grid.
///
/// The resume/app-focus trigger (Phase 4b trigger #2) deliberately stays in
/// `_LibraryScreenState` — it's a foreground/lifecycle event tied to a
/// widget observer (`WidgetsBindingObserver`/the desktop `window_focus`
/// listener), not a state change, so it doesn't have the same "wrong route"
/// problem this controller fixes.
class SyncController extends Notifier<void> {
  /// Debounce for auto-sync-on-local-change: coalesces a burst of edits
  /// (e.g. flipping through pages, several favorite toggles) into one sync a
  /// few seconds after the *last* one, rather than a sync per edit. Mirrors
  /// the constant this replaces in `_LibraryScreenState`.
  static const _autoSyncPushDebounce = Duration(seconds: 5);

  Timer? _debounceTimer;

  @override
  void build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });

    // Trigger #1: the moment `canSync` (Supabase configured + signed in to
    // Google) first becomes true — right after connecting *either* half,
    // whichever happens second — kick off one sync immediately rather than
    // waiting for the next resume/local-change trigger.
    ref.listen<AuthState>(authProvider, (previous, next) {
      final couldSyncBefore = previous is AuthStateSignedIn && previous.canSync;
      final canSyncNow = next is AuthStateSignedIn && next.canSync;
      if (canSyncNow && !couldSyncBefore && _canAutoSync()) {
        _autoSync();
      }
    });

    // The other half of trigger #1: saving Supabase credentials while
    // already signed in to Google.
    ref.listen(syncCredentialsProvider, (previous, next) {
      final wasConfigured = previous?.isConfigured ?? false;
      if (next.isConfigured && !wasConfigured && _canAutoSync()) {
        _autoSync();
      }
    });

    // Trigger #3: debounced auto-push after a local syncable change —
    // reading progress (including from `ReaderScreen`, which is the whole
    // point of moving this here), favorite toggle, collection membership, a
    // rename, or (via `collectionsProvider`) a collection
    // create/rename/delete. See `_scheduleDebouncedAutoSync`'s doc for the
    // in-flight-sync guard that keeps this from ever re-triggering off its
    // own pull+merge.
    ref.listen(libraryProvider, (previous, next) {
      _scheduleDebouncedAutoSync();
    });
    ref.listen(collectionsProvider, (previous, next) {
      _scheduleDebouncedAutoSync();
    });
  }

  /// Whether Phase 4b auto-sync is allowed to run at all right now: a
  /// Supabase project is configured *and* the user is signed in to Google
  /// (see `AuthStateSignedIn.canSync`) — the same gate `SyncNotifier` itself
  /// re-checks before doing any network work, kept here too so callers can
  /// skip even scheduling a debounce timer when it's pointless.
  bool _canAutoSync() {
    final credentials = ref.read(syncCredentialsProvider);
    final authState = ref.read(authProvider);
    final canSync = authState is AuthStateSignedIn && authState.canSync;
    return credentials.isConfigured && canSync;
  }

  /// Schedules (or reschedules) the debounced trigger-#3 auto-push. Skips
  /// scheduling entirely while a sync is already running
  /// (`SyncNotifier.isSyncing`) — that covers both a change that's actually
  /// this sync's own pull+merge landing (see `SyncNotifier.isSyncing`'s doc
  /// for why that can't be allowed to re-trigger itself) and a genuine
  /// concurrent edit, which the in-flight sync's push will already pick up.
  void _scheduleDebouncedAutoSync() {
    if (!_canAutoSync()) return;
    if (ref.read(syncRunProvider.notifier).isSyncing) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_autoSyncPushDebounce, _autoSync);
  }

  void _autoSync() {
    ref.read(syncRunProvider.notifier).autoSync();
  }
}

/// Instantiate (e.g. via `ref.watch`) once, at app root — see `app.dart` —
/// so this stays alive for the whole app session. A plain `NotifierProvider`
/// like this one is never auto-disposed by Riverpod, but it's also never
/// *created* until something reads/watches it at least once, so it must
/// actually be watched somewhere always-mounted (not, say, only from within
/// `LibraryScreen`, which is exactly the bug this controller fixes).
final syncControllerProvider = NotifierProvider<SyncController, void>(
  SyncController.new,
);
