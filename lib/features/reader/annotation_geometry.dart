// Pure geometry/model-building helpers for text-anchored highlights and
// underlines — no widget/BuildContext/pdfrx-viewer dependency, so these are
// exercised directly by unit tests (see test/annotation_geometry_test.dart)
// rather than needing a running PdfViewer.
//
// [PdfRect] (from pdfrx_engine, re-exported by package:pdfrx) is a plain
// Dart value type — page-point coordinates, bottom-left origin, [PdfRect.top]
// >= [PdfRect.bottom] (see that class's doc) — so it's safe to depend on here
// without pulling in any platform/rendering machinery.
import 'package:pdfrx/pdfrx.dart';

import '../../core/models/graph/graph_ids.dart';
import '../../core/models/graph/graph_node.dart';
import '../../core/models/graph/graph_style.dart';
import '../../core/models/graph/node_anchor.dart';
import '../../core/models/graph/node_kind.dart';
import '../../core/models/graph/node_region.dart';

/// Preset highlight/underline colors offered by the reader toolbar's color
/// swatches, as 32-bit ARGB ints (matching [GraphStyle.color]'s
/// representation) — a small, deliberately fixed palette rather than a full
/// color picker, per this PR's "keep it simple" scope.
const List<int> kAnnotationColors = [
  0xFFFFEB3B, // yellow
  0xFF8BC34A, // green
  0xFF29B6F6, // blue
  0xFFF06292, // pink
  0xFFFFA726, // orange
];

/// Default fill opacity for a new [NodeKind.highlight] node — translucent so
/// the underlying text stays readable through the fill.
const double kHighlightOpacity = 0.35;

/// Default stroke opacity/width for a new [NodeKind.underline] node — fully
/// opaque since it's a thin line, not a fill.
const double kUnderlineOpacity = 1.0;
const double kUnderlineStrokeWidth = 3.0;

/// Converts one pdfrx [PdfRect] (page-point coordinates) into a
/// [NormalizedRect] (0..1, independent of zoom/DPI) by dividing every edge
/// by the page's own point size — see [pdfRectFromNormalizedRect] for the
/// inverse used when rendering. [pageWidth]/[pageHeight] should be the
/// page's `PdfPage.width`/`.height`; either being <= 0 defensively yields
/// [NormalizedRect.zero] rather than dividing by zero.
NormalizedRect normalizedRectFromPdfRect(
  PdfRect rect, {
  required double pageWidth,
  required double pageHeight,
}) {
  if (pageWidth <= 0 || pageHeight <= 0) return NormalizedRect.zero;
  return NormalizedRect(
    x: rect.left / pageWidth,
    y: rect.bottom / pageHeight,
    w: rect.width / pageWidth,
    h: rect.height / pageHeight,
  );
}

/// Inverse of [normalizedRectFromPdfRect]: scales a stored [NormalizedRect]
/// back up to a page-point [PdfRect] for [pageWidth]/[pageHeight] — the
/// result is then handed to pdfrx's `PdfRect.toRect(page:, scaledPageSize:)`
/// to get an on-screen [Rect] (see `_ReaderScreenState`'s overlay code),
/// which is what lets a rendered annotation track zoom/scroll/page-flip
/// automatically rather than caching a screen-space rect that would go
/// stale the moment the user zooms or scrolls.
PdfRect pdfRectFromNormalizedRect(
  NormalizedRect rect, {
  required double pageWidth,
  required double pageHeight,
}) {
  final left = rect.x * pageWidth;
  final bottom = rect.y * pageHeight;
  final right = left + rect.w * pageWidth;
  final top = bottom + rect.h * pageHeight;
  return PdfRect(left, top, right, bottom);
}

/// The axis-aligned bounding box of [rects], in whatever [NormalizedRect]
/// coordinate convention they already share (see [normalizedRectFromPdfRect])
/// — used as a new [GraphNode]'s board-space `x/y/w/h` so it has a sensible
/// position/size even before the canvas UI (a later phase) lets it be moved.
/// Returns [NormalizedRect.zero] for an empty list.
NormalizedRect unionNormalizedRects(List<NormalizedRect> rects) {
  if (rects.isEmpty) return NormalizedRect.zero;
  var minX = rects.first.x;
  var minY = rects.first.y;
  var maxX = rects.first.x + rects.first.w;
  var maxY = rects.first.y + rects.first.h;
  for (final r in rects.skip(1)) {
    if (r.x < minX) minX = r.x;
    if (r.y < minY) minY = r.y;
    if (r.x + r.w > maxX) maxX = r.x + r.w;
    if (r.y + r.h > maxY) maxY = r.y + r.h;
  }
  return NormalizedRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY);
}

/// Builds a new highlight/underline [GraphNode] from a text selection's
/// per-line [quads] (already normalized — see [normalizedRectFromPdfRect])
/// and its [sourceText] — the one place that assembles
/// `kind`/`boardId`/`anchor`/`contentText`/`style`/geometry consistently, so
/// the reader toolbar's "Highlight"/"Underline" actions and their unit tests
/// both go through the same logic. [kind] must be [NodeKind.highlight] or
/// [NodeKind.underline] (the only two kinds this PR creates).
GraphNode buildAnnotationNode({
  required NodeKind kind,
  required String boardId,
  required String bookId,
  required int page,
  required List<NormalizedRect> quads,
  required String sourceText,
  required GraphStyle style,
  DateTime? now,
}) {
  assert(
    kind == NodeKind.highlight || kind == NodeKind.underline,
    'buildAnnotationNode only builds highlight/underline nodes',
  );
  final bbox = unionNormalizedRects(quads);
  return GraphNode(
    id: generateGraphId(kind == NodeKind.highlight ? 'highlight' : 'underline'),
    boardId: boardId,
    kind: kind,
    x: bbox.x,
    y: bbox.y,
    w: bbox.w,
    h: bbox.h,
    style: style,
    anchor: NodeAnchor(
      bookId: bookId,
      page: page,
      region: TextQuadsRegion(quads),
      sourceText: sourceText,
    ),
    contentText: sourceText,
    createdAt: now,
    updatedAt: now,
  );
}

/// The [GraphStyle] a new highlight/underline should carry for [kind] and a
/// chosen [color] (one of [kAnnotationColors]) — centralizes the
/// kind-dependent opacity/stroke-width defaults described in this PR's
/// design (0.35 fill opacity for a highlight; a fully-opaque thin stroke for
/// an underline) so the create-toolbar and any future recolor action agree.
GraphStyle annotationStyle(NodeKind kind, int color) {
  if (kind == NodeKind.underline) {
    return GraphStyle(
      color: color,
      opacity: kUnderlineOpacity,
      strokeWidth: kUnderlineStrokeWidth,
    );
  }
  return GraphStyle(color: color, opacity: kHighlightOpacity, fill: color);
}
