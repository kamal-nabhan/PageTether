import 'package:flutter/material.dart';

import '../../../core/models/book.dart';
import 'book_actions_menu.dart';

/// A compact horizontal row for a single book — the library dashboard's
/// List view mode (see `LibraryViewMode.list` in
/// `core/models/library_view_mode.dart`), as an alternative to `BookCard`'s
/// grid tile.
///
/// Shows a small cover thumbnail, then title/author/progress, mirroring
/// `BookCard`'s content but laid out as a row instead of a column. Every
/// action `BookCard` exposes is reachable here too — the ❤ favorite toggle
/// and the ⋮ overflow menu (open/rename/add-to-collection/change-or-reset
/// cover/remove-or-delete) — via the widgets shared out of
/// `book_actions_menu.dart`, so switching view modes never hides an action.
/// [onDelete]/[onRemove]/[onChangeCover]/[onResetCover]/[onToggleFavorite]/
/// [onAddToCollection]/[onRename] all have exactly the same meaning as their
/// `BookCard` counterparts — see that widget's doc comment for the full
/// per-callback rundown.
class BookListTile extends StatelessWidget {
  const BookListTile({
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
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onDelete == null ? null : () => _confirmDelete(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _ListCoverThumb(book: book),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: book.title,
                      child: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    BookProgressBar(progress: book.progress, minHeight: 5),
                    const SizedBox(height: 4),
                    Text(
                      needsDownload
                          ? (book.driveSizeBytes != null
                                ? '${formatBookBytes(book.driveSizeBytes!)} on Google Drive'
                                : 'On Google Drive')
                          : started
                          ? '${book.progressPercent}% • page ${book.currentPage} of ${book.pageCount}'
                          : (book.pageCount > 0
                                ? '${book.pageCount} pages'
                                : 'Ready to open'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
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
        ),
      ),
    );
  }
}

/// Small, badge-free version of `BookCard`'s cover banner — at list-row
/// scale there's no room for the grid tile's "PDF"/"Drive" overlay badges,
/// so this just shows the rendered page-1 thumbnail (or, failing that, the
/// book's gradient with a plain PDF glyph) in a small rounded rect.
class _ListCoverThumb extends StatelessWidget {
  const _ListCoverThumb({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final thumbnail = book.coverThumbnail;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 60,
        decoration: BoxDecoration(gradient: book.coverGradient),
        child: thumbnail != null
            ? Image.memory(
                thumbnail,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const _ListCoverFallbackIcon(),
              )
            : const _ListCoverFallbackIcon(),
      ),
    );
  }
}

class _ListCoverFallbackIcon extends StatelessWidget {
  const _ListCoverFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.picture_as_pdf_rounded,
        color: Colors.white70,
        size: 18,
      ),
    );
  }
}
