import 'package:flutter/material.dart';

import '../../../core/models/book.dart';
import '../../../core/theme/app_theme.dart';
import 'book_actions_menu.dart';

/// A premium-styled card for a single book on the library dashboard.
///
/// Shows a gradient cover banner, title/author, a progress bar, and a
/// call-to-action button. For a [BookSource.drive] book that hasn't been
/// downloaded to this device yet ([Book.hasLiveSource] is false), that
/// button reads "Download & Read" instead of "Open"/"Continue Reading" —
/// [onOpen] is the same callback either way; `library_screen.dart` decides
/// whether opening it means downloading first. [onDelete], when provided
/// (Drive books only), is reachable both via a long-press (kept for
/// backwards compatibility) and via the "⋮" overflow menu next to the
/// title, both of which show the same confirm dialog before calling back.
/// [onRemove], when provided (local books only — see [Book.driveFileId]),
/// is only reachable via the overflow menu's "Remove from library" item,
/// which shows its own (non-destructive-framed) confirm dialog first.
/// [onChangeCover]/[onResetCover] back the overflow menu's cover-editing
/// actions — see [BookOptionsMenu]. [onToggleFavorite] backs both the heart
/// icon next to the title and the menu's "Add/Remove Favorite" item;
/// [onAddToCollection]/[onRename] each open their own dialog (see
/// `add_to_collection_dialog.dart`/`rename_book_dialog.dart`) and are wired
/// up by the caller (`library_screen.dart`) rather than owned here, keeping
/// this widget itself provider-agnostic like the rest of its callbacks.
class BookCard extends StatelessWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.onOpen,
    this.onDelete,
    this.onRemove,
    this.onChangeCover,
    this.onResetCover,
    this.onToggleFavorite,
    this.onAddToCollection,
    this.onRename,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onRemove;
  final VoidCallback? onChangeCover;
  final VoidCallback? onResetCover;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onRename;

  Future<void> _confirmDelete(BuildContext context) async {
    if (await confirmDeleteDialog(context, book.title)) onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final started = book.isStarted;
    final needsDownload = book.isDriveBook && !book.hasLiveSource;

    return Card(
      child: InkWell(
        onTap: onOpen,
        onLongPress: onDelete == null ? null : () => _confirmDelete(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _CoverBanner(book: book),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: book.title,
                          child: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                      FavoriteToggleButton(
                        isFavorite: book.isFavorite,
                        onToggleFavorite: onToggleFavorite,
                      ),
                      BookOptionsMenu(
                        book: book,
                        onDelete: onDelete,
                        onRemove: onRemove,
                        onChangeCover: onChangeCover,
                        onResetCover: onResetCover,
                        onToggleFavorite: onToggleFavorite,
                        onAddToCollection: onAddToCollection,
                        onRename: onRename,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  BookProgressBar(progress: book.progress),
                  const SizedBox(height: 4),
                  Text(
                    needsDownload
                        ? (book.driveSizeBytes != null
                              ? '${formatBookBytes(book.driveSizeBytes!)} on Google Drive'
                              : 'On Google Drive')
                        : started
                        ? '${book.progressPercent}% • page ${book.currentPage} of ${book.pageCount}'
                        : (book.pageCount > 0 ? '${book.pageCount} pages' : 'Ready to open'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: started
                            ? AppColors.card
                            : AppColors.accentPurple,
                        foregroundColor: AppColors.textPrimary,
                        side: started
                            ? const BorderSide(color: AppColors.border)
                            : BorderSide.none,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: Icon(
                        needsDownload
                            ? Icons.cloud_download_rounded
                            : started
                            ? Icons.play_arrow_rounded
                            : Icons.menu_book_rounded,
                        size: 18,
                      ),
                      label: Text(
                        needsDownload
                            ? 'Download & Read'
                            : started
                            ? 'Continue Reading'
                            : 'Open',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverBanner extends StatelessWidget {
  const _CoverBanner({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final thumbnail = book.coverThumbnail;

    // The title used to also be drawn as an overlay at the bottom of the
    // cover, duplicating the one already shown below it in `BookCard` — the
    // tooltip (hover on desktop/web, long-press on touch) now covers the
    // "see the full title" need that overlay was there for, without the
    // visual repetition.
    return Tooltip(
      message: book.title,
      child: Container(
        decoration: BoxDecoration(gradient: book.coverGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Real page-1 render when available; the gradient behind it (set
            // on the outer Container) is what shows through if rendering
            // failed or hasn't finished yet.
            if (thumbnail != null)
              Positioned.fill(
                child: Image.memory(
                  thumbnail,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: thumbnail != null ? 0.45 : 0.25),
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 12,
              right: 12,
              child: Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.white70,
                size: 20,
              ),
            ),
            if (book.isDriveBook)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_rounded, size: 12, color: Colors.white70),
                      SizedBox(width: 4),
                      Text(
                        'Drive',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

