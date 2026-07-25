// Fallback used whenever `dart:io` isn't available (Flutter web). See
// `drive_cache.dart` for the conditional export that picks between this
// file and `drive_cache_io.dart`.
//
// Browsers have no straightforward writable filesystem, so "caching" here
// just means keeping the downloaded bytes in memory for the rest of this
// page session — consistent with how every other web-picked book already
// works (see `Book.fileBytes`/`Book.openedOnWeb`). A page reload loses it,
// same as any other web-picked book.
import 'dart:typed_data';

import '../../pdf/pdf_source.dart';
import 'byte_stream_source.dart';

final Map<String, Uint8List> _memoryCache = {};

Future<PdfSource> getOrDownloadPdf({
  required String fileId,
  required String name,
  required ByteStreamFetcher fetch,
  void Function(double progress)? onProgress,
}) async {
  final cached = _memoryCache[fileId];
  if (cached != null) {
    onProgress?.call(1);
    return PdfSource.data(cached, name: name);
  }

  final download = await fetch();
  final builder = BytesBuilder(copy: false);
  var received = 0;
  await for (final chunk in download.stream) {
    builder.add(chunk);
    received += chunk.length;
    if (download.length > 0) onProgress?.call(received / download.length);
  }
  final bytes = builder.takeBytes();
  _memoryCache[fileId] = bytes;
  return PdfSource.data(bytes, name: name);
}
