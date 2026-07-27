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
/// "Connected" / "Error: …" without its own try/catch. [notConfigured] is
/// never produced by [SyncEngine.testConnection] itself (callers already
/// hold a `SupabaseClient` by the time they build a [SyncEngine] — see that
/// class's doc — so they check [SyncCredentials.isConfigured] beforehand);
/// it's kept here so callers that short-circuit before ever touching
/// [SyncEngine] can still report through the same three-way result type.
enum SyncConnectionStatus { notConfigured, connected, error }

class SyncConnectionResult {
  const SyncConnectionResult(this.status, [this.message]);

  final SyncConnectionStatus status;

  /// Set only for [SyncConnectionStatus.error] — the raw
  /// `PostgrestException`/socket-error message, shown as-is since it's
  /// already a short, actionable Postgres/HTTP error.
  final String? message;
}

/// Talks to `pt_books`/`pt_collections` (see `schema.sql`) over a
/// caller-supplied `SupabaseClient`; `pt_annotations` is defined in the
/// schema for Phase 5 but not touched here.
///
/// Unlike the Phase 4a/4b version of this class, a [SyncEngine] instance
/// does **not** own or build its own `SupabaseClient` — it's handed one
/// (see [supabaseClientProvider] in `features/settings/settings_providers.dart`).
/// `SupabaseClient` eagerly spins up a JSON-decoding isolate and a realtime
/// socket internally, so constructing (and disposing) a fresh one per
/// operation — as every push/pull previously did — is expensive enough to
/// visibly lag the UI; [supabaseClientProvider] instead builds exactly one,
/// long-lived client per set of credentials, shared by every sync path
/// (the reader's per-book read/write loop and the full-library
/// `SyncNotifier`/`SyncController`), and this class is now a thin,
/// stateless wrapper around whichever client it's given. A [SyncEngine]
/// itself is cheap to construct and never needs disposing — only the
/// shared client does.
class SyncEngine {
  const SyncEngine(this._client);

  final SupabaseClient _client;

  static const _booksTable = 'pt_books';
  static const _collectionsTable = 'pt_collections';

  /// A lightweight reachability + schema check: selects one row (if any)
  /// from `pt_books`. Callers check [SyncCredentials.isConfigured] (and thus
  /// whether a shared client even exists — see [supabaseClientProvider])
  /// before ever constructing a [SyncEngine], so this only ever
  /// distinguishes "connected" from "error" — the error case covers both a
  /// bad URL/key and a URL/key that's fine but `schema.sql` hasn't been run
  /// yet (surfaced as a Postgres "relation does not exist" message, which is
  /// itself a useful hint to the user).
  Future<SyncConnectionResult> testConnection() async {
    try {
      await _client.from(_booksTable).select('user_id').limit(1);
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
    await _client.from(_booksTable).upsert(rows, onConflict: 'user_id,book_id');
  }

  /// Every `pt_books` row belonging to [userId].
  Future<List<SyncedBook>> pullBooks(String userId) async {
    final rows = await _client.from(_booksTable).select().eq('user_id', userId);
    return [for (final row in rows) SyncedBook.fromRow(row)];
  }

  /// Single-row equivalent of [pullBooks], used by `ReaderScreen`'s per-book
  /// sync loop instead of pulling (and merging) every book in the library
  /// just to check on the one currently open. Returns null if [bookId] has
  /// no row yet for [userId] (e.g. never pushed from any device).
  Future<SyncedBook?> pullBook(String userId, String bookId) async {
    final rows = await _client
        .from(_booksTable)
        .select()
        .eq('user_id', userId)
        .eq('book_id', bookId)
        .limit(1);
    if (rows.isEmpty) return null;
    return SyncedBook.fromRow(rows.first);
  }

  /// Single-row equivalent of [pushBooks]: upserts [book] as one full
  /// `pt_books` row for [userId]. Deliberately writes every column
  /// [SyncedBook.toRow] knows about (title/author/current_page/page_count/
  /// is_favorite/drive_file_id/collection_ids/updated_at), not just
  /// `current_page` — an upsert of a partial row would otherwise null out
  /// every column this call doesn't mention for a book that already has a
  /// remote row. Used by `ReaderScreen`'s per-book dwell-timer push so a
  /// reading-position update doesn't require pushing the whole library.
  Future<void> pushBook(String userId, Book book) async {
    final row = SyncedBook.fromBook(book).toRow(userId);
    await _client.from(_booksTable).upsert(row, onConflict: 'user_id,book_id');
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
    await _client
        .from(_collectionsTable)
        .upsert(rows, onConflict: 'user_id,id');
  }

  /// Every `pt_collections` row belonging to [userId].
  Future<List<SyncedCollection>> pullCollections(String userId) async {
    final rows = await _client
        .from(_collectionsTable)
        .select()
        .eq('user_id', userId);
    return [for (final row in rows) SyncedCollection.fromRow(row)];
  }
}
