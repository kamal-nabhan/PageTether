import 'package:flutter/services.dart' show rootBundle;

import '../../core/models/book.dart';
import '../../core/pdf/pdf_document_tools.dart';
import '../../core/pdf/pdf_source.dart';
import '../../core/storage/library_store.dart';
import '../../core/storage/pdf_hash.dart';

/// Loads the persisted library and guarantees the bundled sample book is
/// always present, seeding it on first launch so a brand-new install never
/// shows a confusing empty library. Called once from `main()`, before
/// `runApp`, so the library is populated on the very first frame.
Future<List<Book>> loadInitialLibrary(LibraryStore store) async {
  final saved = await store.loadAll();
  if (saved.any((book) => book.assetPath == kSampleBookAssetPath)) {
    return saved;
  }

  final sample = await _buildSampleBook();
  if (sample == null) {
    // Rendering the bundled asset failed for some reason (corrupt asset,
    // pdfium init failure, ...) — degrade gracefully rather than crashing
    // startup. The user still sees whatever was already persisted, and can
    // always open their own PDFs.
    return saved;
  }

  await store.upsert(sample);
  return [sample, ...saved];
}

Future<Book?> _buildSampleBook() async {
  try {
    final assetData = await rootBundle.load(kSampleBookAssetPath);
    final bytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );
    final id = contentIdForBytes(bytes);
    final source = PdfSource.asset(
      kSampleBookAssetPath,
      name: 'PageTether Sample Book',
    );
    final pageCount = await readPdfPageCount(source);
    final thumbnail = await renderCoverThumbnail(source);

    return Book(
      id: id,
      title: 'PageTether Sample Book',
      author: 'PageTether',
      pageCount: pageCount,
      currentPage: 1,
      coverGradientIndex: 0,
      coverThumbnail: thumbnail,
      assetPath: kSampleBookAssetPath,
      // Deliberately old, not "now" — once the user has actually opened
      // real books, the bundled sample shouldn't keep jumping to the front
      // of a most-recently-opened sort.
      lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  } catch (_) {
    return null;
  }
}
