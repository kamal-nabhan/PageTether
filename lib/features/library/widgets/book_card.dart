import 'package:flutter/material.dart';

import '../../../core/models/book.dart';
import '../../../core/theme/app_theme.dart';

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
/// actions — see `_BookCardMenu`.
class BookCard extends StatelessWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.onOpen,
    this.onDelete,
    this.onRemove,
    this.onChangeCover,
    this.onResetCover,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onRemove;
  final VoidCallback? onChangeCover;
  final VoidCallback? onResetCover;

  Future<void> _confirmDelete(BuildContext context) async {
    if (await _confirmDeleteDialog(context, book.title)) onDelete?.call();
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
                      _BookCardMenu(
                        book: book,
                        onDelete: onDelete,
                        onRemove: onRemove,
                        onChangeCover: onChangeCover,
                        onResetCover: onResetCover,
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
                  _ProgressBar(progress: book.progress),
                  const SizedBox(height: 4),
                  Text(
                    needsDownload
                        ? (book.driveSizeBytes != null
                              ? '${_formatBytes(book.driveSizeBytes!)} on Google Drive'
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

/// "Book options" overflow menu shown next to the title (see [BookCard]):
/// change or reset the cover thumbnail, and either — depending on
/// [Book.driveFileId] — delete (Drive books) or remove from library (local
/// books). Hidden entirely (renders nothing) when none of its actions could
/// possibly apply, which in practice only happens for a book with no
/// [onChangeCover] callback wired up at all (every call site currently wires
/// one, so this is mostly a defensive fallback).
class _BookCardMenu extends StatelessWidget {
  const _BookCardMenu({
    required this.book,
    required this.onDelete,
    required this.onRemove,
    required this.onChangeCover,
    required this.onResetCover,
  });

  final Book book;
  final VoidCallback? onDelete;
  final VoidCallback? onRemove;
  final VoidCallback? onChangeCover;
  final VoidCallback? onResetCover;

  @override
  Widget build(BuildContext context) {
    if (onChangeCover == null &&
        onResetCover == null &&
        onDelete == null &&
        onRemove == null) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<_BookCardAction>(
      tooltip: 'Book options',
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (action) async {
        switch (action) {
          case _BookCardAction.changeCover:
            onChangeCover?.call();
          case _BookCardAction.resetCover:
            onResetCover?.call();
          case _BookCardAction.delete:
            if (await _confirmDeleteDialog(context, book.title)) {
              onDelete?.call();
            }
          case _BookCardAction.remove:
            if (await _confirmRemoveDialog(context, book.title)) {
              onRemove?.call();
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _BookCardAction.changeCover,
          enabled: onChangeCover != null,
          child: const Text('Change cover…'),
        ),
        PopupMenuItem(
          value: _BookCardAction.resetCover,
          enabled: onResetCover != null && book.hasLiveSource,
          child: const Text('Reset cover'),
        ),
        if (onDelete != null)
          const PopupMenuItem(
            value: _BookCardAction.delete,
            child: Text('Delete'),
          ),
        if (onRemove != null)
          const PopupMenuItem(
            value: _BookCardAction.remove,
            child: Text('Remove from library'),
          ),
      ],
    );
  }
}

enum _BookCardAction { changeCover, resetCover, delete, remove }

/// Shared "Delete from Drive?" confirmation, used both by [BookCard]'s
/// long-press (kept for backwards compatibility) and by [_BookCardMenu]'s
/// "Delete" item.
Future<bool> _confirmDeleteDialog(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete from Drive?'),
      content: Text(
        '"$title" will be permanently deleted from Google Drive. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// "Remove from library?" confirmation for local books' "Remove from
/// library" menu item — framed as non-destructive (no file on disk or in
/// Drive is touched, only the library entry and its progress), unlike
/// [_confirmDeleteDialog]'s permanent-Drive-delete warning.
Future<bool> _confirmRemoveDialog(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove from library?'),
      content: Text(
        '"$title" will be removed from your library and its reading '
        'progress forgotten. This does not delete any file from your '
        'device or Google Drive.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0).toDouble(),
        minHeight: 6,
        backgroundColor: AppColors.card,
        valueColor: const AlwaysStoppedAnimation(AppColors.accentTeal),
      ),
    );
  }
}

/// Formats a byte count for display (e.g. "12.4 MB") — used for
/// not-yet-downloaded Drive books, which only know their remote size.
String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final formatted = unitIndex == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$formatted ${units[unitIndex]}';
}
