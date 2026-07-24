import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../core/theme/app_theme.dart';
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
/// grid on mobile. Every card is a real, persisted local PDF (the bundled
/// sample book plus whatever the user has opened) — there is no mock data.
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
    if (!book.hasLiveSource) {
      // Most commonly hit on web: the browser sandbox can't reopen a local
      // file by path after a reload, so the in-memory bytes from a prior
      // session are gone. Rather than crash (or silently do nothing), tell
      // the user why and hand them straight to the picker — re-selecting
      // the same file resolves to the same content id, so progress carries
      // over instead of creating a duplicate entry.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This session lost access to "${book.title}". Please re-select the file to continue reading.',
          ),
        ),
      );
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
          onOpenPdf: () => _openPdf(context, ref),
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
    required this.onOpenPdf,
  });

  final List<Book> books;
  final int crossAxisCount;
  final ValueChanged<Book> onOpenBook;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return _EmptyLibraryView(onOpenPdf: onOpenPdf);
    }

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

/// Shown when the library has no books at all — practically only reachable
/// if the bundled sample book failed to render on this device, since it's
/// otherwise always seeded on first launch.
class _EmptyLibraryView extends StatelessWidget {
  const _EmptyLibraryView({required this.onOpenPdf});

  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Your library is empty',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Open a PDF from your device to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOpenPdf,
              icon: const Icon(Icons.file_open_rounded),
              label: const Text('Open your first PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
