// Unit tests for LibraryNotifier's last-write-wins remote merge
// (lib/features/library/library_providers.dart): mergeRemoteBooks and its
// mergeRemoteBookAndGetPage wrapper, used by "Sync now" and the reader's
// per-book pull loop respectively. Drives the notifier via a real
// ProviderContainer with libraryStoreProvider backed by mocked
// SharedPreferences — no real Supabase/Drive calls.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagetether/core/models/book.dart';
import 'package:pagetether/core/services/sync/sync_engine.dart';
import 'package:pagetether/core/storage/library_store.dart';
import 'package:pagetether/features/library/library_providers.dart';

Book _localBook({
  required String id,
  required DateTime updatedAt,
  DateTime? lastOpenedAt,
  int currentPage = 1,
  bool isFavorite = false,
  String title = 'Local title',
}) {
  return Book(
    id: id,
    title: title,
    author: 'Local author',
    pageCount: 100,
    currentPage: currentPage,
    coverGradientIndex: 0,
    lastOpenedAt: lastOpenedAt ?? updatedAt,
    updatedAt: updatedAt,
    isFavorite: isFavorite,
  );
}

SyncedBook _remoteBook({
  required String id,
  required DateTime updatedAt,
  int currentPage = 1,
  int pageCount = 100,
  bool isFavorite = false,
  String title = 'Remote title',
  String? driveFileId,
  Set<String> collectionIds = const {},
}) {
  return SyncedBook(
    bookId: id,
    title: title,
    author: 'Remote author',
    currentPage: currentPage,
    pageCount: pageCount,
    isFavorite: isFavorite,
    driveFileId: driveFileId,
    collectionIds: collectionIds,
    updatedAt: updatedAt,
  );
}

