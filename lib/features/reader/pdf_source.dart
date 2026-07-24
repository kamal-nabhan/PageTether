import 'dart:typed_data';

import '../../core/models/book.dart';

/// Cross-platform PDF source.
///
/// `file_picker` (and therefore [Book]) hands back a filesystem [path] on
/// desktop/mobile but only raw [bytes] on web, since the browser sandbox
/// has no concept of a real path. This wrapper normalizes the two cases so
/// the reader screen doesn't need to branch on `kIsWeb` itself — it just
/// asks pdfrx to open whichever source is available.
class PdfSource {
  const PdfSource._({required this.name, this.path, this.bytes});

  factory PdfSource.file(String path, {required String name}) =>
      PdfSource._(name: name, path: path);

  factory PdfSource.data(Uint8List bytes, {required String name}) =>
      PdfSource._(name: name, bytes: bytes);

  /// Builds a [PdfSource] from a [Book], preferring a filesystem path when
  /// one is available and falling back to in-memory bytes (the web case).
  static PdfSource? fromBook(Book book) {
    final path = book.filePath;
    if (path != null) return PdfSource.file(path, name: book.title);
    final bytes = book.fileBytes;
    if (bytes != null) return PdfSource.data(bytes, name: book.title);
    return null;
  }

  final String name;
  final String? path;
  final Uint8List? bytes;
}
