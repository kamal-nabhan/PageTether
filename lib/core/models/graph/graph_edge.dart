import 'package:flutter/foundation.dart';

import 'graph_style.dart';

/// What kind of relationship a [GraphEdge] represents between two
/// [GraphNode]s.
enum EdgeKind {
  /// A plain directional connector, no semantic meaning beyond "points to".
  arrow,

  /// The source node explains/annotates the target (e.g. an
  /// [NodeKind.aiSummary] or [NodeKind.textNote] explaining a highlight).
  explains,

  /// A generic named relationship (see [GraphEdge.label]) — anything not
  /// covered by [arrow]/[explains].
  link,
}

/// A connection between two [GraphNode]s on the same [Board] — the arrows/
/// relationships drawn on the canvas linking a note to the highlight it
/// explains, or two highlights to each other. Persisted locally via
/// `LibraryStore` under `pt.edges.v1` and synced via `SyncEngine.pushEdges`/
/// `pullEdges` against the `pt_edges` table (see `schema.sql`).
@immutable
class GraphEdge {
  GraphEdge({
    required this.id,
    required this.boardId,
    required this.fromNodeId,
    required this.toNodeId,
    this.kind = EdgeKind.arrow,
    this.label,
    this.style = GraphStyle.empty,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  /// Opaque, practically-unique id — see `generateGraphId` (`graph_ids.dart`).
  final String id;

  final String boardId;
  final String fromNodeId;
  final String toNodeId;
  final EdgeKind kind;

  /// Optional free-text label shown on/near the edge.
  final String? label;

  final GraphStyle style;

  final DateTime createdAt;

  /// Last-write-wins clock for sync — see `SyncEngine.pushEdges`/
  /// `GraphEdgesNotifier.mergeRemoteEdges`, mirroring `Book.updatedAt`'s doc.
  final DateTime updatedAt;

  GraphEdge copyWith({
    String? boardId,
    String? fromNodeId,
    String? toNodeId,
    EdgeKind? kind,
    String? label,
    GraphStyle? style,
    DateTime? updatedAt,
  }) => GraphEdge(
    id: id,
    boardId: boardId ?? this.boardId,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    style: style ?? this.style,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'boardId': boardId,
    'fromNodeId': fromNodeId,
    'toNodeId': toNodeId,
    'kind': kind.name,
    'label': label,
    'style': style.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Defensive against unknown [EdgeKind]s and missing fields — see
  /// `GraphNode.fromJson`'s doc for the same stance. An unrecognized `kind`
  /// falls back to [EdgeKind.arrow] rather than throwing.
  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    final updatedAt =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final createdAt =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updatedAt;
    return GraphEdge(
      id: json['id'] as String,
      boardId: json['boardId'] as String? ?? '',
      fromNodeId: json['fromNodeId'] as String? ?? '',
      toNodeId: json['toNodeId'] as String? ?? '',
      kind: EdgeKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => EdgeKind.arrow,
      ),
      label: json['label'] as String?,
      style: GraphStyle.fromJson(json['style'] as Map<String, dynamic>?),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
