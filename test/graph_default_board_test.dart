// Unit tests for BoardsNotifier.getOrCreateDefaultBoard
// (lib/features/graph/graph_providers.dart) — the helper the reader uses so
// a book's first highlight/underline has *some* board to land on without a
// "create board" UI existing yet. Mirrors
// test/graph_providers_merge_test.dart's ProviderContainer setup.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagetether/core/models/graph/board.dart';
import 'package:pagetether/core/storage/library_store.dart';
import 'package:pagetether/features/graph/graph_providers.dart';
import 'package:pagetether/features/library/library_providers.dart'
    show libraryStoreProvider;

Future<ProviderContainer> _container({List<Board> boards = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      libraryStoreProvider.overrideWithValue(LibraryStore(prefs)),
      boardsProvider.overrideWith(() => BoardsNotifier(boards)),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardsNotifier.getOrCreateDefaultBoard', () {
    test('creates a new default board when none exists for the book', () async {
      final container = await _container();
      addTearDown(container.dispose);

      final board = container
          .read(boardsProvider.notifier)
          .getOrCreateDefaultBoard('book-1');

      expect(board.bookId, 'book-1');
      expect(board.isDefaultForBook, isTrue);
      expect(board.title, 'Highlights');
      expect(container.read(boardsProvider), [board]);
    });

    test('uses the supplied title only when actually creating', () async {
      final container = await _container();
      addTearDown(container.dispose);

      final board = container
          .read(boardsProvider.notifier)
          .getOrCreateDefaultBoard('book-1', title: 'My Book highlights');

      expect(board.title, 'My Book highlights');
    });

    test('returns the same board on a second call, ignoring a new title', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(boardsProvider.notifier);

      final first = notifier.getOrCreateDefaultBoard('book-1', title: 'First');
      final second = notifier.getOrCreateDefaultBoard('book-1', title: 'Second');

      expect(second.id, first.id);
      expect(second.title, 'First');
      expect(container.read(boardsProvider), hasLength(1));
    });

    test('does not create a duplicate when a default board already exists locally', () async {
      final existing = Board(
        id: 'existing-board',
        title: 'Already there',
        bookId: 'book-1',
        isDefaultForBook: true,
      );
      final container = await _container(boards: [existing]);
      addTearDown(container.dispose);

      final board = container
          .read(boardsProvider.notifier)
          .getOrCreateDefaultBoard('book-1');

      expect(board.id, 'existing-board');
      expect(container.read(boardsProvider), hasLength(1));
    });

    test('creates independent default boards for different books', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(boardsProvider.notifier);

      final boardA = notifier.getOrCreateDefaultBoard('book-a');
      final boardB = notifier.getOrCreateDefaultBoard('book-b');

      expect(boardA.id, isNot(boardB.id));
      expect(container.read(boardsProvider), hasLength(2));
    });

    test('ignores a non-default board belonging to the same book', () async {
      final crossBookBoard = Board(
        id: 'other-board',
        title: 'Cross-book research',
        bookId: 'book-1',
        isDefaultForBook: false,
      );
      final container = await _container(boards: [crossBookBoard]);
      addTearDown(container.dispose);

      final board = container
          .read(boardsProvider.notifier)
          .getOrCreateDefaultBoard('book-1');

      expect(board.id, isNot('other-board'));
      expect(board.isDefaultForBook, isTrue);
      expect(container.read(boardsProvider), hasLength(2));
    });
  });
}
