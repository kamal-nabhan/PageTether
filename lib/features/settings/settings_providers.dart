import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../../core/models/book.dart';
import '../../core/models/collection.dart';
import '../../core/models/sync_credentials.dart';
import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/sync/sync_engine.dart';
import '../../core/storage/library_store.dart';
import '../graph/graph_providers.dart';
import '../library/library_providers.dart';

/// Holds the user's pasted-in Supabase URL/anon key (see
/// `core/models/sync_credentials.dart`). Seeded in `main()` with whatever
/// [LibraryStore] already had saved, mirroring `ViewModeNotifier`'s
/// constructor-seeded pattern, so Settings shows the right thing on the very
/// first frame.
class SyncCredentialsNotifier extends Notifier<SyncCredentials> {
  SyncCredentialsNotifier([this._initial = SyncCredentials.empty]);

  final SyncCredentials _initial;

  @override
  SyncCredentials build() => _initial;

  LibraryStore get _store => ref.read(libraryStoreProvider);

  /// Persists [url]/[anonKey] (trimmed) as the active credentials. Does not
  /// validate them — see [SyncConnectionNotifier.test] for that.
  Future<void> save(String url, String anonKey) async {
    final credentials = SyncCredentials(url: url.trim(), anonKey: anonKey.trim());
    state = credentials;
    await _store.saveSyncCredentials(credentials);
  }

  /// "Disconnect": forgets the locally-stored credentials. Doesn't touch
  /// anything on the Supabase project itself.
  Future<void> clear() async {
    state = SyncCredentials.empty;
    await _store.clearSyncCredentials();
  }
}

final syncCredentialsProvider =
    NotifierProvider<SyncCredentialsNotifier, SyncCredentials>(
      SyncCredentialsNotifier.new,
    );

/// The ONE shared, long-lived `SupabaseClient` used by every sync path —
/// the full-library `SyncNotifier`/`SyncController` sync and `ReaderScreen`'s
/// per-book read/write loop alike (see `SyncEngine`'s class doc). Null while
/// [syncCredentialsProvider] isn't configured; callers must check that
/// before reading this.
///
/// `SupabaseClient` eagerly spins up a JSON-decoding isolate and a realtime
/// socket internally at construction time — building (and disposing) a
/// fresh one for every push/pull, as the Phase 4a/4b code did, was the root
/// cause of the reader visibly lagging on every page turn. This provider
/// instead builds exactly one client and keeps it alive for as long as
/// [syncCredentialsProvider]'s value doesn't change: watching that provider
/// means Riverpod disposes the old client (via [Ref.onDispose] below) and
/// rebuilds a new one only when the user actually edits/clears their
/// Supabase URL or anon key, never per sync operation.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final credentials = ref.watch(syncCredentialsProvider);
  if (!credentials.isConfigured) return null;
  final client = SupabaseClient(credentials.url.trim(), credentials.anonKey.trim());
  ref.onDispose(() {
    unawaited(client.dispose());
  });
  return client;
});

/// Status of the Settings screen's "Test connection" action.
sealed class SyncConnectionState {
  const SyncConnectionState();
}

class SyncConnectionUnknown extends SyncConnectionState {
  const SyncConnectionUnknown();
}

class SyncConnectionTesting extends SyncConnectionState {
  const SyncConnectionTesting();
}

class SyncConnectionOk extends SyncConnectionState {
  const SyncConnectionOk();
}

class SyncConnectionNotConfigured extends SyncConnectionState {
  const SyncConnectionNotConfigured();
}

class SyncConnectionFailed extends SyncConnectionState {
  const SyncConnectionFailed(this.message);
  final String message;
}

class SyncConnectionNotifier extends Notifier<SyncConnectionState> {
  @override
  SyncConnectionState build() => const SyncConnectionUnknown();

