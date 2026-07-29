import 'package:flutter/foundation.dart';

import 'graph_style.dart';
import 'node_anchor.dart';
import 'node_content.dart';
import 'node_kind.dart';

/// One visual element on a [Board]'s spatial canvas — a highlight lifted
/// from a book page, a hand-drawn ink stroke, a free-floating text note, an
/// AI-generated summary card, etc. (see [NodeKind] for the full set this
/// model must carry, even though only a few are actually created before the
/// canvas UI phase).
///
/// Deliberately carries every [NodeKind] variant's fields up front rather
/// than growing new optional fields per canvas feature later — this graph is
/// designed to be both AI-ready ([contentText] is the flattened, searchable/
/// embeddable text of the node regardless of its concrete [content] variant)
/// and export-ready (an Obsidian export or canvas renderer walks [anchor]/
/// [content] identically). Persisted locally via `LibraryStore` under
/// `pt.nodes.v1` and synced via `SyncEngine.pushNodes`/`pullNodes` against
/// the `pt_nodes` table (see `schema.sql`).
@immutable
class GraphNode {
  GraphNode({
    required this.id,
    required this.boardId,
    required this.kind,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
    this.rotation = 0,
    this.z = 0,
    this.style = GraphStyle.empty,
    this.content = const EmptyNodeContent(),
    this.anchor,
    this.contentText = '',
    this.badge,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  /// Opaque, practically-unique id — see `generateGraphId` (`graph_ids.dart`).
  final String id;

  /// The [Board] this node lives on.
  final String boardId;

  final NodeKind kind;

  // --- Geometry: board-space coordinates (not page-normalized — see
  // NodeAnchor.region for the node's *source* location on the book page,
  // which is independent of where it's currently placed on the canvas). ---
  final double x;
  final double y;
  final double w;
  final double h;

  /// Radians.
  final double rotation;

  /// Stacking order — higher draws on top. A plain double (not an int index)
  /// so a node can be nudged between two others without renumbering the rest.
  final double z;

  final GraphStyle style;

  /// The node's structured payload (text/vector/image — see [NodeContent]).
  /// [EmptyNodeContent] for kinds whose meaning lives entirely in [anchor]/
  /// [contentText] (a plain highlight/underline needs no content of its own).
  final NodeContent content;

  /// Where on a book page this node was derived from, if any — see
  /// [NodeAnchor]'s doc for which kinds are expected to have one.
  final NodeAnchor? anchor;

  /// The denormalized, searchable/AI-embeddable text of this node —
  /// deliberately flat plain text regardless of [content]'s concrete
  /// variant, so full-text search, an AI summarizer, or an Obsidian export
  /// never needs to pattern-match [content] just to know what a node "says".
  /// For a highlight this mirrors [NodeAnchor.sourceText]; for a text note
  /// it mirrors the [TextNodeContent.text]; for an [NodeKind.image] node
  /// it's whatever caption/OCR text (if any) describes the image.
  final String contentText;

  /// Optional small status/label string for [NodeKind.badge] nodes (and,
  /// incidentally, available to decorate any other kind — e.g. tagging a
  /// highlight "TODO").
  final String? badge;

  final DateTime createdAt;

  /// Last-write-wins clock for sync — see `SyncEngine.pushNodes`/
  /// `GraphNodesNotifier.mergeRemoteNodes`, mirroring `Book.updatedAt`'s doc.
  final DateTime updatedAt;

  GraphNode copyWith({
    String? boardId,
    NodeKind? kind,
    double? x,
    double? y,
    double? w,
    double? h,
    double? rotation,
    double? z,
    GraphStyle? style,
    NodeContent? content,
    NodeAnchor? anchor,
    String? contentText,
    String? badge,
    DateTime? updatedAt,
  }) => GraphNode(
    id: id,
    boardId: boardId ?? this.boardId,
    kind: kind ?? this.kind,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    rotation: rotation ?? this.rotation,
    z: z ?? this.z,
    style: style ?? this.style,
    content: content ?? this.content,
    anchor: anchor ?? this.anchor,
    contentText: contentText ?? this.contentText,
    badge: badge ?? this.badge,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'boardId': boardId,
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
    'contentText': contentText,
    'badge': badge,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Defensive against unknown [NodeKind]s and missing fields — never crash
  /// on bad local data or a row written by a future app version (mirrors
  /// `Book.fromJson`'s stance). An unrecognized `kind` falls back to
  /// [NodeKind.textNote] rather than throwing.
  factory GraphNode.fromJson(Map<String, dynamic> json) {
    final updatedAt =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final createdAt =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updatedAt;
    return GraphNode(
      id: json['id'] as String,
      boardId: json['boardId'] as String? ?? '',
      kind: NodeKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => NodeKind.textNote,
      ),
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      w: (json['w'] as num?)?.toDouble() ?? 0,
      h: (json['h'] as num?)?.toDouble() ?? 0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
      style: GraphStyle.fromJson(json['style'] as Map<String, dynamic>?),
      content: NodeContent.fromJson(json['content'] as Map<String, dynamic>?),
      anchor: NodeAnchor.fromJson(json['anchor'] as Map<String, dynamic>?),
      contentText: json['contentText'] as String? ?? '',
      badge: json['badge'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
