import 'package:flutter/material.dart';

import '../../../core/models/book.dart';
import '../../../core/theme/app_theme.dart';

/// Shared pieces of a book's per-card actions — the ⋮ overflow menu, the ❤
/// favorite toggle, their confirm dialogs, the progress bar, and the
/// byte-size formatter — used identically by both `BookCard` (grid view, see
/// `book_card.dart`) and `BookListTile` (list view, see
/// `book_list_tile.dart`) so the two layouts can't drift apart on what
/// actions a book supports.

/// "Book options" overflow menu: change or reset the cover thumbnail, and
/// either — depending on [Book.driveFileId] — delete (Drive books) or remove
/// from library (local books). Hidden entirely (renders nothing) when none
/// of its actions could possibly apply, which in practice only happens for a
/// book with no `onChangeCover` callback wired up at all (every call site
/// currently wires one, so this is mostly a defensive fallback).
class BookOptionsMenu extends StatelessWidget {
  const BookOptionsMenu({
    super.key,
    required this.book,
    required this.onDelete,
    required this.onRemove,
    required this.onChangeCover,
    required this.onResetCover,
    required this.onToggleFavorite,
    required this.onAddToCollection,
    required this.onRename,
  });

  final Book book;
  final VoidCallback? onDelete;
  final VoidCallback? onRemove;
  final VoidCallback? onChangeCover;
  final VoidCallback? onResetCover;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    if (onChangeCover == null &&
        onResetCover == null &&
        onDelete == null &&
        onRemove == null &&
        onToggleFavorite == null &&
        onAddToCollection == null &&
        onRename == null) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<_BookMenuAction>(
      tooltip: 'Book options',
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (action) async {
        switch (action) {
          case _BookMenuAction.toggleFavorite:
            onToggleFavorite?.call();
          case _BookMenuAction.rename:
            onRename?.call();
          case _BookMenuAction.addToCollection:
            onAddToCollection?.call();
          case _BookMenuAction.changeCover:
            onChangeCover?.call();
          case _BookMenuAction.resetCover:
            onResetCover?.call();
          case _BookMenuAction.delete:
            if (await confirmDeleteDialog(context, book.title)) {
              onDelete?.call();
            }
          case _BookMenuAction.remove:
            if (await confirmRemoveDialog(context, book.title)) {
              onRemove?.call();
            }
        }
      },
      itemBuilder: (context) => [
        if (onToggleFavorite != null)
          PopupMenuItem(
            value: _BookMenuAction.toggleFavorite,
            child: Text(
              book.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
            ),
          ),
        if (onRename != null)
          const PopupMenuItem(
            value: _BookMenuAction.rename,
            child: Text('Rename…'),
          ),
        if (onAddToCollection != null)
          const PopupMenuItem(
            value: _BookMenuAction.addToCollection,
            child: Text('Add to collection…'),
          ),
        PopupMenuItem(
          value: _BookMenuAction.changeCover,
          enabled: onChangeCover != null,
          child: const Text('Change cover…'),
        ),
        PopupMenuItem(
          value: _BookMenuAction.resetCover,
          enabled: onResetCover != null && book.hasLiveSource,
          child: const Text('Reset cover'),
        ),
        if (onDelete != null)
          const PopupMenuItem(
            value: _BookMenuAction.delete,
            child: Text('Delete'),
          ),
        if (onRemove != null)
          const PopupMenuItem(
            value: _BookMenuAction.remove,
            child: Text('Remove from library'),
          ),
      ],
    );
  }
}

enum _BookMenuAction {
  toggleFavorite,
  rename,
  addToCollection,
  changeCover,
  resetCover,
  delete,
  remove,
}

/// The ❤ favorite toggle shown next to a book's title in both `BookCard` and
/// `BookListTile`. Renders nothing if [onToggleFavorite] is null, mirroring
/// [BookOptionsMenu]'s per-item optionality.
class FavoriteToggleButton extends StatelessWidget {
  const FavoriteToggleButton({
    super.key,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (onToggleFavorite == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
      icon: Icon(
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 18,
        color: isFavorite ? const Color(0xFFEF4444) : AppColors.textSecondary,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      onPressed: onToggleFavorite,
    );
  }
}

/// Shared "Delete from Drive?" confirmation, used both by `BookCard`'s
/// long-press (kept for backwards compatibility) and by [BookOptionsMenu]'s
/// "Delete" item (reachable from either grid or list view).
Future<bool> confirmDeleteDialog(BuildContext context, String title) async {
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
/// [confirmDeleteDialog]'s permanent-Drive-delete warning.
Future<bool> confirmRemoveDialog(BuildContext context, String title) async {
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

/// Thin progress bar shown under a book's title, in both the grid card and
/// the list tile.
class BookProgressBar extends StatelessWidget {
  const BookProgressBar({
    super.key,
    required this.progress,
    this.minHeight = 6,
  });

  final double progress;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0).toDouble(),
        minHeight: minHeight,
        backgroundColor: AppColors.card,
        valueColor: const AlwaysStoppedAnimation(AppColors.accentTeal),
      ),
    );
  }
}

/// Formats a byte count for display (e.g. "12.4 MB") — used for
/// not-yet-downloaded Drive books, which only know their remote size.
String formatBookBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final formatted = unitIndex == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[unitIndex]}';
}
