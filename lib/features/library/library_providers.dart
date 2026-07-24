import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../core/pdf/pdf_document_tools.dart';
import '../../core/pdf/pdf_source.dart';
import '../../core/storage/library_store.dart';
import '../../core/storage/pdf_hash.dart';
import '../../core/theme/app_theme.dart';

/// The collections shown in the sidebar (desktop) / bottom nav (mobile).
///
/// Phase 1.1 still treats these as visual/highlight-only filters — there is
/// no favorites/recent tracking yet, so selecting one just changes which
/// nav item is highlighted.
enum LibraryCollection { allBooks, favorites, recent }

extension LibraryCollectionLabel on LibraryCollection {
  String get label => switch (this) {
    LibraryCollection.allBooks => 'All Books',
    LibraryCollection.favorites => 'Favorites',
    LibraryCollection.recent => 'Recent',
  };
}

/// Currently highlighted collection in the sidebar/bottom nav.
///
/// Riverpod 3 moved `StateProvider` to a legacy import and made `state =`
/// protected on plain [Notifier]s, so external widgets can no longer set it
/// directly — call [select] instead.
class SelectedCollectionNotifier extends Notifier<LibraryCollection> {
  @override
  LibraryCollection build() => LibraryCollection.allBooks;

  void select(LibraryCollection collection) => state = collection;
}

final selectedCollectionProvider =
    NotifierProvider<SelectedCollectionNotifier, LibraryCollection>(
      SelectedCollectionNotifier.new,
    );

/// The book the reader screen should currently display.
///
/// Set right before navigating to the reader screen so it can pull the
/// [Book] (and therefore its PDF source) back out via Riverpod instead of
/// threading it through constructor arguments alone.
class SelectedBookNotifier extends Notifier<Book?> {
  @override
  Book? build() => null;

  void select(Book? book) => state = book;
}

final selectedBookProvider = NotifierProvider<SelectedBookNotifier, Book?>(
  SelectedBookNotifier.new,
);

/// The [LibraryStore] singleton. Overridden in `main()` with a real
/// instance backed by an already-initialized [SharedPreferences] — the
/// default here only exists so the provider graph type-checks before that
/// override is applied.
final libraryStoreProvider = Provider<LibraryStore>((ref) {
  throw UnimplementedError(
    'libraryStoreProvider must be overridden in main() with a real LibraryStore',
  );
});

/// Holds the library's book list: whatever was persisted locally (via
/// [LibraryStore]) plus the bundled sample book, loaded once in `main()`
/// before `runApp` so the very first frame already shows real data — no
/// hardcoded mock entries.
class LibraryNotifier extends Notifier<List<Book>> {
  LibraryNotifier([this._initialBooks = const []]);

  final List<Book> _initialBooks;

  @override
  List<Book> build() => _initialBooks;

  LibraryStore get _store => ref.read(libraryStoreProvider);

  /// Opens the platform file picker restricted to PDFs.
  ///
  /// If the picked file's content hash matches a book already in the
  /// library (e.g. a desktop file that moved, or a web re-pick after a
  /// reload lost its in-memory bytes), the existing entry is refreshed in
  /// place instead of duplicated, so progress carries over. Returns the
  /// resulting [Book], or null if the user cancelled the picker.
  Future<Book?> openLocalPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      // Reading bytes on every platform (not just web) keeps content
      // hashing and cover-thumbnail rendering simple and uniform, at the
      // cost of reading the file into memory once at pick time.
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) return null;
    final String? path = file.path;

    final id = contentIdForBytes(bytes);
    final source = PdfSource.data(bytes, name: file.name);
    final pageCount = await readPdfPageCount(source);

    final existingIndex = state.indexWhere((b) => b.id == id);
    final Book book;
    if (existingIndex != -1) {
      book = state[existingIndex].copyWith(
        pageCount: pageCount > 0 ? pageCount : state[existingIndex].pageCount,
        filePath: path,
        fileBytes: bytes,
        openedOnWeb: path == null,
        lastOpenedAt: DateTime.now(),
      );
    } else {
      book = Book(
        id: id,
        title: _titleFromFileName(file.name),
        author: 'Opened from device',
        pageCount: pageCount,
        currentPage: 1,
        coverGradientIndex: state.length % kCoverGradients.length,
        filePath: path,
        fileBytes: bytes,
        openedOnWeb: path == null,
        lastOpenedAt: DateTime.now(),
      );
    }

    state = [book, for (final b in state) if (b.id != id) b];
    unawaited(_store.upsert(book));
    unawaited(_ensureThumbnail(book));
    return book;
  }

  /// Records reading progress for [bookId] (a content id) and persists it
  /// immediately. No-ops if the book isn't in the library (e.g. it was
  /// removed) or nothing actually changed.
  void recordProgress(
    String bookId, {
    required int currentPage,
    required int pageCount,
  }) {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;

    final existing = state[index];
    final resolvedPageCount = pageCount > 0 ? pageCount : existing.pageCount;
    if (existing.currentPage == currentPage &&
        existing.pageCount == resolvedPageCount) {
      return;
    }

    final updated = existing.copyWith(
      currentPage: currentPage,
      pageCount: resolvedPageCount,
      lastOpenedAt: DateTime.now(),
    );
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Renders and caches the page-1 cover thumbnail for [book] if it doesn't
  /// have one yet. Fire-and-forget: failures just leave the gradient
  /// fallback in place.
  Future<void> _ensureThumbnail(Book book) async {
    if (book.coverThumbnail != null) return;
    final source = PdfSource.fromBook(book);
    if (source == null) return;

    final thumbnail = await renderCoverThumbnail(source);
    if (thumbnail == null) return;

    final index = state.indexWhere((b) => b.id == book.id);
    if (index == -1) return;
    final updated = state[index].copyWith(coverThumbnail: thumbnail);
    state = [for (final b in state) if (b.id == book.id) updated else b];
    unawaited(_store.upsert(updated));
  }

  static String _titleFromFileName(String fileName) {
    final withoutExtension = fileName.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    return withoutExtension.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<Book>>(
  LibraryNotifier.new,
);
