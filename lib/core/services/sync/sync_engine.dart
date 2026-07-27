import 'package:supabase/supabase.dart';

import '../../models/book.dart';
import '../../models/collection.dart';
import '../../models/sync_credentials.dart';

/// A `pt_books` row (see `schema.sql`) — a thinner, sync-only shape than
/// [Book]: no cover thumbnail, file path, in-memory bytes, or any other
/// local-only/session-only field, since those either can't be serialized
/// sensibly (raw PDF bytes) or are meaningless read back on another device
/// (a local file path). [updatedAt] is the last-write-wins clock — see
/// `Book.updatedAt`'s doc comment for what bumps it.
class SyncedBook {
  const SyncedBook({
    required this.bookId,
    required this.title,
    required this.author,
    required this.currentPage,
    required this.pageCount,
    required this.isFavorite,
    required this.driveFileId,
    required this.collectionIds,
    required this.updatedAt,
  });

  final String bookId;
  final String title;
  final String author;
  final int currentPage;
  final int pageCount;
  final bool isFavorite;
  final String? driveFileId;
  final Set<String> collectionIds;
  final DateTime updatedAt;

  factory SyncedBook.fromBook(Book book) => SyncedBook(
    bookId: book.id,
    title: book.title,
    author: book.author,
    currentPage: book.currentPage,
    pageCount: book.pageCount,
    isFavorite: book.isFavorite,
    driveFileId: book.driveFileId,
    collectionIds: book.collectionIds,
    updatedAt: book.updatedAt,
  );

