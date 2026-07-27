import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../models/collection.dart';
import '../models/library_view_mode.dart';
import '../models/sync_credentials.dart';

/// Local persistence for the library's book metadata and user-defined
/// collections.
///
/// Backed by [SharedPreferences] as the interim local store for Phase 1.1
/// (a proper database arrives in a later sync phase — this is intentionally
/// simple). Everything lives under one JSON object mapping each book's
/// content id (see `pdf_hash.dart`) to its serialized record, so a single
/// key holds the whole library. Collections (see `core/models/collection.dart`)
/// are a separate, much smaller list under their own key — there's no need
/// for the per-record upsert/remove [loadAll]/[upsert]/[remove] give books,
/// since the whole collection list is always small enough to load/save in
/// one shot (see [loadCollections]/[saveCollections]).
class LibraryStore {
  LibraryStore(this._prefs);

  static const _key = 'pt.library.v1';
  static const _collectionsKey = 'pt.collections.v1';
  static const _viewModeKey = 'pt.viewmode.v1';
  // Phase 4a: BYOD Supabase URL + anon key, pasted by the user in Settings.
  // The anon key is user-provided and local-only — never bundled/committed —
  // same trust model as `credentials.json`/the desktop Drive token cache
  // (see `.gitignore` and `core/services/auth/desktop_drive_auth_io.dart`),
  // just persisted in shared_preferences instead of a file since it's
  // small and user-editable rather than an opaque OAuth blob.
  static const _syncCredentialsKey = 'pt.sync.credentials.v1';

  final SharedPreferences _prefs;

  /// Loads every persisted book, most-recently-opened first.
  Future<List<Book>> loadAll() async {
    final decoded = _readMap();
    final books = decoded.values
        .map((entry) => Book.fromJson(entry as Map<String, dynamic>))
        .toList();
    books.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return books;
  }

  /// Inserts or updates a single book record in place.
  Future<void> upsert(Book book) async {
    final decoded = _readMap();
    decoded[book.id] = book.toJson();
    await _writeMap(decoded);
  }

  /// Deletes a single book record, mirroring [upsert]. No-op if [id] isn't
  /// present.
  Future<void> remove(String id) async {
    final decoded = _readMap();
    if (decoded.remove(id) == null) return;
    await _writeMap(decoded);
  }

  /// Replaces the entire persisted library with [books].
  Future<void> saveAll(List<Book> books) async {
    await _writeMap({for (final book in books) book.id: book.toJson()});
  }

  /// Loads every persisted [Collection], in whatever order they were saved
  /// (creation order — see `CollectionsNotifier.create`).
  Future<List<Collection>> loadCollections() async {
    final raw = _prefs.getString(_collectionsKey);
    if (raw == null || raw.isEmpty) return <Collection>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((entry) => Collection.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Mirrors _readMap's corrupt-data fallback: never crash startup over
      // bad local data — start with no collections instead.
      return <Collection>[];
    }
  }

  /// Replaces the entire persisted collection list with [collections].
  Future<void> saveCollections(List<Collection> collections) async {
    await _prefs.setString(
      _collectionsKey,
      jsonEncode([for (final c in collections) c.toJson()]),
    );
  }

  /// Loads the persisted library view mode (list vs. grid density — see
  /// [LibraryViewMode]), defaulting to [LibraryViewMode.gridMedium] —
  /// today's look — if nothing has been saved yet, or the saved value is
  /// unrecognized (e.g. from a future app version rolled back).
  Future<LibraryViewMode> loadViewMode() async {
    final raw = _prefs.getString(_viewModeKey);
    if (raw == null) return LibraryViewMode.gridMedium;
    return LibraryViewMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => LibraryViewMode.gridMedium,
    );
  }

  /// Persists the user's chosen library view mode.
  Future<void> saveViewMode(LibraryViewMode mode) async {
    await _prefs.setString(_viewModeKey, mode.name);
  }

  /// Loads the user's pasted-in Supabase URL/anon key, or
  /// [SyncCredentials.empty] if nothing has been saved (or Settings was used
  /// to disconnect — see [clearSyncCredentials]).
  Future<SyncCredentials> loadSyncCredentials() async {
    final raw = _prefs.getString(_syncCredentialsKey);
    if (raw == null || raw.isEmpty) return SyncCredentials.empty;
    try {
      return SyncCredentials.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return SyncCredentials.empty;
    }
  }

  /// Persists [credentials] as-is (no validation — see
  /// `SyncEngine.testConnection` for that).
  Future<void> saveSyncCredentials(SyncCredentials credentials) async {
    await _prefs.setString(
      _syncCredentialsKey,
      jsonEncode(credentials.toJson()),
    );
  }

  /// "Disconnect": forgets the locally-stored Supabase credentials. Does
  /// not touch anything on the Supabase project itself.
  Future<void> clearSyncCredentials() async {
    await _prefs.remove(_syncCredentialsKey);
  }

  Map<String, dynamic> _readMap() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Corrupt/incompatible local data should never crash the app — start
      // fresh instead of throwing.
      return <String, dynamic>{};
    }
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    await _prefs.setString(_key, jsonEncode(map));
  }
}
