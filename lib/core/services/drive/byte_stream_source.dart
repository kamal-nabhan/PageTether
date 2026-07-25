/// A byte source paired with its total length, used for both directions of
/// Drive file transfer:
///
/// - **Upload**: [upload_source.dart] opens a local file (desktop/mobile)
///   as one of these so `DriveService.uploadPdf` can stream it without ever
///   holding the whole file in memory.
/// - **Download**: `DriveService.downloadToCache` wraps the `googleapis`
///   `Media` response in one of these so `drive_cache.dart` can write it to
///   disk (or, on web, buffer it in memory) while reporting progress.
///
/// Plain Dart, no platform imports — safe to use from `drive_service.dart`
/// directly on every platform.
class ByteStreamSource {
  const ByteStreamSource({required this.stream, required this.length});

  final Stream<List<int>> stream;

  /// Total byte count, used to compute progress percentage. 0 if unknown
  /// (progress reporting is then skipped rather than divide-by-zero).
  final int length;
}

/// Lazily produces a [ByteStreamSource] — only invoked when a download
/// actually needs to hit the network (see `drive_cache.dart`'s cache-hit
/// short-circuit).
typedef ByteStreamFetcher = Future<ByteStreamSource> Function();
