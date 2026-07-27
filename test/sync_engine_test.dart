// Row (de)serialization tests for SyncedBook/SyncedCollection
// (lib/core/services/sync/sync_engine.dart), the thin shapes SyncEngine
// pushes/pulls against Supabase. Asserts the row keys these produce/consume
// match schema.sql's pt_books/pt_collections column names exactly, since a
// mismatch there would silently null out columns on upsert. Pure logic —
// no real Supabase client involved.
import 'package:flutter_test/flutter_test.dart';
import 'package:pagetether/core/services/sync/sync_engine.dart';

void main() {
  group('SyncedBook.fromRow/toRow', () {
    test('fromRow parses a schema.sql-shaped pt_books row', () {
      final row = {
        'user_id': 'user-1',
        'book_id': 'book-1',
        'title': 'A Title',
        'author': 'An Author',
        'current_page': 42,
        'page_count': 200,
        'is_favorite': true,
        'drive_file_id': 'drive-1',
        'collection_ids': ['c1', 'c2'],
        'updated_at': '2026-03-15T10:30:00.000Z',
      };
      final book = SyncedBook.fromRow(row);

      expect(book.bookId, 'book-1');
      expect(book.title, 'A Title');
      expect(book.author, 'An Author');
      expect(book.currentPage, 42);
      expect(book.pageCount, 200);
      expect(book.isFavorite, isTrue);
      expect(book.driveFileId, 'drive-1');
      expect(book.collectionIds, {'c1', 'c2'});
      expect(book.updatedAt, DateTime.parse('2026-03-15T10:30:00.000Z'));
    });

    test('fromRow defaults missing optional columns', () {
      final book = SyncedBook.fromRow({'book_id': 'book-1'});
      expect(book.title, '');
      expect(book.author, '');
      expect(book.currentPage, 1);
      expect(book.pageCount, 0);
      expect(book.isFavorite, isFalse);
      expect(book.driveFileId, isNull);
      expect(book.collectionIds, isEmpty);
    });

    test('toRow produces exactly the pt_books columns from schema.sql', () {
      final book = SyncedBook(
        bookId: 'book-1',
        title: 'A Title',
        author: 'An Author',
        currentPage: 42,
        pageCount: 200,
        isFavorite: true,
        driveFileId: 'drive-1',
        collectionIds: const {'c1', 'c2'},
        updatedAt: DateTime.utc(2026, 3, 15, 10, 30),
      );
      final row = book.toRow('user-1');

      expect(row.keys.toSet(), {
        'user_id',
        'book_id',
        'title',
        'author',
        'current_page',
        'page_count',
        'is_favorite',
        'drive_file_id',
        'collection_ids',
        'updated_at',
      });
      expect(row['user_id'], 'user-1');
      expect(row['book_id'], 'book-1');
      expect(row['current_page'], 42);
      expect(row['page_count'], 200);
      expect(row['is_favorite'], isTrue);
      expect(row['drive_file_id'], 'drive-1');
      expect((row['collection_ids'] as List).toSet(), {'c1', 'c2'});
      expect(row['updated_at'], '2026-03-15T10:30:00.000Z');
    });

    test('round-trips through fromRow(toRow(...))', () {
      final original = SyncedBook(
        bookId: 'book-2',
        title: 'Round Trip',
        author: 'Author',
        currentPage: 5,
        pageCount: 10,
        isFavorite: false,
        driveFileId: null,
        collectionIds: const {},
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final roundTripped = SyncedBook.fromRow(original.toRow('user-1'));

      expect(roundTripped.bookId, original.bookId);
      expect(roundTripped.title, original.title);
      expect(roundTripped.currentPage, original.currentPage);
      expect(roundTripped.pageCount, original.pageCount);
      expect(roundTripped.isFavorite, original.isFavorite);
      expect(roundTripped.driveFileId, original.driveFileId);
      expect(roundTripped.collectionIds, original.collectionIds);
      expect(roundTripped.updatedAt, original.updatedAt);
    });
  });

  group('SyncedCollection.fromRow/toRow', () {
    test('fromRow parses a schema.sql-shaped pt_collections row', () {
      final row = {
        'user_id': 'user-1',
        'id': 'col-1',
        'name': 'Sci-Fi',
        'color_index': 3,
        'updated_at': '2026-02-01T09:00:00.000Z',
      };
      final collection = SyncedCollection.fromRow(row);

      expect(collection.id, 'col-1');
      expect(collection.name, 'Sci-Fi');
      expect(collection.colorIndex, 3);
      expect(collection.updatedAt, DateTime.parse('2026-02-01T09:00:00.000Z'));
    });

    test('toRow produces exactly the pt_collections columns from schema.sql', () {
      final collection = SyncedCollection(
        id: 'col-1',
        name: 'Sci-Fi',
        colorIndex: 3,
        updatedAt: DateTime.utc(2026, 2, 1, 9, 0),
      );
      final row = collection.toRow('user-1');

      expect(row.keys.toSet(), {
        'user_id',
        'id',
        'name',
        'color_index',
        'updated_at',
      });
      expect(row['user_id'], 'user-1');
      expect(row['id'], 'col-1');
      expect(row['name'], 'Sci-Fi');
      expect(row['color_index'], 3);
      expect(row['updated_at'], '2026-02-01T09:00:00.000Z');
    });

    test('round-trips through fromRow(toRow(...))', () {
      final original = SyncedCollection(
        id: 'col-2',
        name: 'Fantasy',
        colorIndex: 1,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final roundTripped = SyncedCollection.fromRow(original.toRow('user-1'));

      expect(roundTripped.id, original.id);
      expect(roundTripped.name, original.name);
      expect(roundTripped.colorIndex, original.colorIndex);
      expect(roundTripped.updatedAt, original.updatedAt);
    });
  });
}
