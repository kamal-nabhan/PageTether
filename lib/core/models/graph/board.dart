import 'package:flutter/foundation.dart';

/// A spatial canvas holding [GraphNode]s/[GraphEdge]s.
///
/// A board is not necessarily tied to one book: [bookId] is nullable so a
/// board can be free-form/cross-book (e.g. a "research" canvas pulling
/// highlights from several books together), while [isDefaultForBook] marks
/// the one auto-created board a book's own highlights land on by default
/// (so opening a book's canvas for the first time doesn't require the user
/// to create one manually). Persisted locally via `LibraryStore` under
/// `pt.boards.v1` and synced via `SyncEngine.pushBoards`/`pullBoards` against
/// the `pt_boards` table (see `schema.sql`).
@immutable
class Board {
  Board({
    required this.id,
    required this.title,
    this.bookId,
    this.isDefaultForBook = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  /// Opaque, practically-unique id — see `generateGraphId` (`graph_ids.dart`).
  final String id;

  final String title;

  /// The single book this board belongs to, or null for a free-form/
  /// cross-book board.
  final String? bookId;

  /// True for the one board auto-created as a given book's default canvas
  /// (see [bookId]) — meaningless (and expected false) when [bookId] is
  /// null.
  final bool isDefaultForBook;

  final DateTime createdAt;

  /// Last-write-wins clock for sync — see `SyncEngine.pushBoards`/
  /// `BoardsNotifier.mergeRemoteBoards`, mirroring `Book.updatedAt`'s doc.
  final DateTime updatedAt;

  Board copyWith({
    String? title,
    String? bookId,
    bool? isDefaultForBook,
    DateTime? updatedAt,
  }) => Board(
    id: id,
    title: title ?? this.title,
    bookId: bookId ?? this.bookId,
    isDefaultForBook: isDefaultForBook ?? this.isDefaultForBook,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'bookId': bookId,
    'isDefaultForBook': isDefaultForBook,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Defensive against missing fields — see `GraphNode.fromJson`'s doc for
  /// the same stance.
  factory Board.fromJson(Map<String, dynamic> json) {
    final updatedAt =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final createdAt =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updatedAt;
    return Board(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled board',
      bookId: json['bookId'] as String?,
      isDefaultForBook: json['isDefaultForBook'] as bool? ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
