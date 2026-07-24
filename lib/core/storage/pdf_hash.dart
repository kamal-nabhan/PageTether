import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Stable content id for a PDF: sha256 of its raw bytes, hex-encoded.
///
/// Hashing content (rather than using a file path or a random id) means
/// "Continue Reading" and per-document progress work no matter where the
/// file lives or which platform reopened it — the same PDF opened from two
/// different paths (or re-picked on web after a reload) resolves to the
/// same library entry.
String contentIdForBytes(Uint8List bytes) => sha256.convert(bytes).toString();
