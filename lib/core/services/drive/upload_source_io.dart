// Only ever compiled when `dart:io` is available (see the conditional
// export in `upload_source.dart`) — never pulled into the web build.
import 'dart:io';

import 'byte_stream_source.dart';

Future<ByteStreamSource> openUploadSource(String path) async {
  final file = File(path);
  final length = await file.length();
  return ByteStreamSource(stream: file.openRead(), length: length);
}
