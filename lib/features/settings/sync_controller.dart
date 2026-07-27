import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
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
    // favorite toggle, collection membership, a rename, a Drive
    // add/remove, or (via `collectionsProvider`) a collection
    // create/rename/delete. See `_scheduleDebouncedAutoSync`'s doc for the
    // in-flight-sync guard that keeps this from ever re-triggering off its
    // own pull+merge.
    //
    // Reading *position* specifically is deliberately excluded here (see
    // [_isReadingPositionOnlyChange]) now that `ReaderScreen` owns pushing
    // its own book's row on a 4s dwell timer (and once more on close) — a
    // page turn would otherwise also debounce a redundant full-library
    // push a few seconds later for no benefit.
    ref.listen(libraryProvider, (previous, next) {
      if (_isReadingPositionOnlyChange(previous, next)) return;
      _scheduleDebouncedAutoSync();
    });
    ref.listen(collectionsProvider, (previous, next) {
      _scheduleDebouncedAutoSync();
    });
  }

  /// True when every book present in both [previous] and [next] differs, if
  /// at all, only in the fields `ReaderScreen.recordProgress` touches
  /// (`currentPage`/`pageCount`/`lastOpenedAt`/`updatedAt`) — i.e. this
  /// state change is purely a page turn, already covered by the reader's own
  /// per-book push. False (schedule normally) for a book add/remove, any
  /// other field changing, or when [previous] is null (nothing to diff
  /// against yet).
  bool _isReadingPositionOnlyChange(List<Book>? previous, List<Book> next) {
    if (previous == null || previous.length != next.length) return false;
    final previousById = {for (final b in previous) b.id: b};
    for (final book in next) {
      final prior = previousById[book.id];
      if (prior == null) return false;
      if (_differsBeyondReadingPosition(prior, book)) return false;
    }
    return true;
  }

  bool _differsBeyondReadingPosition(Book a, Book b) {
    return a.title != b.title ||
        a.author != b.author ||
        a.coverGradientIndex != b.coverGradientIndex ||
        a.coverThumbnail != b.coverThumbnail ||
        a.assetPath != b.assetPath ||
        a.filePath != b.filePath ||
        a.fileBytes != b.fileBytes ||
        a.openedOnWeb != b.openedOnWeb ||
        a.source != b.source ||
        a.driveFileId != b.driveFileId ||
        a.driveSizeBytes != b.driveSizeBytes ||
        a.isFavorite != b.isFavorite ||
        !setEquals(a.collectionIds, b.collectionIds);
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
    final configured = ref.read(syncCredentialsProvider).isConfigured;
    final auth = ref.read(authProvider);
    final canSync = auth is AuthStateSignedIn && auth.canSync;
    if (!configured || !canSync) return;
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
