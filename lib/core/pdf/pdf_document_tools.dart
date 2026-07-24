import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'pdf_source.dart';

/// Opens [source] with pdfrx, branching on whichever of asset/file/bytes it
/// carries. Callers are responsible for calling `dispose()` on the result.
Future<PdfDocument> openPdfDocument(PdfSource source) async {
  await pdfrxFlutterInitialize();
  final assetPath = source.assetPath;
  if (assetPath != null) return PdfDocument.openAsset(assetPath);
  final path = source.path;
  if (path != null) return PdfDocument.openFile(path);
  return PdfDocument.openData(source.bytes!, sourceName: source.name);
}

/// Opens [source] just long enough to read its true page count, then closes
/// it. Used right after picking/seeding a book so the library can show real
/// numbers instead of placeholders. Returns 0 if the document can't be
/// opened rather than throwing, so a bad PDF never crashes the library.
Future<int> readPdfPageCount(PdfSource source) async {
  try {
    final document = await openPdfDocument(source);
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  } catch (_) {
    return 0;
  }
}

/// Renders page 1 of [source] to PNG bytes for use as a book-card cover.
/// Returns null (never throws) if rendering fails for any reason, so
/// callers can fall back to the gradient cover.
Future<Uint8List?> renderCoverThumbnail(
  PdfSource source, {
  double targetWidth = 320,
}) async {
  PdfDocument? document;
  try {
    document = await openPdfDocument(source);
    if (document.pages.isEmpty) return null;
    final page = document.pages.first;
    if (page.width <= 0 || page.height <= 0) return null;
    final scale = targetWidth / page.width;

    final pdfImage = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (pdfImage == null) return null;
    try {
      final uiImage = await pdfImage.createImage();
      try {
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        uiImage.dispose();
      }
    } finally {
      pdfImage.dispose();
    }
  } catch (_) {
    return null;
  } finally {
    await document?.dispose();
  }
}
