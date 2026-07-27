// Unit tests for LibraryStore (lib/core/storage/library_store.dart) — the
// SharedPreferences-backed local persistence for books, collections, view
// mode, and BYOD sync credentials. Uses SharedPreferences.setMockInitialValues
// so no real platform storage is touched.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagetether/core/models/book.dart';
import 'package:pagetether/core/models/collection.dart';
import 'package:pagetether/core/models/library_view_mode.dart';
import 'package:pagetether/core/models/sync_credentials.dart';
import 'package:pagetether/core/storage/library_store.dart';

Book _book(String id, {DateTime? lastOpenedAt}) => Book(
  id: id,
  title: 'Title $id',
  author: 'Author $id',
  pageCount: 100,
  currentPage: 5,
  coverGradientIndex: 0,
  lastOpenedAt: lastOpenedAt ?? DateTime.utc(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LibraryStore books', () {
    test('loadAll starts empty', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      expect(await store.loadAll(), isEmpty);
    });

    test('upsert then loadAll round-trips a book', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsert(_book('b1'));

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'b1');
      expect(loaded.first.title, 'Title b1');
      expect(loaded.first.currentPage, 5);
    });

    test('upsert overwrites an existing record with the same id', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsert(_book('b1'));
      await store.upsert(_book('b1').copyWith(title: 'Renamed'));

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.title, 'Renamed');
    });

    test('remove deletes a single record', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsert(_book('b1'));
      await store.upsert(_book('b2'));
      await store.remove('b1');

      final loaded = await store.loadAll();
      expect(loaded.map((b) => b.id), ['b2']);
    });

    test('remove is a no-op for an unknown id', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsert(_book('b1'));
      await store.remove('does-not-exist');
      expect(await store.loadAll(), hasLength(1));
    });

    test('saveAll replaces the entire persisted library', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsert(_book('b1'));
      await store.saveAll([_book('b2'), _book('b3')]);

      final loaded = await store.loadAll();
      expect(loaded.map((b) => b.id).toSet(), {'b2', 'b3'});
    });

    test('loadAll sorts most-recently-opened first', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.saveAll([
        _book('old', lastOpenedAt: DateTime.utc(2025, 1, 1)),
        _book('new', lastOpenedAt: DateTime.utc(2026, 1, 1)),
      ]);

      final loaded = await store.loadAll();
      expect(loaded.map((b) => b.id), ['new', 'old']);
    });
  });

  group('LibraryStore collections', () {
    test('loadCollections starts empty', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      expect(await store.loadCollections(), isEmpty);
    });

    test('saveCollections then loadCollections round-trips', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      final collection = Collection(id: 'c1', name: 'Sci-Fi', colorIndex: 2);
      await store.saveCollections([collection]);

      final loaded = await store.loadCollections();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'c1');
      expect(loaded.first.name, 'Sci-Fi');
      expect(loaded.first.colorIndex, 2);
    });
  });

  group('LibraryStore view mode', () {
    test('defaults to gridMedium when nothing saved', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      expect(await store.loadViewMode(), LibraryViewMode.gridMedium);
    });

    test('saveViewMode then loadViewMode round-trips', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.saveViewMode(LibraryViewMode.list);
      expect(await store.loadViewMode(), LibraryViewMode.list);
    });
  });

  group('LibraryStore sync credentials', () {
    test('defaults to empty when nothing saved', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      final creds = await store.loadSyncCredentials();
      expect(creds.isConfigured, isFalse);
    });

    test('saveSyncCredentials then loadSyncCredentials round-trips', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      const creds = SyncCredentials(
        url: 'https://example.supabase.co',
        anonKey: 'anon-key',
      );
      await store.saveSyncCredentials(creds);

      final loaded = await store.loadSyncCredentials();
      expect(loaded.url, creds.url);
      expect(loaded.anonKey, creds.anonKey);
      expect(loaded.isConfigured, isTrue);
    });

    test('clearSyncCredentials forgets saved credentials', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.saveSyncCredentials(
        const SyncCredentials(url: 'https://x.supabase.co', anonKey: 'k'),
      );
      await store.clearSyncCredentials();

      final loaded = await store.loadSyncCredentials();
      expect(loaded.isConfigured, isFalse);
    });
  });
}
