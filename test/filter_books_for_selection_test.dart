// Unit tests for filterBooksForSelection (lib/features/library/library_providers.dart):
// the pure function behind the library dashboard's All/Favorites/Recent/
// Custom-collection views. Pure logic, no device/network.
import 'package:flutter_test/flutter_test.dart';
import 'package:pagetether/core/models/book.dart';
import 'package:pagetether/features/library/library_providers.dart';

Book _book(
  String id, {
  bool isFavorite = false,
  DateTime? lastOpenedAt,
  Set<String> collectionIds = const {},
}) => Book(
  id: id,
  title: 'Title $id',
  author: 'Author',
  pageCount: 100,
  currentPage: 1,
  coverGradientIndex: 0,
  // Matches library_bootstrap's "never really opened" sentinel unless
  // overridden.
  lastOpenedAt: lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
  isFavorite: isFavorite,
  collectionIds: collectionIds,
);

void main() {
  group('filterBooksForSelection', () {
    test('AllBooks returns every book unchanged', () {
      final books = [_book('a'), _book('b')];
      expect(filterBooksForSelection(books, const AllBooks()), books);
    });

    test('Favorites returns only favorited books', () {
      final a = _book('a', isFavorite: true);
      final b = _book('b');
      final result = filterBooksForSelection([a, b], const Favorites());
      expect(result, [a]);
    });

    test('Favorites is empty when nothing is favorited', () {
      final books = [_book('a'), _book('b')];
      expect(filterBooksForSelection(books, const Favorites()), isEmpty);
    });

    test('Recent excludes books at the never-opened epoch sentinel', () {
      final neverOpened = _book('a');
      final opened = _book('b', lastOpenedAt: DateTime.utc(2026, 1, 1));
      final result = filterBooksForSelection([neverOpened, opened], const Recent());
      expect(result.map((b) => b.id), ['b']);
    });

    test('Recent sorts most-recently-opened first', () {
      final older = _book('a', lastOpenedAt: DateTime.utc(2025, 1, 1));
      final newer = _book('b', lastOpenedAt: DateTime.utc(2026, 1, 1));
      final result = filterBooksForSelection([older, newer], const Recent());
      expect(result.map((b) => b.id), ['b', 'a']);
    });

    test('Recent caps at recentLimit', () {
      final books = [
        for (var i = 0; i < 5; i++)
          _book('b$i', lastOpenedAt: DateTime.utc(2026, 1, i + 1)),
      ];
      final result = filterBooksForSelection(
        books,
        const Recent(),
        recentLimit: 2,
      );
      expect(result, hasLength(2));
      expect(result.map((b) => b.id), ['b4', 'b3']);
    });

    test('Custom returns only books that belong to the given collection', () {
      final a = _book('a', collectionIds: {'c1'});
      final b = _book('b', collectionIds: {'c2'});
      final c = _book('c', collectionIds: {'c1', 'c2'});
      final result = filterBooksForSelection([a, b, c], const Custom('c1'));
      expect(result.map((b) => b.id).toSet(), {'a', 'c'});
    });

    test('Custom is empty for an unknown collection id', () {
      final books = [_book('a', collectionIds: {'c1'})];
      final result = filterBooksForSelection(books, const Custom('missing'));
      expect(result, isEmpty);
    });
  });
}
