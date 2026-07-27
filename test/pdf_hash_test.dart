// Unit tests for contentIdForBytes (lib/core/storage/pdf_hash.dart): the
// stable sha256-of-bytes content id used to dedupe books across pick/upload/
// download paths. Pure logic, no device/network.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:pagetether/core/storage/pdf_hash.dart';

void main() {
  group('contentIdForBytes', () {
    test('is deterministic for the same bytes', () {
      final bytes = Uint8List.fromList(utf8.encode('hello world'));
      expect(contentIdForBytes(bytes), contentIdForBytes(bytes));
    });

    test('differs for different bytes', () {
      final a = Uint8List.fromList(utf8.encode('hello world'));
      final b = Uint8List.fromList(utf8.encode('hello world!'));
      expect(contentIdForBytes(a), isNot(contentIdForBytes(b)));
    });

    test('matches the sha256 hex digest of the input bytes', () {
      final bytes = Uint8List.fromList(utf8.encode('pagetether'));
      expect(contentIdForBytes(bytes), crypto.sha256.convert(bytes).toString());
    });

    test('is a 64-character lowercase hex string', () {
      final bytes = Uint8List.fromList(utf8.encode('pagetether'));
      final id = contentIdForBytes(bytes);
      expect(id, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id), isTrue);
    });

    test('empty bytes still produce a stable id', () {
      final id = contentIdForBytes(Uint8List(0));
      expect(id, crypto.sha256.convert(Uint8List(0)).toString());
    });
  });
}
