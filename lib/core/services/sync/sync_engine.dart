import 'package:supabase/supabase.dart';

import '../../models/book.dart';
import '../../models/collection.dart';
import '../../models/graph/board.dart';
import '../../models/graph/graph_edge.dart';
import '../../models/graph/graph_node.dart';
import '../../models/graph/graph_style.dart';
import '../../models/graph/node_anchor.dart';
import '../../models/graph/node_content.dart';
import '../../models/graph/node_kind.dart';
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

/// A `pt_boards` row (see `schema.sql`).
class SyncedBoard {
  const SyncedBoard({
    required this.id,
    required this.title,
    required this.bookId,
    required this.isDefaultForBook,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? bookId;
  final bool isDefaultForBook;
  final DateTime updatedAt;

  factory SyncedBoard.fromBoard(Board board) => SyncedBoard(
    id: board.id,
    title: board.title,
    bookId: board.bookId,
    isDefaultForBook: board.isDefaultForBook,
    updatedAt: board.updatedAt,
  );

  factory SyncedBoard.fromRow(Map<String, dynamic> row) => SyncedBoard(
    id: row['id'] as String,
    title: row['title'] as String? ?? '',
    bookId: row['book_id'] as String?,
    isDefaultForBook: row['is_default_for_book'] as bool? ?? false,
    updatedAt: _parseTimestamp(row['updated_at']),
  );

  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'id': id,
    'title': title,
    'book_id': bookId,
    'is_default_for_book': isDefaultForBook,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

/// A `pt_nodes` row (see `schema.sql`). Unlike [SyncedBook] this thins
/// nothing out — every [GraphNode] field except [GraphNode.createdAt] has a
/// column/JSON-column here, since [GraphNode.createdAt] is a purely local
/// concept (`pt_nodes` has no `created_at` column — see that table's comment
/// in `schema.sql`); merging a remote row back into a local [GraphNode]
/// therefore always keeps the local `createdAt` (see
/// `GraphNodesNotifier.mergeRemoteNodes`).
///
/// [deleted] carries [GraphNode.deleted] — a deleted node is never dropped
/// from `pt_nodes` by row deletion (there is no delete path anywhere in this
/// class); instead the tombstone rides along as an ordinary column and
/// propagates via the same last-write-wins upsert every other field does.
/// See [GraphNode]'s class doc.
class SyncedGraphNode {
  const SyncedGraphNode({
    required this.id,
    required this.boardId,
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.rotation,
    required this.z,
    required this.style,
    required this.content,
    required this.anchor,
    required this.contentText,
    required this.badge,
    required this.deleted,
    required this.updatedAt,
  });

  final String id;
  final String boardId;
  final NodeKind kind;
  final double x;
  final double y;
  final double w;
  final double h;
  final double rotation;
  final double z;
  final GraphStyle style;
  final NodeContent content;
  final NodeAnchor? anchor;
  final String contentText;
  final String? badge;
  final bool deleted;
  final DateTime updatedAt;

  factory SyncedGraphNode.fromNode(GraphNode node) => SyncedGraphNode(
    id: node.id,
    boardId: node.boardId,
    kind: node.kind,
    x: node.x,
    y: node.y,
    w: node.w,
    h: node.h,
    rotation: node.rotation,
    z: node.z,
    style: node.style,
    content: node.content,
    anchor: node.anchor,
    contentText: node.contentText,
    badge: node.badge,
    deleted: node.deleted,
    updatedAt: node.updatedAt,
  );

  factory SyncedGraphNode.fromRow(Map<String, dynamic> row) => SyncedGraphNode(
    id: row['id'] as String,
    boardId: row['board_id'] as String? ?? '',
    kind: NodeKind.values.firstWhere(
      (k) => k.name == row['kind'],
      orElse: () => NodeKind.textNote,
    ),
    x: (row['x'] as num?)?.toDouble() ?? 0,
    y: (row['y'] as num?)?.toDouble() ?? 0,
    w: (row['w'] as num?)?.toDouble() ?? 0,
    h: (row['h'] as num?)?.toDouble() ?? 0,
    rotation: (row['rotation'] as num?)?.toDouble() ?? 0,
    z: (row['z'] as num?)?.toDouble() ?? 0,
    style: GraphStyle.fromJson(row['style'] as Map<String, dynamic>?),
    content: NodeContent.fromJson(row['content'] as Map<String, dynamic>?),
    anchor: NodeAnchor.fromJson(row['anchor'] as Map<String, dynamic>?),
    contentText: row['content_text'] as String? ?? '',
    badge: row['badge'] as String?,
    deleted: row['deleted'] as bool? ?? false,
    updatedAt: _parseTimestamp(row['updated_at']),
  );

  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'id': id,
    'board_id': boardId,
    'kind': kind.name,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'rotation': rotation,
    'z': z,
    'style': style.toJson(),
    'content': content.toJson(),
    'anchor': anchor?.toJson(),
    'content_text': contentText,
    'badge': badge,
    'deleted': deleted,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

/// A `pt_edges` row (see `schema.sql`).
class SyncedGraphEdge {
  const SyncedGraphEdge({
    required this.id,
    required this.boardId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.kind,
    required this.label,
    required this.style,
    required this.updatedAt,
  });

  final String id;
  final String boardId;
  final String fromNodeId;
  final String toNodeId;
  final EdgeKind kind;
  final String? label;
  final GraphStyle style;
  final DateTime updatedAt;

  factory SyncedGraphEdge.fromEdge(GraphEdge edge) => SyncedGraphEdge(
    id: edge.id,
    boardId: edge.boardId,
    fromNodeId: edge.fromNodeId,
    toNodeId: edge.toNodeId,
    kind: edge.kind,
    label: edge.label,
    style: edge.style,
    updatedAt: edge.updatedAt,
  );

  factory SyncedGraphEdge.fromRow(Map<String, dynamic> row) => SyncedGraphEdge(
    id: row['id'] as String,
    boardId: row['board_id'] as String? ?? '',
    fromNodeId: row['from_node_id'] as String? ?? '',
    toNodeId: row['to_node_id'] as String? ?? '',
    kind: EdgeKind.values.firstWhere(
      (k) => k.name == row['kind'],
      orElse: () => EdgeKind.arrow,
    ),
    label: row['label'] as String?,
    style: GraphStyle.fromJson(row['style'] as Map<String, dynamic>?),
    updatedAt: _parseTimestamp(row['updated_at']),
  );

  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'id': id,
    'board_id': boardId,
    'from_node_id': fromNodeId,
    'to_node_id': toNodeId,
    'kind': kind.name,
    'label': label,
    'style': style.toJson(),
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

/// Talks to `pt_books`/`pt_collections`/`pt_boards`/`pt_nodes`/`pt_edges`
/// (see `schema.sql`) over a caller-supplied `SupabaseClient`;
/// `pt_annotations` predates the annotation-graph model (Boards/GraphNodes/
/// GraphEdges) it was superseded by and is not touched here.
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
  static const _boardsTable = 'pt_boards';
  static const _nodesTable = 'pt_nodes';
  static const _edgesTable = 'pt_edges';

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

  /// Upserts every one of [boards] as [userId]'s rows, keyed by
  /// `(user_id, id)` — see [pushBooks]'s doc for the same "overwrites
  /// outright" caveat.
  Future<void> pushBoards(String userId, List<Board> boards) async {
    if (boards.isEmpty) return;
    final rows = [
      for (final board in boards) SyncedBoard.fromBoard(board).toRow(userId),
    ];
    await _client.from(_boardsTable).upsert(rows, onConflict: 'user_id,id');
  }

  /// Every `pt_boards` row belonging to [userId].
  Future<List<SyncedBoard>> pullBoards(String userId) async {
    final rows = await _client
        .from(_boardsTable)
        .select()
        .eq('user_id', userId);
    return [for (final row in rows) SyncedBoard.fromRow(row)];
  }

  /// Upserts every one of [nodes] as [userId]'s rows, keyed by
  /// `(user_id, id)` — see [pushBooks]'s doc for the same "overwrites
  /// outright" caveat.
  Future<void> pushNodes(String userId, List<GraphNode> nodes) async {
    if (nodes.isEmpty) return;
    final rows = [
      for (final node in nodes) SyncedGraphNode.fromNode(node).toRow(userId),
    ];
    await _client.from(_nodesTable).upsert(rows, onConflict: 'user_id,id');
  }

  /// Every `pt_nodes` row belonging to [userId].
  Future<List<SyncedGraphNode>> pullNodes(String userId) async {
    final rows = await _client.from(_nodesTable).select().eq('user_id', userId);
    return [for (final row in rows) SyncedGraphNode.fromRow(row)];
  }

  /// Upserts every one of [edges] as [userId]'s rows, keyed by
  /// `(user_id, id)` — see [pushBooks]'s doc for the same "overwrites
  /// outright" caveat.
  Future<void> pushEdges(String userId, List<GraphEdge> edges) async {
    if (edges.isEmpty) return;
    final rows = [
      for (final edge in edges) SyncedGraphEdge.fromEdge(edge).toRow(userId),
    ];
    await _client.from(_edgesTable).upsert(rows, onConflict: 'user_id,id');
  }

  /// Every `pt_edges` row belonging to [userId].
  Future<List<SyncedGraphEdge>> pullEdges(String userId) async {
    final rows = await _client.from(_edgesTable).select().eq('user_id', userId);
    return [for (final row in rows) SyncedGraphEdge.fromRow(row)];
  }
}
