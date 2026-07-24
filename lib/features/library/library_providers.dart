import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../core/theme/app_theme.dart';

/// The collections shown in the sidebar (desktop) / bottom nav (mobile).
///
/// Phase 1 treats these as visual/highlight-only filters — there is no
/// favorites/recent tracking yet, so selecting one just changes which nav
/// item is highlighted.
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

/// Holds the library's book list: a handful of mock entries to make the
/// dashboard look populated, plus whatever real PDFs the user has opened
/// from disk during this session (Phase 1 has no persistence, so this
/// resets on every app restart).
class LibraryNotifier extends Notifier<List<Book>> {
  @override
  List<Book> build() => _mockBooks;

  /// Opens the platform file picker restricted to PDFs and, if the user
  /// picks one, prepends a new [Book] entry for it to the library.
  ///
  /// Returns the newly created [Book], or null if the user cancelled the
  /// picker or the picked file had no usable source.
  Future<Book?> openLocalPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    final String? path = file.path;
    if (bytes == null && path == null) return null;

    final title = _titleFromFileName(file.name);
    final book = Book(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      author: 'Opened from device',
      progress: 0,
      currentPage: 1,
      pageCount: 0,
      coverGradient: kCoverGradients[state.length % kCoverGradients.length],
      filePath: path,
      fileBytes: bytes,
    );
    state = [book, ...state];
    return book;
  }

  static String _titleFromFileName(String fileName) {
    final withoutExtension = fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return withoutExtension.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<Book>>(
  LibraryNotifier.new,
);

final _mockBooks = <Book>[
  Book(
    id: 'mock-1',
    title: 'Atomic Habits',
    author: 'James Clear',
    progress: 0.62,
    currentPage: 148,
    pageCount: 238,
    coverGradient: kCoverGradients[0],
  ),
  Book(
    id: 'mock-2',
    title: 'Deep Work',
    author: 'Cal Newport',
    progress: 0.31,
    currentPage: 62,
    pageCount: 204,
    coverGradient: kCoverGradients[1],
  ),
  Book(
    id: 'mock-3',
    title: 'The Pragmatic Programmer',
    author: 'David Thomas & Andrew Hunt',
    progress: 0.85,
    currentPage: 306,
    pageCount: 360,
    coverGradient: kCoverGradients[2],
  ),
  Book(
    id: 'mock-4',
    title: 'Sapiens',
    author: 'Yuval Noah Harari',
    progress: 0.12,
    currentPage: 55,
    pageCount: 443,
    coverGradient: kCoverGradients[3],
  ),
  Book(
    id: 'mock-5',
    title: 'Designing Data-Intensive Applications',
    author: 'Martin Kleppmann',
    progress: 0.47,
    currentPage: 210,
    pageCount: 449,
    coverGradient: kCoverGradients[4],
  ),
  Book(
    id: 'mock-6',
    title: 'Clean Architecture',
    author: 'Robert C. Martin',
    progress: 0,
    currentPage: 1,
    pageCount: 432,
    coverGradient: kCoverGradients[0],
  ),
];
