import 'dart:typed_data';

import '../models/book.dart';

/// Path (registered under `assets:` in `pubspec.yaml`) of the bundled
/// sample PDF that ships with the app so the library is never empty on
/// first launch.
const kSampleBookAssetPath = 'assets/sample.pdf';

/// Cross-platform PDF source.
///
/// `file_picker` (and therefore [Book]) hands back a filesystem [path] on
/// desktop/mobile but only raw [bytes] on web, since the browser sandbox
/// has no concept of a real path. This wrapper normalizes those cases (plus
/// the bundled-asset case) so callers don't need to branch on `kIsWeb`
/// themselves — they just ask pdfrx to open whichever source is available.
class PdfSource {
  const PdfSource._({required this.name, this.assetPath, this.path, this.bytes});

  factory PdfSource.asset(String assetPath, {required String name}) =>
      PdfSource._(name: name, assetPath: assetPath);

  factory PdfSource.file(String path, {required String name}) =>
      PdfSource._(name: name, path: path);

  factory PdfSource.data(Uint8List bytes, {required String name}) =>
      PdfSource._(name: name, bytes: bytes);

  /// Builds a [PdfSource] from a [Book], preferring the bundled asset, then
  /// a filesystem path, then in-memory bytes (the current-session/web
  /// case). Returns null if none is available — e.g. a web-picked book
  /// after a page reload — so the caller can prompt a re-pick instead of
  /// crashing.
  static PdfSource? fromBook(Book book) {
    final assetPath = book.assetPath;
    if (assetPath != null) return PdfSource.asset(assetPath, name: book.title);
    final path = book.filePath;
    if (path != null) return PdfSource.file(path, name: book.title);
    final bytes = book.fileBytes;
    if (bytes != null) return PdfSource.data(bytes, name: book.title);
    return null;
  }

  final String name;
  final String? assetPath;
  final String? path;
  final Uint8List? bytes;
}
