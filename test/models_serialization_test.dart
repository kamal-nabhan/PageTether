// Serialization round-trip tests for the two persisted library models: Book
// (lib/core/models/book.dart) and Collection (lib/core/models/collection.dart).
// Pure logic, no device/network.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagetether/core/models/book.dart';
import 'package:pagetether/core/models/collection.dart';

void main() {
  group('Book.toJson/fromJson', () {
    test('round-trips every persisted field', () {
      final book = Book(
        id: 'abc123',
        title: 'Test Title',
        author: 'Test Author',
        pageCount: 250,
        currentPage: 42,
        coverGradientIndex: 3,
        coverThumbnail: Uint8List.fromList([1, 2, 3, 4]),
        assetPath: 'assets/sample.pdf',
        filePath: '/some/path.pdf',
        openedOnWeb: true,
        lastOpenedAt: DateTime.utc(2026, 3, 15, 10, 30),
        source: BookSource.drive,
        driveFileId: 'drive-file-1',
        driveSizeBytes: 12345,
        isFavorite: true,
        collectionIds: const {'c1', 'c2'},
        updatedAt: DateTime.utc(2026, 3, 15, 11, 0),
      );

      final decoded = Book.fromJson(book.toJson());

      expect(decoded.id, book.id);
      expect(decoded.title, book.title);
      expect(decoded.author, book.author);
      expect(decoded.pageCount, book.pageCount);
      expect(decoded.currentPage, book.currentPage);
      expect(decoded.coverGradientIndex, book.coverGradientIndex);
      expect(decoded.coverThumbnail, book.coverThumbnail);
      expect(decoded.assetPath, book.assetPath);
      expect(decoded.filePath, book.filePath);
      expect(decoded.openedOnWeb, book.openedOnWeb);
      expect(decoded.lastOpenedAt, book.lastOpenedAt);
      expect(decoded.source, book.source);
      expect(decoded.driveFileId, book.driveFileId);
      expect(decoded.driveSizeBytes, book.driveSizeBytes);
      expect(decoded.isFavorite, book.isFavorite);
      expect(decoded.collectionIds, book.collectionIds);
      expect(decoded.updatedAt, book.updatedAt);
    });

    test('fileBytes is never serialized (session-only field)', () {
      final book = Book(
        id: 'has-bytes',
        title: 't',
        author: 'a',
        pageCount: 1,
        currentPage: 1,
        coverGradientIndex: 0,
        fileBytes: Uint8List.fromList([9, 9, 9]),
        lastOpenedAt: DateTime.utc(2026, 1, 1),
      );
      expect(book.toJson().containsKey('fileBytes'), isFalse);
    });

    test('fromJson fills sensible defaults for missing/legacy fields', () {
      final decoded = Book.fromJson({'id': 'legacy-1'});

      expect(decoded.id, 'legacy-1');
      expect(decoded.title, 'Untitled');
      expect(decoded.author, '');
      expect(decoded.pageCount, 0);
      expect(decoded.currentPage, 1);
      expect(decoded.source, BookSource.local);
      expect(decoded.isFavorite, isFalse);
      expect(decoded.collectionIds, isEmpty);
      // Pre-Phase-4a persisted records have no updatedAt of their own —
      // falls back to lastOpenedAt, matching the constructor's default.
      expect(decoded.updatedAt, decoded.lastOpenedAt);
    });

    test('null coverThumbnail round-trips as null, not an empty list', () {
      final book = Book(
        id: 'no-cover',
        title: 't',
        author: 'a',
        pageCount: 1,
        currentPage: 1,
        coverGradientIndex: 0,
        lastOpenedAt: DateTime.utc(2026, 1, 1),
      );
      final decoded = Book.fromJson(book.toJson());
      expect(decoded.coverThumbnail, isNull);
    });
  });

  group('Collection.toJson/fromJson', () {
    test('round-trips every field', () {
      final collection = Collection(
        id: 'col1',
        name: 'Sci-Fi',
        colorIndex: 4,
        updatedAt: DateTime.utc(2026, 2, 1, 9, 0),
      );
      final decoded = Collection.fromJson(collection.toJson());

      expect(decoded.id, collection.id);
      expect(decoded.name, collection.name);
      expect(decoded.colorIndex, collection.colorIndex);
      expect(decoded.updatedAt, collection.updatedAt);
    });

    test('fromJson defaults missing name/colorIndex', () {
      final decoded = Collection.fromJson({'id': 'legacy-col'});
      expect(decoded.id, 'legacy-col');
      expect(decoded.name, 'Untitled collection');
      expect(decoded.colorIndex, 0);
      // No persisted updatedAt: falls back to "now" (see Collection.fromJson).
      expect(
        decoded.updatedAt.difference(DateTime.now()).inSeconds.abs(),
        lessThan(5),
      );
    });
  });
}
