import 'dart:math';
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

/// Lays pages out left-to-right, each vertically centered, so the viewer
/// reads like a horizontal page-flip book instead of pdfrx's default
/// continuous vertical scroll. Swiping/dragging moves between pages
/// horizontally; [ReaderScreen]'s prev/next controls animate a full page
/// at a time via [PdfViewerController.goToPage].
///
/// Adapted from pdfrx's documented pattern for `PdfViewerParams.layoutPages`
/// (see the "Page Layout Customization" wiki entry).
PdfPageLayout horizontalPdfPageLayout(List<PdfPage> pages, PdfViewerParams params) {
  final height = pages.fold<double>(0, (prev, page) => max(prev, page.height)) + params.margin * 2;
  final pageLayouts = <Rect>[];
  var x = params.margin;
  for (final page in pages) {
    pageLayouts.add(
      Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height),
    );
    x += page.width + params.margin;
  }
  return PdfPageLayout(pageLayouts: pageLayouts, documentSize: Size(x, height));
}