Future<ProviderContainer> _containerWith(List<Book> initialBooks) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      libraryStoreProvider.overrideWithValue(LibraryStore(prefs)),
      libraryProvider.overrideWith(() => LibraryNotifier(initialBooks)),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryNotifier.mergeRemoteBooks', () {
    test('adds a book that only exists remotely', () async {
      final container = await _containerWith(const []);
      addTearDown(container.dispose);

      final remote = _remoteBook(
        id: 'r1',
        updatedAt: DateTime.utc(2026, 1, 1),
        currentPage: 7,
        driveFileId: 'drive-1',
      );
      final result = container
          .read(libraryProvider.notifier)
          .mergeRemoteBooks([remote]);

      expect(result, (added: 1, updated: 0));
      final book = container
          .read(libraryProvider)
          .singleWhere((b) => b.id == 'r1');
      expect(book.title, 'Remote title');
      expect(book.currentPage, 7);
      expect(book.driveFileId, 'drive-1');
      expect(book.source, BookSource.drive);
    });

    test('a remote-only book with no driveFileId is added as local source', () async {
      final container = await _containerWith(const []);
      addTearDown(container.dispose);

      final remote = _remoteBook(id: 'r1', updatedAt: DateTime.utc(2026, 1, 1));
      container.read(libraryProvider.notifier).mergeRemoteBooks([remote]);

      final book = container
          .read(libraryProvider)
          .singleWhere((b) => b.id == 'r1');
      expect(book.source, BookSource.local);
    });

    test('keeps the local copy when local.updatedAt is strictly newer', () async {
      final local = _localBook(
        id: 'b1',
        updatedAt: DateTime.utc(2026, 6, 1),
        currentPage: 50,
        title: 'My local edit',
      );
      final container = await _containerWith([local]);
      addTearDown(container.dispose);

      final remote = _remoteBook(
        id: 'b1',
        updatedAt: DateTime.utc(2026, 1, 1),
        currentPage: 1,
        title: 'Stale remote',
      );
      final result = container
          .read(libraryProvider.notifier)
          .mergeRemoteBooks([remote]);

      expect(result, (added: 0, updated: 0));
      final book = container
          .read(libraryProvider)
          .singleWhere((b) => b.id == 'b1');
      expect(book.title, 'My local edit');
      expect(book.currentPage, 50);
    });

    test('keeps the local copy when timestamps are exactly equal', () async {
      final same = DateTime.utc(2026, 3, 1);
      final local = _localBook(
        id: 'b1',
        updatedAt: same,
        currentPage: 10,
        title: 'Local',
      );
      final container = await _containerWith([local]);
      addTearDown(container.dispose);

      final remote = _remoteBook(
        id: 'b1',
        updatedAt: same,
        currentPage: 99,
        title: 'Remote',
      );
      final result = container
          .read(libraryProvider.notifier)
          .mergeRemoteBooks([remote]);

      expect(result, (added: 0, updated: 0));
      final book = container
          .read(libraryProvider)
          .singleWhere((b) => b.id == 'b1');
      expect(book.title, 'Local');
      expect(book.currentPage, 10);
    });

    test('adopts the remote row when it is strictly newer than local', () async {
      final localLastOpened = DateTime.utc(2025, 12, 1);
      final local = _localBook(
        id: 'b1',
        updatedAt: DateTime.utc(2026, 1, 1),
        lastOpenedAt: localLastOpened,
        currentPage: 1,
        title: 'Old title',
      );
      final container = await _containerWith([local]);
      addTearDown(container.dispose);

      final remoteUpdatedAt = DateTime.utc(2026, 2, 1);
      final remote = _remoteBook(
        id: 'b1',
        updatedAt: remoteUpdatedAt,
        currentPage: 88,
        isFavorite: true,
        title: 'New title from another device',
        collectionIds: const {'c1'},
      );
      final result = container
          .read(libraryProvider.notifier)
          .mergeRemoteBooks([remote]);

      expect(result, (added: 0, updated: 1));
      final book = container
          .read(libraryProvider)
          .singleWhere((b) => b.id == 'b1');
      expect(book.title, 'New title from another device');
      expect(book.currentPage, 88);
      expect(book.isFavorite, isTrue);
      expect(book.collectionIds, {'c1'});
      expect(book.updatedAt, remoteUpdatedAt);
      // lastOpenedAt is a purely local concept the merge never touches.
      expect(book.lastOpenedAt, localLastOpened);
    });

    test('is a no-op when remoteBooks is empty', () async {
      final local = _localBook(id: 'b1', updatedAt: DateTime.utc(2026, 1, 1));
      final container = await _containerWith([local]);
      addTearDown(container.dispose);

      final result = container
          .read(libraryProvider.notifier)
          .mergeRemoteBooks(const []);
      expect(result, (added: 0, updated: 0));
    });
  });

  group('LibraryNotifier.mergeRemoteBookAndGetPage', () {
    test('returns the adopted page when the remote book is newly added', () async {
      final container = await _containerWith(const []);
      addTearDown(container.dispose);

      final remote = _remoteBook(
        id: 'r1',
        updatedAt: DateTime.utc(2026, 1, 1),
        currentPage: 42,
      );
      final page = container
          .read(libraryProvider.notifier)
          .mergeRemoteBookAndGetPage(remote);

      expect(page, 42);
    });

    test('returns null when the local copy is newer (remote not adopted)', () async {
      final local = _localBook(
        id: 'b1',
        updatedAt: DateTime.utc(2026, 6, 1),
        currentPage: 5,
      );
      final container = await _containerWith([local]);
      addTearDown(container.dispose);

      final remote = _remoteBook(
        id: 'b1',
        updatedAt: DateTime.utc(2026, 1, 1),
        currentPage: 999,
      );
      final page = container
          .read(libraryProvider.notifier)
          .mergeRemoteBookAndGetPage(remote);

      expect(page, isNull);
      final book = container
          .read(libraryProvider)
          .singleWhere((b) => b.id == 'b1');
      expect(book.currentPage, 5);
    });

    test('returns null when timestamps are exactly equal', () async {
      final same = DateTime.utc(2026, 3, 1);
      final local = _localBook(id: 'b1', updatedAt: same, currentPage: 5);
      final container = await _containerWith([local]);
      addTearDown(container.dispose);

      final remote = _remoteBook(id: 'b1', updatedAt: same, currentPage: 999);
      final page = container
          .read(libraryProvider.notifier)
          .mergeRemoteBookAndGetPage(remote);

      expect(page, isNull);
    });

    test('returns the adopted page when the remote row is strictly newer', () async {
      final local = _localBook(
        id: 'b1',
        updatedAt: DateTime.utc(2026, 1, 1),
        currentPage: 5,
      );
      final container = await _containerWith([local]);
      addTearDown(container.dispose);

      final remote = _remoteBook(
        id: 'b1',
        updatedAt: DateTime.utc(2026, 2, 1),
        currentPage: 77,
      );
      final page = container
          .read(libraryProvider.notifier)
          .mergeRemoteBookAndGetPage(remote);

      expect(page, 77);
    });
  });
}
