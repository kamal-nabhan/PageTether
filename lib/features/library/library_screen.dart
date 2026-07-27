import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../core/models/library_view_mode.dart';
import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/auth/auth_state.dart';
import '../../core/services/window/window_focus_service.dart'
    as window_focus;
import '../../core/theme/app_theme.dart';
import '../reader/reader_screen.dart';
import 'library_providers.dart';
import 'widgets/add_to_collection_dialog.dart';
import 'widgets/book_card.dart';
import 'widgets/book_list_tile.dart';
import 'widgets/collections_sheet.dart';
import 'widgets/drive_auth_panel.dart';
import 'widgets/library_sidebar.dart';
import 'widgets/rename_book_dialog.dart';
import 'widgets/view_mode_control.dart';

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
///
/// Desktop windows often don't emit `AppLifecycleState.resumed` just from
/// regaining OS focus (e.g. alt-tabbing back in without minimizing first),
/// so [didChangeAppLifecycleState] alone can miss that case there. This is
/// supplemented with a `window_manager` focus listener (see
/// [window_focus]/`window_focus_service.dart`) that's a no-op on
/// mobile/web, where the lifecycle observer already covers it. Both paths
/// funnel through the same debounced [_maybeAutoRefreshFromDrive], so they
/// never stack duplicate `files.list` calls.
class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  /// Minimum gap between auto-refreshes triggered by resuming/refocusing —
  /// otherwise quickly alt-tabbing (desktop) or repeatedly foregrounding the
  /// app (mobile/web tab-switching) would spam Drive with duplicate
  /// `files.list` calls for no benefit.
  static const _autoRefreshDebounce = Duration(seconds: 30);

  DateTime? _lastAutoRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    window_focus.registerDesktopWindowFocusListener(
      _maybeAutoRefreshFromDrive,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    window_focus.unregisterDesktopWindowFocusListener();
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
    if (!mounted) return;
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

  void _removeFromLibrary(WidgetRef ref, Book book) {
    ref.read(libraryProvider.notifier).removeFromLibrary(book.id);
  }

  void _changeCover(WidgetRef ref, Book book) {
    ref.read(libraryProvider.notifier).pickAndSetCover(book.id);
  }

  void _resetCover(WidgetRef ref, Book book) {
    ref.read(libraryProvider.notifier).resetCover(book.id);
  }

  void _toggleFavorite(WidgetRef ref, Book book) {
    ref.read(libraryProvider.notifier).toggleFavorite(book.id);
  }

  void _addToCollection(BuildContext context, Book book) {
    showAddToCollectionDialog(context, book);
  }

  void _renameBook(BuildContext context, WidgetRef ref, Book book) {
    showRenameBookDialog(context, ref, book);
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

  void _openCollectionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const CollectionsSheet(),
    );
  }

  /// Which bottom-nav index corresponds to [selection] — the built-ins map
  /// 1:1, and any [Custom] collection maps to the 4th "Collections"
  /// destination (which doesn't filter the grid itself; tapping it just
  /// opens [CollectionsSheet] — see [_openCollectionsSheet]).
  int _bottomNavIndexFor(LibrarySelection selection) => switch (selection) {
    AllBooks() => 0,
    Favorites() => 1,
    Recent() => 2,
    Custom() => 3,
  };

  void _onBottomNavSelected(BuildContext context, WidgetRef ref, int index) {
    switch (index) {
      case 0:
        ref.read(selectedCollectionProvider.notifier).select(const AllBooks());
      case 1:
        ref.read(selectedCollectionProvider.notifier).select(const Favorites());
      case 2:
        ref.read(selectedCollectionProvider.notifier).select(const Recent());
      default:
        _openCollectionsSheet(context);
    }
  }

  /// The grid header text for [selection] — a fixed label for each built-in
  /// view, or the matching [Collection.name] for a custom one (falling back
  /// to a generic label if it's since been deleted, e.g. a stale selection
  /// racing a delete from another part of the UI).
  String _headingLabelFor(WidgetRef ref, LibrarySelection selection) {
    switch (selection) {
      case AllBooks():
        return 'Your Library';
      case Favorites():
        return 'Favorites';
      case Recent():
        return 'Recent';
      case Custom(:final collectionId):
        for (final collection in ref.watch(collectionsProvider)) {
          if (collection.id == collectionId) return collection.name;
        }
        return 'Collection';
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(libraryProvider);
    final selection = ref.watch(selectedCollectionProvider);
    final filteredBooks = filterBooksForSelection(books, selection);
    final headingLabel = _headingLabelFor(ref, selection);
    final viewMode = ref.watch(viewModeProvider);

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
          books: filteredBooks,
          isLibraryEmpty: books.isEmpty,
          selection: selection,
          headingLabel: headingLabel,
          viewMode: viewMode,
          onViewModeChanged: (mode) =>
              ref.read(viewModeProvider.notifier).select(mode),
          onOpenBook: (book) => _openBook(context, ref, book),
          onOpenPdf: () => _openPdf(context, ref),
          onDeleteBook: (book) => _deleteDriveBook(ref, book),
          onRemoveBook: (book) => _removeFromLibrary(ref, book),
          onChangeCover: (book) => _changeCover(ref, book),
          onResetCover: (book) => _resetCover(ref, book),
          onToggleFavorite: (book) => _toggleFavorite(ref, book),
          onAddToCollection: (book) => _addToCollection(context, book),
          onRenameBook: (book) => _renameBook(context, ref, book),
          onShowAllBooks: () => ref
              .read(selectedCollectionProvider.notifier)
              .select(const AllBooks()),
        );

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                LibrarySidebar(
                  selected: selection,
                  onSelect: (s) =>
                      ref.read(selectedCollectionProvider.notifier).select(s),
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
            selectedIndex: _bottomNavIndexFor(selection),
            onDestinationSelected: (index) =>
                _onBottomNavSelected(context, ref, index),
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
              NavigationDestination(
                icon: Icon(Icons.folder_rounded),
                label: 'Collections',
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
    required this.isLibraryEmpty,
    required this.selection,
    required this.headingLabel,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onOpenBook,
    required this.onOpenPdf,
    required this.onDeleteBook,
    required this.onRemoveBook,
    required this.onChangeCover,
    required this.onResetCover,
    required this.onToggleFavorite,
    required this.onAddToCollection,
    required this.onRenameBook,
    required this.onShowAllBooks,
  });

  /// Already filtered down to [selection] (see `filterBooksForSelection`).
  final List<Book> books;

  /// Whether the *unfiltered* library has zero books — distinguishes a
  /// genuinely empty library ([_EmptyLibraryView]) from a non-empty library
  /// whose current view just has no matches ([_EmptyFilterView]).
  final bool isLibraryEmpty;
  final LibrarySelection selection;
  final String headingLabel;

  /// Current list/grid display density — see [LibraryViewMode]. Read here
  /// (rather than watched via Riverpod directly) so this remains a plain
  /// [StatelessWidget], matching how every other display input already
  /// flows in from `LibraryScreen`.
  final LibraryViewMode viewMode;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
  final ValueChanged<Book> onOpenBook;
  final VoidCallback onOpenPdf;
  final ValueChanged<Book> onDeleteBook;
  final ValueChanged<Book> onRemoveBook;
  final ValueChanged<Book> onChangeCover;
  final ValueChanged<Book> onResetCover;
  final ValueChanged<Book> onToggleFavorite;
  final ValueChanged<Book> onAddToCollection;
  final ValueChanged<Book> onRenameBook;
  final VoidCallback onShowAllBooks;

  @override
  Widget build(BuildContext context) {
    if (isLibraryEmpty) {
      return _EmptyLibraryView(onOpenPdf: onOpenPdf);
    }
    if (books.isEmpty) {
      return _EmptyFilterView(
        selection: selection,
        onShowAllBooks: onShowAllBooks,
      );
    }

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _DriveSyncBanner()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headingLabel,
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
                const SizedBox(width: 12),
                ViewModeControl(mode: viewMode, onChanged: onViewModeChanged),
              ],
            ),
          ),
        ),
        if (viewMode == LibraryViewMode.list)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final book = books[index];
                  return BookListTile(
                    book: book,
                    onOpen: () => onOpenBook(book),
                    onDelete: book.isDriveBook
                        ? () => onDeleteBook(book)
                        : null,
                    onRemove: book.driveFileId == null
                        ? () => onRemoveBook(book)
                        : null,
                    onChangeCover: () => onChangeCover(book),
                    onResetCover: book.hasLiveSource
                        ? () => onResetCover(book)
                        : null,
                    onToggleFavorite: () => onToggleFavorite(book),
                    onAddToCollection: () => onAddToCollection(book),
                    onRename: () => onRenameBook(book),
                  );
                },
                childCount: books.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            sliver: SliverGrid(
              gridDelegate: _gridDelegateFor(viewMode),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final book = books[index];
                  return BookCard(
                    book: book,
                    onOpen: () => onOpenBook(book),
                    onDelete: book.isDriveBook
                        ? () => onDeleteBook(book)
                        : null,
                    onRemove: book.driveFileId == null
                        ? () => onRemoveBook(book)
                        : null,
                    onChangeCover: () => onChangeCover(book),
                    onResetCover: book.hasLiveSource
                        ? () => onResetCover(book)
                        : null,
                    onToggleFavorite: () => onToggleFavorite(book),
                    onAddToCollection: () => onAddToCollection(book),
                    onRename: () => onRenameBook(book),
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

/// Maps a grid [LibraryViewMode] to its tile size/spacing. [maxCrossAxisExtent]
/// is the per-tile cap [SliverGridDelegateWithMaxCrossAxisExtent] fits as many
/// columns of as will cleanly divide the available width — unlike the
/// previous fixed-column-count delegate, this needs no separate
/// desktop/mobile breakpoint math to look right at any width.
/// [LibraryViewMode.gridMedium]'s 230/20/0.62 reproduces the pre-Phase-4
/// default grid's look (previously a fixed 3-6 column desktop / 2-3 column
/// mobile count anchored to the same ~230px tile width).
SliverGridDelegateWithMaxCrossAxisExtent _gridDelegateFor(
  LibraryViewMode mode,
) {
  final (maxExtent, spacing, aspectRatio) = switch (mode) {
    LibraryViewMode.gridSmall => (160.0, 14.0, 0.6),
    LibraryViewMode.gridMedium => (230.0, 20.0, 0.62),
    LibraryViewMode.gridLarge => (320.0, 24.0, 0.66),
    // Unreachable: this helper is only called from the grid branch above,
    // never when `viewMode` is `list` — kept here only so the switch stays
    // exhaustive over every `LibraryViewMode` variant.
    LibraryViewMode.list => (230.0, 20.0, 0.62),
  };
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxExtent,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
    childAspectRatio: aspectRatio,
  );
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

/// Shown when the *unfiltered* library has books, but the currently
/// selected view (Favorites/Recent/a custom collection) has no matches —
/// distinct from [_EmptyLibraryView], which only appears when the library
/// has no books at all regardless of the current view.
class _EmptyFilterView extends StatelessWidget {
  const _EmptyFilterView({required this.selection, required this.onShowAllBooks});

  final LibrarySelection selection;
  final VoidCallback onShowAllBooks;

  (IconData, String, String) get _copy => switch (selection) {
    // Unreachable in practice: an empty [AllBooks] filter is exactly
    // [isLibraryEmpty], which `_LibraryContent` already routes to
    // [_EmptyLibraryView] instead — kept here only so the switch stays
    // exhaustive over every `LibrarySelection` variant.
    AllBooks() => (
      Icons.auto_stories_outlined,
      'Your library is empty',
      'Open a PDF from your device to get started.',
    ),
    Favorites() => (
      Icons.favorite_border_rounded,
      'No favorites yet',
      'Tap the heart on a book, or use its ⋮ menu, to add it here.',
    ),
    Recent() => (
      Icons.history_rounded,
      'Nothing recent',
      'Books you open will show up here, most recent first.',
    ),
    Custom() => (
      Icons.folder_open_rounded,
      'This collection is empty',
      'Add books to it from any book card\'s ⋮ menu.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = _copy;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onShowAllBooks,
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text('View All Books'),
            ),
          ],
        ),
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
