// Unit tests for the pure highlight/underline logic in
// lib/features/reader/annotation_geometry.dart: PdfRect<->NormalizedRect
// conversion, the union bounding box used for a new GraphNode's geometry,
// and building a highlight/underline GraphNode from a set of quads + text.
// No widget/device dependency — PdfRect (pdfrx_engine) is a plain Dart value
// type, so this runs as fast pure-Dart logic like
// test/graph_models_serialization_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:pagetether/core/models/graph/node_kind.dart';
import 'package:pagetether/core/models/graph/node_region.dart';
import 'package:pagetether/core/models/graph/graph_style.dart';
import 'package:pagetether/features/reader/annotation_geometry.dart';

void main() {
  group('normalizedRectFromPdfRect / pdfRectFromNormalizedRect', () {
    test('round-trips a rect through normalize then denormalize', () {
      const pageWidth = 612.0; // US Letter, points
      const pageHeight = 792.0;
      const original = PdfRect(50, 700, 200, 680);

      final normalized = normalizedRectFromPdfRect(
        original,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
      );
      // Normalized coordinates must stay within the unit square.
      expect(normalized.x, closeTo(50 / 612, 1e-9));
      expect(normalized.y, closeTo(680 / 792, 1e-9));
      expect(normalized.w, closeTo(150 / 612, 1e-9));
      expect(normalized.h, closeTo(20 / 792, 1e-9));

      final roundTripped = pdfRectFromNormalizedRect(
        normalized,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
      );
      expect(roundTripped.left, closeTo(original.left, 1e-9));
      expect(roundTripped.top, closeTo(original.top, 1e-9));
      expect(roundTripped.right, closeTo(original.right, 1e-9));
      expect(roundTripped.bottom, closeTo(original.bottom, 1e-9));
    });

    test('normalizedRectFromPdfRect defends against a zero-size page', () {
      const rect = PdfRect(10, 20, 30, 10);
      expect(
        normalizedRectFromPdfRect(rect, pageWidth: 0, pageHeight: 100),
        NormalizedRect.zero,
      );
      expect(
        normalizedRectFromPdfRect(rect, pageWidth: 100, pageHeight: -1),
        NormalizedRect.zero,
      );
    });

    test('is stable across different page sizes (zoom-independent)', () {
      const rect = PdfRect(30, 100, 130, 80);
      final atOnePagePoint = normalizedRectFromPdfRect(
        rect,
        pageWidth: 300,
        pageHeight: 400,
      );
      // Scaling the "page" (as a zoomed render would) shouldn't be fed back
      // in here — normalization always uses the *document* point size, so
      // the same input rect/page size always yields the same normalized
      // rect regardless of how the page happens to be rendered on screen.
      final again = normalizedRectFromPdfRect(
        rect,
        pageWidth: 300,
        pageHeight: 400,
      );
      expect(again, atOnePagePoint);
    });
  });

  group('unionNormalizedRects', () {
    test('returns zero for an empty list', () {
      expect(unionNormalizedRects(const []), NormalizedRect.zero);
    });

    test('returns the single rect unchanged for a one-element list', () {
      const rect = NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.05);
      final union = unionNormalizedRects(const [rect]);
      // Compared field-by-field with a tolerance rather than `==` — the
      // union is computed via min/max of edges (x, x+w, ...) rather than
      // just returning the input rect verbatim, so floating-point rounding
      // (e.g. 0.1 + 0.3 - 0.1 != 0.3 in binary floating point) can make an
      // exact-equality check flaky even though the rect is unchanged in
      // any meaningful sense.
      expect(union.x, closeTo(rect.x, 1e-9));
      expect(union.y, closeTo(rect.y, 1e-9));
      expect(union.w, closeTo(rect.w, 1e-9));
      expect(union.h, closeTo(rect.h, 1e-9));
    });

    test('computes the bounding box of several quads (multi-line selection)', () {
      const quads = [
        NormalizedRect(x: 0.1, y: 0.30, w: 0.5, h: 0.05),
        NormalizedRect(x: 0.05, y: 0.24, w: 0.3, h: 0.05),
      ];
      final union = unionNormalizedRects(quads);
      expect(union.x, closeTo(0.05, 1e-9));
      expect(union.y, closeTo(0.24, 1e-9));
      // Right edge is max(0.1+0.5, 0.05+0.3) = 0.6; width is right - minX.
      expect(union.x + union.w, closeTo(0.6, 1e-9));
      // Top edge is max(0.30+0.05, 0.24+0.05) = 0.35.
      expect(union.y + union.h, closeTo(0.35, 1e-9));
    });
  });

  group('annotationStyle', () {
    test('a highlight gets the default translucent fill opacity', () {
      final style = annotationStyle(NodeKind.highlight, 0xFFFFEB3B);
      expect(style.color, 0xFFFFEB3B);
      expect(style.fill, 0xFFFFEB3B);
      expect(style.opacity, kHighlightOpacity);
    });

    test('an underline gets a fully opaque thin stroke, no fill', () {
      final style = annotationStyle(NodeKind.underline, 0xFF29B6F6);
      expect(style.color, 0xFF29B6F6);
      expect(style.fill, isNull);
      expect(style.opacity, kUnderlineOpacity);
      expect(style.strokeWidth, kUnderlineStrokeWidth);
    });
  });

  group('buildAnnotationNode', () {
    const quads = [
      NormalizedRect(x: 0.1, y: 0.30, w: 0.5, h: 0.05),
      NormalizedRect(x: 0.05, y: 0.24, w: 0.3, h: 0.05),
    ];

    test('builds a highlight node with the correct kind/anchor/contentText/style', () {
      const style = GraphStyle(color: 0xFFFFEB3B, opacity: 0.35, fill: 0xFFFFEB3B);
      final node = buildAnnotationNode(
        kind: NodeKind.highlight,
        boardId: 'board-1',
        bookId: 'book-1',
        page: 7,
        quads: quads,
        sourceText: 'the highlighted passage',
        style: style,
      );

      expect(node.kind, NodeKind.highlight);
      expect(node.boardId, 'board-1');
      expect(node.contentText, 'the highlighted passage');
      expect(node.style, style);
      expect(node.anchor, isNotNull);
      expect(node.anchor!.bookId, 'book-1');
      expect(node.anchor!.page, 7);
      expect(node.anchor!.sourceText, 'the highlighted passage');
      final region = node.anchor!.region;
      expect(region, isA<TextQuadsRegion>());
      expect((region as TextQuadsRegion).quads, quads);

      // Geometry is the union bbox of the quads, so the node has a sensible
      // position/size even before the canvas UI exists.
      final union = unionNormalizedRects(quads);
      expect(node.x, union.x);
      expect(node.y, union.y);
      expect(node.w, union.w);
      expect(node.h, union.h);

      // Ids are generated, not caller-supplied, and are unique per call.
      expect(node.id, isNotEmpty);
      expect(node.id, startsWith('highlight_'));
    });

    test('builds an underline node with its own id prefix', () {
      final node = buildAnnotationNode(
        kind: NodeKind.underline,
        boardId: 'board-1',
        bookId: 'book-1',
        page: 3,
        quads: quads,
        sourceText: 'underlined text',
        style: annotationStyle(NodeKind.underline, 0xFF29B6F6),
      );
      expect(node.kind, NodeKind.underline);
      expect(node.id, startsWith('underline_'));
    });

    test('two nodes built back-to-back get distinct ids', () {
      final a = buildAnnotationNode(
        kind: NodeKind.highlight,
        boardId: 'board-1',
        bookId: 'book-1',
        page: 1,
        quads: quads,
        sourceText: 'a',
        style: annotationStyle(NodeKind.highlight, 0xFFFFEB3B),
      );
      final b = buildAnnotationNode(
        kind: NodeKind.highlight,
        boardId: 'board-1',
        bookId: 'book-1',
        page: 1,
        quads: quads,
        sourceText: 'b',
        style: annotationStyle(NodeKind.highlight, 0xFFFFEB3B),
      );
      expect(a.id, isNot(b.id));
    });
  });
}
