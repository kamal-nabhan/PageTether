import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

import '../../core/models/sync_credentials.dart';
import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/sync/sync_engine.dart';
import '../../core/storage/library_store.dart';
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

  /// Builds a throwaway [SyncEngine] from whatever's currently saved in
  /// [syncCredentialsProvider], runs [SyncEngine.testConnection], and always
  /// disposes it afterwards — see `SyncEngine`'s class doc for why disposal
  /// matters (it owns a JSON isolate + a realtime socket internally).
  Future<void> test() async {
    final credentials = ref.read(syncCredentialsProvider);
    state = const SyncConnectionTesting();
    final engine = SyncEngine(credentials);
    try {
      final result = await engine.testConnection();
      state = switch (result.status) {
        SyncConnectionStatus.notConfigured => const SyncConnectionNotConfigured(),
        SyncConnectionStatus.connected => const SyncConnectionOk(),
        SyncConnectionStatus.error => SyncConnectionFailed(
          result.message ?? 'Unknown error',
        ),
      };
    } finally {
      await engine.dispose();
    }
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

/// Orchestrates a full manual "Sync now": push this device's books +
/// collections to Supabase, then pull the remote state and merge it back in
/// (see `LibraryNotifier.mergeRemoteBooks`/
/// `CollectionsNotifier.mergeRemoteCollections` for the last-write-wins
/// merge itself). Deliberately sequential and one-shot — no automatic/
/// background sync yet (that's Phase 4b).
class SyncNotifier extends Notifier<SyncRunState> {
  @override
  SyncRunState build() => const SyncRunIdle();

  Future<void> syncNow() async {
    final credentials = ref.read(syncCredentialsProvider);
    if (!credentials.isConfigured) {
      state = const SyncRunError(
        'Add your Supabase URL and anon key below, then run schema.sql in '
        'your Supabase project, before syncing.',
      );
      return;
    }

    final userId = ref.read(authProvider.notifier).syncUserId;
    if (userId == null) {
      state = const SyncRunError(
        'Sign in to sync — connect your Google account first (from the '
        'library sidebar/Drive menu).',
      );
      return;
    }

    state = const SyncRunInProgress('Pulling remote changes…');
    final engine = SyncEngine(credentials);
    try {
      // Pull + merge BEFORE pushing. pushBooks/pushCollections upsert this
      // device's rows unconditionally (no updated_at comparison), so pushing
      // first would overwrite a *newer* device's remote values (e.g. a reading
      // position advanced elsewhere) with this device's possibly-stale ones.
      // Pulling + merging first (last-write-wins — see mergeRemoteBooks) makes
      // local hold the newest of (local, remote) per row; the push below then
      // writes that already-newest state back, so nothing newer is clobbered.
      final remoteBooks = await engine.pullBooks(userId);
      final remoteCollections = await engine.pullCollections(userId);

      final bookMerge = ref
          .read(libraryProvider.notifier)
          .mergeRemoteBooks(remoteBooks);
      final collectionMerge = ref
          .read(collectionsProvider.notifier)
          .mergeRemoteCollections(remoteCollections);

      state = const SyncRunInProgress('Pushing local changes…');
      final books = ref.read(libraryProvider);
      final collections = ref.read(collectionsProvider);
      await engine.pushBooks(userId, books);
      await engine.pushCollections(userId, collections);

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
      state = SyncRunSuccess(parts.join(' '));
    } on PostgrestException catch (e) {
      state = SyncRunError('Sync failed: ${e.message}');
    } catch (e) {
      state = SyncRunError('Sync failed: $e');
    } finally {
      await engine.dispose();
    }
  }

  void dismiss() => state = const SyncRunIdle();
}

final syncRunProvider = NotifierProvider<SyncNotifier, SyncRunState>(
  SyncNotifier.new,
);
