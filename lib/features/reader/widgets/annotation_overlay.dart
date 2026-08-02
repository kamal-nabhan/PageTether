import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/models/graph/graph_node.dart';
import '../../../core/models/graph/node_kind.dart';
import '../../../core/models/graph/node_region.dart';
import '../../graph/graph_providers.dart';
import '../annotation_geometry.dart';

/// Renders every highlight/underline anchored to [page] of [bookId] as one
/// of [PdfViewerParams.pageOverlaysBuilder]'s returned widgets.
///
/// A [ConsumerWidget] deliberately kept separate from `_ReaderScreenState`'s
/// own rebuilds: it `ref.watch`es [graphNodesProvider] itself, so adding/
/// removing/recoloring an annotation only rebuilds this small overlay rather
/// than needing `ReaderScreen` to rebuild (and thus hand pdfrx a new
/// `PdfViewerParams`/`pageOverlaysBuilder` closure) on every graph change —
/// see that file's doc comment on why `pageOverlaysBuilder` itself is kept a
/// stable method tear-off.
///
/// Each quad is wrapped in a `PdfOverlayInteractionRegion` (pdfrx's
/// recommended way for an overlay widget to handle taps without competing
/// with the viewer's own pan/zoom/text-selection gesture arena — see that
/// class's doc in pdfrx) so tapping any line of a highlight/underline
/// selects the whole annotation via [onAnnotationTap].
///
/// [onAnnotationTap] is called with the tap's *global* position (from
/// `PdfOverlayInteractionRegion`'s `PdfOverlayInteractionDetails
/// .globalPosition`) alongside the tapped node — `_ReaderScreenState` uses
/// that position to anchor the recolor/delete popover right where the user
/// tapped (see `showAnnotationActionsPopover`).
typedef AnnotationTapCallback =
    void Function(GraphNode node, Offset globalPosition);

class AnnotationOverlay extends ConsumerWidget {
  const AnnotationOverlay({
    super.key,
    required this.bookId,
    required this.page,
    required this.pageRectInViewer,
    required this.onAnnotationTap,
  });

  final String bookId;
  final PdfPage page;

  /// The page's rect in the viewer — only its [Rect.size] is used (to scale
  /// stored [NormalizedRect]s back to screen pixels via `PdfRect.toRect`);
  /// each returned widget is already laid out relative to the page's own
  /// top-left by pdfrx (see `PdfPageOverlaysBuilder`'s doc), so no
  /// translation by [pageRectInViewer]'s origin is needed here.
  final Rect pageRectInViewer;

  final AnnotationTapCallback onAnnotationTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(graphNodesProvider);
    final pageNumber = page.pageNumber;
    final relevant = [
      for (final node in nodes)
        if ((node.kind == NodeKind.highlight ||
                node.kind == NodeKind.underline) &&
            node.anchor?.bookId == bookId &&
            node.anchor?.page == pageNumber)
          node,
    ];
    if (relevant.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: [
        for (final node in relevant)
          for (final quad in _quadsOf(node))
            _AnnotationQuad(
              node: node,
              quad: quad,
              page: page,
              pageRectInViewer: pageRectInViewer,
              onTap: onAnnotationTap,
            ),
      ],
    );
  }

  static List<NormalizedRect> _quadsOf(GraphNode node) {
    final region = node.anchor?.region;
    return region is TextQuadsRegion ? region.quads : const [];
  }
}

/// One rendered line of a highlight (translucent fill) or underline (a
/// stroke along the bottom edge) — positioned via `PdfRect.toRect`, which
/// recomputes from the page's *current* [pageRectInViewer] every build, so
/// it tracks zoom/scroll/page-flip automatically rather than caching a
/// screen-space rect that would go stale.
class _AnnotationQuad extends StatelessWidget {
  const _AnnotationQuad({
    required this.node,
    required this.quad,
    required this.page,
    required this.pageRectInViewer,
    required this.onTap,
  });

  final GraphNode node;
  final NormalizedRect quad;
  final PdfPage page;
  final Rect pageRectInViewer;
  final AnnotationTapCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pdfRect = pdfRectFromNormalizedRect(
      quad,
      pageWidth: page.width,
      pageHeight: page.height,
    );
    final rect = pdfRect.toRect(
      page: page,
      scaledPageSize: pageRectInViewer.size,
    );
    final color = Color(node.style.color ?? kAnnotationColors.first);
    final isHighlight = node.kind == NodeKind.highlight;

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: PdfOverlayInteractionRegion(
        onTap: (details) {
          onTap(node, details.globalPosition);
          return true;
        },
        child: isHighlight
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: node.style.opacity),
                ),
              )
            : Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: node.style.strokeWidth,
                  color: color.withValues(alpha: node.style.opacity),
                ),
              ),
      ),
    );
  }
}
