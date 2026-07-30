import 'package:flutter/foundation.dart';

/// Visual styling shared by [GraphNode] and [GraphEdge] — a small, typed
/// subset of "the stuff a shape/stroke/label needs to render" (color,
/// opacity, stroke width, fill), plus [extra]: a free-form bag for anything a
/// later canvas feature needs that isn't modeled here yet (a dash pattern, a
/// gradient, …), so a not-yet-invented style knob can still round-trip
/// through local storage and sync without a schema/model change — the same
/// forward-compatibility stance as [NodeContent.fromJson]/[NodeKind]'s doc
/// comment.
@immutable
class GraphStyle {
  const GraphStyle({
    this.color,
    this.opacity = 1.0,
    this.strokeWidth = 1.0,
    this.fill,
    this.extra = const {},
  });

  static const empty = GraphStyle();

  /// Stroke/text/label color as a 32-bit ARGB int (`Color(...).toARGB32()`),
  /// not a `Color` — keeps this model trivially JSON-native (a `jsonb`
  /// column round-trips a plain int for free) rather than needing a
  /// dedicated color codec. Null means "use the canvas renderer's default".
  final int? color;

  /// 0.0 (invisible) to 1.0 (opaque).
  final double opacity;

  final double strokeWidth;

  /// Fill color (shapes/highlights), same ARGB-int representation as
  /// [color]. Null means "no fill".
  final int? fill;

  /// Anything not modeled above, keyed by whatever a later feature chooses —
  /// preserved as-is through toJson/fromJson so an older app build never
  /// silently drops a newer build's style data on a round-trip through
  /// local storage or Supabase.
  final Map<String, dynamic> extra;

  GraphStyle copyWith({
    int? color,
    double? opacity,
    double? strokeWidth,
    int? fill,
    Map<String, dynamic>? extra,
  }) => GraphStyle(
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    fill: fill ?? this.fill,
    extra: extra ?? this.extra,
  );

  Map<String, dynamic> toJson() => {
    if (color != null) 'color': color,
    'opacity': opacity,
    'strokeWidth': strokeWidth,
    if (fill != null) 'fill': fill,
    if (extra.isNotEmpty) 'extra': extra,
  };

  /// Defensive: null/malformed [json] decodes to [empty] rather than
  /// throwing — never crash on bad local data or a sync row written by a
  /// future app version.
  factory GraphStyle.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    final rawExtra = json['extra'];
    return GraphStyle(
      color: json['color'] as int?,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.0,
      fill: json['fill'] as int?,
      extra: rawExtra is Map
          ? Map<String, dynamic>.from(rawExtra)
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GraphStyle &&
      other.color == color &&
      other.opacity == opacity &&
      other.strokeWidth == strokeWidth &&
      other.fill == fill &&
      mapEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(color, opacity, strokeWidth, fill, Object.hashAll(extra.entries));
}