  factory SyncedBook.fromRow(Map<String, dynamic> row) => SyncedBook(
    bookId: row['book_id'] as String,
    title: row['title'] as String? ?? '',
    author: row['author'] as String? ?? '',
    currentPage: row['current_page'] as int? ?? 1,
    pageCount: row['page_count'] as int? ?? 0,
    isFavorite: row['is_favorite'] as bool? ?? false,
    driveFileId: row['drive_file_id'] as String?,
    collectionIds: ((row['collection_ids'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toSet(),
    updatedAt: _parseTimestamp(row['updated_at']),
  );

  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'book_id': bookId,
    'title': title,
    'author': author,
    'current_page': currentPage,
    'page_count': pageCount,
    'is_favorite': isFavorite,
    'drive_file_id': driveFileId,
    'collection_ids': collectionIds.toList(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

/// A `pt_collections` row (see `schema.sql`).
class SyncedCollection {
  const SyncedCollection({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int colorIndex;
  final DateTime updatedAt;

  factory SyncedCollection.fromCollection(Collection collection) =>
      SyncedCollection(
        id: collection.id,
        name: collection.name,
        colorIndex: collection.colorIndex,
        updatedAt: collection.updatedAt,
      );

  factory SyncedCollection.fromRow(Map<String, dynamic> row) =>
      SyncedCollection(
        id: row['id'] as String,
        name: row['name'] as String? ?? 'Untitled collection',
        colorIndex: row['color_index'] as int? ?? 0,
        updatedAt: _parseTimestamp(row['updated_at']),
      );

  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'id': id,
    'name': name,
    'color_index': colorIndex,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

DateTime _parseTimestamp(Object? value) =>
    DateTime.tryParse(value as String? ?? '')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Outcome of [SyncEngine.testConnection] — a small closed set rather than a
/// bare exception, so the Settings screen can render "Not configured" /
/// "Connected" / "Error: …" without its own try/catch.
enum SyncConnectionStatus { notConfigured, connected, error }

class SyncConnectionResult {
  const SyncConnectionResult(this.status, [this.message]);

  final SyncConnectionStatus status;

  /// Set only for [SyncConnectionStatus.error] — the raw
  /// `PostgrestException`/socket-error message, shown as-is since it's
  /// already a short, actionable Postgres/HTTP error.
  final String? message;
}

/// Builds a `SupabaseClient` **at runtime** from a user-pasted
/// [SyncCredentials] (BYOD — see the Phase 4a plan), rather than via
/// `supabase_flutter`'s compile-time `Supabase.initialize` singleton, since
/// the URL/anon key aren't known until the user has typed them into
/// Settings. Talks to `pt_books`/`pt_collections` (see `schema.sql`);
/// `pt_annotations` is defined in the schema for Phase 5 but not touched
/// here.
///
/// One [SyncEngine] instance owns exactly one underlying `SupabaseClient`
/// (created lazily, on first use) — construction alone doesn't touch the
/// network. Callers **must** call [dispose] when done with an instance:
/// `SupabaseClient` eagerly spins up a JSON-decoding isolate and a realtime
/// socket internally, and only [dispose] tears those back down.
class SyncEngine {
  SyncEngine(this.credentials);

  final SyncCredentials credentials;

  static const _booksTable = 'pt_books';
  static const _collectionsTable = 'pt_collections';

  SupabaseClient? _client;

  SupabaseClient get _requireClient =>
      _client ??= SupabaseClient(credentials.url.trim(), credentials.anonKey.trim());

  Future<void> dispose() async {
    await _client?.dispose();
    _client = null;
  }

  /// A lightweight reachability + schema check: selects one row (if any)
  /// from `pt_books`. Distinguishes "not configured" (no URL/key saved yet)
  /// from "connected" from "error" — the error case covers both a bad
  /// URL/key and a URL/key that's fine but `schema.sql` hasn't been run yet
  /// (surfaced as a Postgres "relation does not exist" message, which is
  /// itself a useful hint to the user).
  Future<SyncConnectionResult> testConnection() async {
    if (!credentials.isConfigured) {
      return const SyncConnectionResult(SyncConnectionStatus.notConfigured);
    }
    try {
      await _requireClient.from(_booksTable).select('user_id').limit(1);
      return const SyncConnectionResult(SyncConnectionStatus.connected);
    } on PostgrestException catch (e) {
      return SyncConnectionResult(SyncConnectionStatus.error, e.message);
    } catch (e) {
      return SyncConnectionResult(SyncConnectionStatus.error, '$e');
    }
  }

  /// Upserts every one of [books] as [userId]'s rows, keyed by the
  /// `(user_id, book_id)` composite primary key — a book already known to
  /// Supabase is overwritten outright with this device's current values
  /// (this call doesn't itself compare `updated_at`; see `SyncEngine`'s
  /// class doc and `LibraryNotifier.syncNow` for how the two directions
  /// combine into last-write-wins). No-ops on an empty list rather than
  /// issuing a pointless request.
  Future<void> pushBooks(String userId, List<Book> books) async {
    if (books.isEmpty) return;
    final rows = [
      for (final book in books) SyncedBook.fromBook(book).toRow(userId),
    ];
    await _requireClient
        .from(_booksTable)
        .upsert(rows, onConflict: 'user_id,book_id');
  }

  /// Every `pt_books` row belonging to [userId].
  Future<List<SyncedBook>> pullBooks(String userId) async {
    final rows = await _requireClient
        .from(_booksTable)
        .select()
        .eq('user_id', userId);
    return [for (final row in rows) SyncedBook.fromRow(row)];
  }

  /// Upserts every one of [collections] as [userId]'s rows — see
  /// [pushBooks]'s doc comment for the same "overwrites outright" caveat.
  Future<void> pushCollections(
    String userId,
    List<Collection> collections,
  ) async {
    if (collections.isEmpty) return;
    final rows = [
      for (final collection in collections)
        SyncedCollection.fromCollection(collection).toRow(userId),
    ];
    await _requireClient
        .from(_collectionsTable)
        .upsert(rows, onConflict: 'user_id,id');
  }

  /// Every `pt_collections` row belonging to [userId].
  Future<List<SyncedCollection>> pullCollections(String userId) async {
    final rows = await _requireClient
        .from(_collectionsTable)
        .select()
        .eq('user_id', userId);
    return [for (final row in rows) SyncedCollection.fromRow(row)];
  }
}
