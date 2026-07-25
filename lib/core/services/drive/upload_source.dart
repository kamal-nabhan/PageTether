// Conditional export: opens a local file path as a [ByteStreamSource] for
// upload on every platform where `dart:io` is available (desktop/mobile);
// on web, [filePath] is never populated in the first place (web always
// supplies raw bytes instead — see `Book.fileBytes`/`PdfSource.data`), so
// the stub only exists to make the import compile there.
export 'upload_source_stub.dart' if (dart.library.io) 'upload_source_io.dart';
