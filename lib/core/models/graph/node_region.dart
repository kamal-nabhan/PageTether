import 'package:flutter/foundation.dart';

/// A rectangle in book-page-normalized coordinates: 0.0-1.0 on both axes,
/// independent of the page's actual pixel/point size, so it renders
/// correctly regardless of zoom level or rendering-surface DPI. Used both as
/// [NormalizedRectRegion]'s whole region and as each entry of
/// [TextQuadsRegion]'s per-line quad list.
@immutable
class NormalizedRect {
  const NormalizedRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  static const zero = NormalizedRect(x: 0, y: 0, w: 0, h: 0);

  final double x;
  final double y;
  final double w;
  final double h;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  /// Defensive: null/malformed [json] decodes to [zero] rather than
  /// throwing.
  factory NormalizedRect.fromJson(Map<String, dynamic>? json) {
    if (json == null) return zero;
    return NormalizedRect(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      w: (json['w'] as num?)?.toDouble() ?? 0,
      h: (json['h'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NormalizedRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

/// Where on a book page a [NodeAnchor] points — a discriminated union (tagged
/// by a `type` string in JSON) between one bounding box
/// ([NormalizedRectRegion] — a rectangular highlight, an ink stroke's
/// bounding box) and several ([TextQuadsRegion] — a text-selection highlight
/// that wraps across lines, one quad per line, the shape pdfrx's text
/// selection API already reports).
sealed class NodeRegion {
  const NodeRegion();

  Map<String, dynamic> toJson();

  /// Defensive: an unrecognized/missing `type` falls back to a zero-sized
  /// [NormalizedRectRegion] rather than throwing.
  factory NodeRegion.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NormalizedRectRegion(NormalizedRect.zero);
    switch (json['type'] as String?) {
      case 'textQuads':
        final rawQuads = json['quads'] as List<dynamic>? ?? const [];
        return TextQuadsRegion([
          for (final quad in rawQuads)
            NormalizedRect.fromJson(quad as Map<String, dynamic>?),
        ]);
      case 'normalizedRect':
      default:
        return NormalizedRectRegion(
          NormalizedRect.fromJson(json['rect'] as Map<String, dynamic>?),
        );
    }
  }
}

class NormalizedRectRegion extends NodeRegion {
  const NormalizedRectRegion(this.rect);

  final NormalizedRect rect;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'normalizedRect',
    'rect': rect.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is NormalizedRectRegion && other.rect == rect;
  @override
  int get hashCode => Object.hash(NormalizedRectRegion, rect);
}

class TextQuadsRegion extends NodeRegion {
  const TextQuadsRegion(this.quads);

  final List<NormalizedRect> quads;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'textQuads',
    'quads': [for (final quad in quads) quad.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is TextQuadsRegion && listEquals(other.quads, quads);
  @override
  int get hashCode => Object.hashAll(quads);
}
