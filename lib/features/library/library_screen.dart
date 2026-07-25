import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/auth/auth_state.dart';
import '../../core/theme/app_theme.dart';
import '../reader/reader_screen.dart';
import 'library_providers.dart';
import 'widgets/book_card.dart';
import 'widgets/drive_auth_panel.dart';
import 'widgets/library_sidebar.dart';

/// Breakpoint above which the permanent sidebar replaces the bottom nav.
const double kDesktopBreakpoint = 800;

/// The library/dashboard screen: PageTether's home screen.
///
/// Responsive by width only (no external package) — a permanent sidebar
/// with a card grid on desktop, a bottom [NavigationBar] with a tighter
/// grid on mobile. Every card is a real, persisted local PDF (the bundled
/// sample book plus whatever the user has opened) — there is no mock data.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

/// A [ConsumerState] (rather than a plain [ConsumerWidget]) purely so this
/// screen can observe app lifecycle transitions via [WidgetsBindingObserver]
/// — see [didChangeAppLifecycleState] — to auto-refresh the Drive library
/// when the app comes back to the foreground (covers another device having
/// added/removed a file while this one was backgrounded).
class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  /// Minimum gap between auto-refreshes triggered by resuming — otherwise
  /// quickly alt-tabbing (desktop) or repeatedly foregrounding the app
  /// (mobile/web tab-switching) would spam Drive with duplicate `files.list`
  /// calls for no benefit.
  static const _autoRefreshDebounce = Duration(seconds: 30);

  DateTime? _lastAutoRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `resumed` fires both for a real mobile/desktop foreground and — since
    // Flutter's web engine maps the Page Visibility API onto the same
    // lifecycle enum — for a browser tab becoming visible again, so this
    // one check covers both "auto-refresh on resume" and "on web
    // visibility" without platform-specific code.
    if (state != AppLifecycleState.resumed) return;
    _maybeAutoRefreshFromDrive();
  }

  void _maybeAutoRefreshFromDrive() {
    final authState = ref.read(authProvider);
    if (authState is! AuthStateSignedIn || !authState.hasDriveAccess) return;

    final now = DateTime.now();
    final last = _lastAutoRefresh;
    if (last != null && now.difference(last) < _autoRefreshDebounce) return;
    _lastAutoRefresh = now;
    ref.read(libraryProvider.notifier).hydrateFromDrive();
  }

  Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    final book = await ref.read(libraryProvider.notifier).openLocalPdf();
    if (book == null || !context.mounted) return;
    ref.read(selectedBookProvider.notifier).select(book);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
  }

  Future<void> _openBook(BuildContext context, WidgetRef ref, Book book) async {
    if (book.isDriveBook && !book.hasLiveSource) {
      // Drive book that hasn't been downloaded to this device yet (or, on
      // web, whose in-memory bytes were lost to a page reload) — download
      // it to the cache first, then open the freshly-updated Book.
      final downloaded = await ref
          .read(libraryProvider.notifier)
          .downloadDriveBook(book.id);
      if (downloaded == null || !context.mounted) return;
      ref.read(selectedBookProvider.notifier).select(downloaded);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ReaderScreen(book: downloaded)),
      );
      return;
    }

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

  void _deleteDriveBook(WidgetRef ref, Book book) {
    ref.read(libraryProvider.notifier).deleteDriveBook(book.id);
  }

  void _changeCover(WidgetRef ref, Book book) {
    ref.read(libraryProvider.notifier).pickAndSetCover(book.id);
  }

  void _resetCover(WidgetRef ref, Book book) {
    ref.read(libraryProvider.notifier).resetCover(book.id);
  }

  void _openDriveSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [DriveAuthPanel(), DriveUploadButton()],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(libraryProvider);
    final selectedCollection = ref.watch(selectedCollectionProvider);

    // Hydrate the grid from Drive exactly once per sign-in transition (not
    // automatically on launch — only once the user actually connects, per
    // the Phase 2 plan), by watching for the moment `hasDriveAccess` first
    // becomes true.
    ref.listen<AuthState>(authProvider, (previous, next) {
      final wasReady = previous is AuthStateSignedIn && previous.hasDriveAccess;
      final isReady = next is AuthStateSignedIn && next.hasDriveAccess;
      if (isReady && !wasReady) {
        ref.read(libraryProvider.notifier).hydrateFromDrive();
      }
    });

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
          onDeleteBook: (book) => _deleteDriveBook(ref, book),
          onChangeCover: (book) => _changeCover(ref, book),
          onResetCover: (book) => _resetCover(ref, book),
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
                tooltip: 'Google Drive',
                icon: const Icon(Icons.add_to_drive_rounded),
                onPressed: () => _openDriveSheet(context),
              ),
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
    required this.onDeleteBook,
    required this.onChangeCover,
    required this.onResetCover,
  });

  final List<Book> books;
  final int crossAxisCount;
  final ValueChanged<Book> onOpenBook;
  final VoidCallback onOpenPdf;
  final ValueChanged<Book> onDeleteBook;
  final ValueChanged<Book> onChangeCover;
  final ValueChanged<Book> onResetCover;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return _EmptyLibraryView(onOpenPdf: onOpenPdf);
    }

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _DriveSyncBanner()),
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
                return BookCard(
                  book: book,
                  onOpen: () => onOpenBook(book),
                  onDelete: book.isDriveBook ? () => onDeleteBook(book) : null,
                  onChangeCover: () => onChangeCover(book),
                  onResetCover: book.hasLiveSource
                      ? () => onResetCover(book)
                      : null,
                );
              },
              childCount: books.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// Slim banner showing the current [driveSyncProvider] state: hidden when
/// idle, a spinner + message while a Drive hydrate/upload/download/delete
/// is in flight, or a dismissible error strip if the last one failed.
class _DriveSyncBanner extends ConsumerWidget {
  const _DriveSyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(driveSyncProvider);
    return switch (syncState) {
      DriveSyncIdle() => const SizedBox.shrink(),
      DriveSyncLoading(:final message) => _Banner(
        color: AppColors.panel,
        icon: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        message: message,
      ),
      DriveSyncError(:final message) => _Banner(
        color: const Color(0x33EF4444),
        icon: const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFEF4444)),
        message: message,
        onDismiss: () => ref.read(driveSyncProvider.notifier).setIdle(),
      ),
    };
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.message,
    this.onDismiss,
  });

  final Color color;
  final Widget icon;
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
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