  /// Runs [SyncEngine.testConnection] against the shared
  /// [supabaseClientProvider] client. No disposal needed here — that client
  /// is long-lived and owned by [supabaseClientProvider] itself (see its
  /// doc), not by this one-off check.
  Future<void> test() async {
    final credentials = ref.read(syncCredentialsProvider);
    if (!credentials.isConfigured) {
      state = const SyncConnectionNotConfigured();
      return;
    }
    state = const SyncConnectionTesting();
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      state = const SyncConnectionNotConfigured();
      return;
    }
    final result = await SyncEngine(client).testConnection();
    state = switch (result.status) {
      SyncConnectionStatus.notConfigured => const SyncConnectionNotConfigured(),
      SyncConnectionStatus.connected => const SyncConnectionOk(),
      SyncConnectionStatus.error => SyncConnectionFailed(
        result.message ?? 'Unknown error',
      ),
    };
  }

  void reset() => state = const SyncConnectionUnknown();
}

final syncConnectionProvider =
    NotifierProvider<SyncConnectionNotifier, SyncConnectionState>(
      SyncConnectionNotifier.new,
    );

/// Status of the manual "Sync now" action (see `SyncNotifier.syncNow`).
sealed class SyncRunState {
  const SyncRunState();
}

class SyncRunIdle extends SyncRunState {
  const SyncRunIdle();
}

class SyncRunInProgress extends SyncRunState {
  const SyncRunInProgress(this.message);
  final String message;
}

class SyncRunSuccess extends SyncRunState {
  const SyncRunSuccess(this.summary);
  final String summary;
}

class SyncRunError extends SyncRunState {
  const SyncRunError(this.message);
  final String message;
}

/// Subtle background-sync status (Phase 4b) — deliberately separate from
/// [SyncRunState]: that one drives the manual "Sync now" button (progress
/// text, a dismissible success/error banner) and must stay exactly as it
/// was in Phase 4a, while this one is updated by *every* sync attempt
/// (manual or automatic) and is meant to be glanced at, never blocking or
/// dismissible — see the sidebar/Settings "Synced · just now" indicator.
/// [AutoSyncFailed] in particular is intentionally quiet: background sync
/// errors (offline, transient network blips) are simply retried on the next
/// trigger, never surfaced as an alarming banner.
sealed class AutoSyncStatus {
  const AutoSyncStatus();
}

class AutoSyncIdle extends AutoSyncStatus {
  const AutoSyncIdle();
}

class AutoSyncSyncing extends AutoSyncStatus {
  const AutoSyncSyncing();
}

class AutoSyncSynced extends AutoSyncStatus {
  const AutoSyncSynced(this.at);
  final DateTime at;
}

class AutoSyncFailed extends AutoSyncStatus {
  const AutoSyncFailed(this.message);
  final String message;
}

class AutoSyncStatusNotifier extends Notifier<AutoSyncStatus> {
  @override
  AutoSyncStatus build() => const AutoSyncIdle();

  void setSyncing() => state = const AutoSyncSyncing();
  void setSynced() => state = AutoSyncSynced(DateTime.now());
  void setFailed(String message) => state = AutoSyncFailed(message);
}

final autoSyncStatusProvider =
    NotifierProvider<AutoSyncStatusNotifier, AutoSyncStatus>(
      AutoSyncStatusNotifier.new,
    );

