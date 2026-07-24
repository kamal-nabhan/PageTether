import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../reader/reader_screen.dart';
import 'library_providers.dart';
import 'widgets/book_card.dart';
import 'widgets/library_sidebar.dart';

/// Breakpoint above which the permanent sidebar replaces the bottom nav.
const double kDesktopBreakpoint = 800;

/// The library/dashboard screen: PageTether's home screen.
///
/// Responsive by width only (no external package) — a permanent sidebar
/// with a card grid on desktop, a bottom [NavigationBar] with a tighter
/// grid on mobile. Book cards use mock data; opening a book (mock or real)
/// either resumes a previously picked local file or launches the file
/// picker so the user can choose one.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    final book = await ref.read(libraryProvider.notifier).openLocalPdf();
    if (book == null || !context.mounted) return;
    ref.read(selectedBookProvider.notifier).select(book);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
  }

  Future<void> _openBook(BuildContext context, WidgetRef ref, Book book) async {
    if (!book.hasSource) {
      // Mock entries have no real PDF behind them yet, so fall back to the
      // file picker rather than pretending to open a document.
      await _openPdf(context, ref);
      return;
    }
    ref.read(selectedBookProvider.notifier).select(book);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider);
    final selectedCollection = ref.watch(selectedCollectionProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= kDesktopBreakpoint;

        final content = _LibraryContent(
          books: books,
          crossAxisCount: isDesktop
              ? (constraints.maxWidth / 240).floor().clamp(3, 6)
              : (constraints.maxWidth / 190).floor().clamp(2, 3),
          onOpenBook: (book) => _openBook(context, ref, book),
        );

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                LibrarySidebar(
                  selected: selectedCollection,
                  onSelect: (c) =>
                      ref.read(selectedCollectionProvider.notifier).select(c),
                  onOpenPdf: () => _openPdf(context, ref),
                ),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('PageTether'),
            actions: [
              IconButton(
                tooltip: 'Open PDF',
                icon: const Icon(Icons.file_open_rounded),
                onPressed: () => _openPdf(context, ref),
              ),
            ],
          ),
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedCollection.index,
            onDestinationSelected: (index) => ref
                .read(selectedCollectionProvider.notifier)
                .select(LibraryCollection.values[index]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view_rounded),
                label: 'All Books',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_rounded),
                label: 'Favorites',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_rounded),
                label: 'Recent',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.books,
    required this.crossAxisCount,
    required this.onOpenBook,
  });

  final List<Book> books;
  final int crossAxisCount;
  final ValueChanged<Book> onOpenBook;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Library',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${books.length} book${books.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: 0.62,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final book = books[index];
                return BookCard(book: book, onOpen: () => onOpenBook(book));
              },
              childCount: books.length,
            ),
          ),
        ),
      ],
    );
  }
}
