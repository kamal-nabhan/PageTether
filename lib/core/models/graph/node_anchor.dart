import 'package:flutter/foundation.dart';

import 'node_region.dart';

/// Ties a [GraphNode] back to the exact spot in a book it was derived from —
/// what lets a highlight/note jump back to its page, and what a later
/// Obsidian export or AI summarizer uses to cite "page 42 of *Book Title*".
/// Null on [GraphNode.anchor] for nodes never derived from a book page at
/// all (a free-floating canvas note, an [NodeKind.aiSummary] card
/// synthesized from several other nodes rather than one passage).
@immutable
class NodeAnchor {
  const NodeAnchor({
    required this.bookId,
    required this.page,
    this.region,
    this.sourceText,
  });

  /// Matches `Book.id` — a content hash, or `'drive:<fileId>'` for a
  /// not-yet-downloaded Drive book (see `core/models/book.dart`).
  final String bookId;

  /// 1-based page number, matching `Book.currentPage`'s convention.
  final int page;

  /// Where on [page] this anchor points, if known precisely (see
  /// [NodeRegion]) — null for an anchor that only names the page as a whole
  /// (e.g. a [NodeKind.pdfPageCard]).
  final NodeRegion? region;

  /// The verbatim source text this node was derived from (e.g. the
  /// highlighted/underlined passage). Kept separate from
  /// [GraphNode.contentText] (the node's *own* denormalized text) — for a
  /// plain highlight the two are the same string, but for an
  /// [NodeKind.aiSummary] node [GraphNode.contentText] is the generated
  /// summary, not the passage(s) it summarizes.
  final String? sourceText;

  NodeAnchor copyWith({
    String? bookId,
    int? page,
    NodeRegion? region,
    String? sourceText,
  }) => NodeAnchor(
    bookId: bookId ?? this.bookId,
    page: page ?? this.page,
    region: region ?? this.region,
    sourceText: sourceText ?? this.sourceText,
  );

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'page': page,
    if (region != null) 'region': region!.toJson(),
    if (sourceText != null) 'sourceText': sourceText,
  };

  /// Defensive: returns null if [json] is null or doesn't even carry a
  /// `bookId` — never crash on bad local data or a sync row written by a
  /// future app version; a [GraphNode] just ends up with no anchor rather
  /// than a half-populated one.
  static NodeAnchor? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final bookId = json['bookId'] as String?;
    if (bookId == null) return null;
    return NodeAnchor(
      bookId: bookId,
      page: json['page'] as int? ?? 1,
      region: json['region'] == null
          ? null
          : NodeRegion.fromJson(json['region'] as Map<String, dynamic>?),
      sourceText: json['sourceText'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NodeAnchor &&
      other.bookId == bookId &&
      other.page == page &&
      other.region == region &&
      other.sourceText == sourceText;

  @override
  int get hashCode => Object.hash(bookId, page, region, sourceText);
}