/// A short "just now"/"5m ago"/"2h ago" label for [AutoSyncSynced.at], used
/// by the subtle sync-status indicator in the library sidebar and Settings.
String formatSyncAge(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Orchestrates a full "Sync now": pull the remote state and merge it in
/// (last-write-wins — see `LibraryNotifier.mergeRemoteBooks`/
/// `CollectionsNotifier.mergeRemoteCollections`), THEN push this device's
/// now-newest books + collections back. [syncNow] is the Phase 4a manual
/// button; [autoSync] (Phase 4b) is the identical routine invoked silently
/// by `library_screen.dart`'s become-ready/resume/debounced-change triggers.
/// Both funnel through [_runExclusive]/[_performSync] below, so there is
/// exactly one LWW-safe pull+merge-then-push implementation regardless of
/// what triggered it.
class SyncNotifier extends Notifier<SyncRunState> {
  @override
  SyncRunState build() => const SyncRunIdle();

  /// Non-null while a sync (manual or automatic) is running. Together with
  /// [_dirty] this is the single-in-flight coalescing gate: a request that
  /// arrives while [_inFlight] is already set never starts a second,
  /// overlapping sync — it just marks [_dirty] and shares the same future.
  Future<void>? _inFlight;

  /// Set when a sync is requested while one is already [_inFlight] — makes
  /// the running loop immediately run one more pass once it finishes,
  /// instead of dropping the request that arrived mid-sync.
  bool _dirty = false;

  /// True whenever a sync — manual or automatic — is currently running.
  /// `library_screen.dart` checks this before scheduling a *new* debounced
  /// auto-sync in response to a `libraryProvider`/`collectionsProvider`
  /// change: a change observed while a sync is already in flight is either
  /// that very sync's own pull+merge landing (which must not re-trigger
  /// itself — see the "no sync loop" requirement) or a genuine concurrent
  /// edit that this in-flight sync's push will already pick up (it reads
  /// book/collection state fresh, right before pushing).
  bool get isSyncing => _inFlight != null;

  /// User-triggered "Sync now" (Settings). Surfaces progress/result via
  /// [state] exactly as in Phase 4a.
  Future<void> syncNow() => _runExclusive(silent: false);

  /// Every Phase 4b automatic trigger (on becoming ready, on app
  /// resume/desktop focus, debounced after a local change) calls this. Runs
  /// the identical pull+merge-then-push routine but never touches [state]
  /// — so it can never pop up the manual button's error banner — and never
  /// throws: failures are quietly recorded on [autoSyncStatusProvider] and
  /// simply retried on the next trigger.
  Future<void> autoSync() => _runExclusive(silent: true);

  /// Coalesces concurrent sync requests into a single in-flight run — see
  /// [isSyncing]'s doc. If a sync is already running, this marks it dirty
  /// and returns that same in-flight future rather than starting a second,
  /// overlapping one; [_runLoop] below then runs once more before settling.
  Future<void> _runExclusive({required bool silent}) {
    final existing = _inFlight;
    if (existing != null) {
      _dirty = true;
      return existing;
    }
    final future = _runLoop(silent: silent);
    _inFlight = future;
    return future;
  }

  Future<void> _runLoop({required bool silent}) async {
    try {
      do {
        _dirty = false;
        await _performSync(silent: silent);
      } while (_dirty);
    } finally {
      _inFlight = null;
    }
  }

  /// The actual pull+merge-then-push routine, shared by every manual and
  /// automatic trigger (always runs under [_runExclusive]'s exclusivity —
  /// see that method's doc). When [silent] is true (every [autoSync] call),
  /// [state] (the manual button's state machine) is never touched and no
  /// exception ever escapes — only [autoSyncStatusProvider] reflects the
  /// outcome.
  Future<void> _performSync({required bool silent}) async {
    final credentials = ref.read(syncCredentialsProvider);
    if (!credentials.isConfigured) {
      if (!silent) {
        state = const SyncRunError(
          'Add your Supabase URL and anon key below, then run schema.sql in '
          'your Supabase project, before syncing.',
        );
      }
      return;
    }

    final userId = ref.read(authProvider.notifier).syncUserId;
    if (userId == null) {
      if (!silent) {
        state = const SyncRunError(
          'Sign in to sync — connect your Google account first (from the '
          'library sidebar/Drive menu).',
        );
      }
      return;
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      // Shouldn't happen — `credentials.isConfigured` was just checked above
      // and `supabaseClientProvider` builds a client whenever that's true —
      // but fail quietly rather than crash if it ever does.
      if (!silent) {
        state = const SyncRunError(
          'Add your Supabase URL and anon key below, then run schema.sql in '
          'your Supabase project, before syncing.',
        );
      }
      return;
    }

    if (!silent) state = const SyncRunInProgress('Pulling remote changes…');
    final autoStatus = ref.read(autoSyncStatusProvider.notifier);
    autoStatus.setSyncing();
    final engine = SyncEngine(client);
    try {
      // Pull + merge BEFORE pushing. pushBooks/pushCollections upsert this
      // device's rows unconditionally (no updated_at comparison), so pushing
      // first would overwrite a *newer* device's remote values (e.g. a reading
      // position advanced elsewhere) with this device's possibly-stale ones.
      // Pulling + merging first (last-write-wins — see mergeRemoteBooks) makes
      // local hold the newest of (local, remote) per row; the push below then
      // writes that already-newest state back, so nothing newer is clobbered.
      // Boards/nodes/edges (the annotation graph model) follow the exact same
      // pull+merge-then-push order, for the exact same reason — see
      // BoardsNotifier/GraphNodesNotifier/GraphEdgesNotifier.mergeRemote*.
      final remoteBooks = await engine.pullBooks(userId);
      final remoteCollections = await engine.pullCollections(userId);
      final remoteBoards = await engine.pullBoards(userId);
      final remoteNodes = await engine.pullNodes(userId);
      final remoteEdges = await engine.pullEdges(userId);

      final bookMerge = ref
          .read(libraryProvider.notifier)
          .mergeRemoteBooks(remoteBooks);
      final collectionMerge = ref
          .read(collectionsProvider.notifier)
          .mergeRemoteCollections(remoteCollections);
      ref.read(boardsProvider.notifier).mergeRemoteBoards(remoteBoards);
      ref.read(graphNodesProvider.notifier).mergeRemoteNodes(remoteNodes);
      ref.read(graphEdgesProvider.notifier).mergeRemoteEdges(remoteEdges);

      if (!silent) state = const SyncRunInProgress('Pushing local changes…');
      final books = ref.read(libraryProvider);
      final collections = ref.read(collectionsProvider);
      await engine.pushBooks(userId, books);
      await engine.pushCollections(userId, collections);
      await engine.pushBoards(userId, ref.read(boardsProvider));
      await engine.pushNodes(userId, ref.read(graphNodesProvider));
      await engine.pushEdges(userId, ref.read(graphEdgesProvider));

      autoStatus.setSynced();
      if (!silent) {
        state = SyncRunSuccess(
          _summarize(books, collections, bookMerge, collectionMerge),
        );
      }
    } on PostgrestException catch (e) {
      autoStatus.setFailed(e.message);
      if (!silent) state = SyncRunError('Sync failed: ${e.message}');
    } catch (e) {
      autoStatus.setFailed('$e');
      if (!silent) state = SyncRunError('Sync failed: $e');
    }
  }

  String _summarize(
    List<Book> books,
    List<Collection> collections,
    ({int added, int updated}) bookMerge,
    ({int added, int updated}) collectionMerge,
  ) {
    final parts = <String>[
      'Pushed ${books.length} book${books.length == 1 ? '' : 's'} and '
          '${collections.length} collection${collections.length == 1 ? '' : 's'}.',
    ];
    if (bookMerge.added > 0 || bookMerge.updated > 0) {
      parts.add(
        '${bookMerge.added} new book${bookMerge.added == 1 ? '' : 's'}, '
        '${bookMerge.updated} updated from another device.',
      );
    }
    if (collectionMerge.added > 0 || collectionMerge.updated > 0) {
      parts.add(
        '${collectionMerge.added} new collection'
        '${collectionMerge.added == 1 ? '' : 's'}, '
        '${collectionMerge.updated} updated from another device.',
      );
    }
    if (bookMerge.added == 0 &&
        bookMerge.updated == 0 &&
        collectionMerge.added == 0 &&
        collectionMerge.updated == 0) {
      parts.add('Nothing new from other devices.');
    }
    return parts.join(' ');
  }

  void dismiss() => state = const SyncRunIdle();
}

final syncRunProvider = NotifierProvider<SyncNotifier, SyncRunState>(
  SyncNotifier.new,
);
