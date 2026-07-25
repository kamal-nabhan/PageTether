// Conditional export: a real on-disk cache (keyed by Drive file id) on every
// platform where `dart:io` is available (desktop/mobile), and an in-memory
// cache on web, where there's no straightforward writable filesystem. See
// `drive_cache_io.dart` / `drive_cache_stub.dart` for details — both expose
// the same `getOrDownloadPdf` signature so `drive_service.dart` never
// branches on platform itself.
export 'drive_cache_stub.dart' if (dart.library.io) 'drive_cache_io.dart';
