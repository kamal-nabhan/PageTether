// Only ever compiled when `dart:io` is available (see the conditional
// export in `drive_cache.dart`) — never pulled into the web build.
//
// Downloads are cached to a real file, keyed by Drive file id, in the OS
// app-cache directory (via `path_provider`). A cache hit skips the network
// entirely — this deliberately does not check Drive's `modifiedTime`
// against the cached copy (out of scope for Phase 2; see the report for
// what that would take), so if a file is re-uploaded/edited on Drive with
// the same id, a previously-cached copy would go stale until the local
// cache entry is manually cleared.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../pdf/pdf_source.dart';
import 'byte_stream_source.dart';

Future<Directory> _cacheDir() async {
  final base = await getApplicationCacheDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}drive_cache');
  await dir.create(recursive: true);
  return dir;
}

String _safeFileName(String fileId, String name) {
  final sanitized = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return '$fileId-$sanitized';
}

Future<PdfSource> getOrDownloadPdf({
  required String fileId,
  required String name,
  required ByteStreamFetcher fetch,
  void Function(double progress)? onProgress,
}) async {
  final dir = await _cacheDir();
  final target = File(
    '${dir.path}${Platform.pathSeparator}${_safeFileName(fileId, name)}',
  );
  if (await target.exists()) {
    onProgress?.call(1);
    return PdfSource.file(target.path, name: name);
  }

  final download = await fetch();
  // Download to a `.part` sibling and rename on success, so a crash or
  // cancellation mid-download never leaves a corrupt file that looks
  // "cached" to the `target.exists()` check above.
  final tempTarget = File('${target.path}.part');
  final sink = tempTarget.openWrite();
  var received = 0;
  try {
    await for (final chunk in download.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (download.length > 0) onProgress?.call(received / download.length);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  await tempTarget.rename(target.path);
  return PdfSource.file(target.path, name: name);
}
