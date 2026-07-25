// Fallback used whenever `dart:io` isn't available (Flutter web). See
// `upload_source.dart` for the conditional export that picks between this
// file and `upload_source_io.dart`. Never actually called on web —
// `DriveService.uploadPdf` is always given `bytes` there, never `filePath`.
import 'byte_stream_source.dart';

Future<ByteStreamSource> openUploadSource(String path) {
  throw UnsupportedError(
    'Uploading by file path is not supported on web; pass bytes instead.',
  );
}
