import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/book.dart';
import '../library_providers.dart';

/// Opens a "Rename book" dialog for [book]'s title/author, persisting via
/// [LibraryNotifier.renameBook] if the user confirms. Reachable from
/// [BookCard]'s "⋮" overflow menu.
///
/// A field left blank on save is treated as "leave unchanged" rather than
/// "clear it" — [LibraryNotifier.renameBook] already no-ops a null
/// argument, so this avoids accidentally blanking a title/author the user
/// just didn't mean to touch.
Future<void> showRenameBookDialog(BuildContext context, WidgetRef ref, Book book) async {
  final titleController = TextEditingController(text: book.title);
  final authorController = TextEditingController(text: book.author);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename book'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: authorController,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    final title = titleController.text.trim();
    final author = authorController.text.trim();
    ref
        .read(libraryProvider.notifier)
        .renameBook(
          book.id,
          title: title.isEmpty ? null : title,
          author: author.isEmpty ? null : author,
        );
  }
  titleController.dispose();
  authorController.dispose();
}
