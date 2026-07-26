import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_providers.dart';

/// Shows a single-line text-input dialog (used for both "New collection"
/// and "Rename collection") and returns the trimmed name, or null if the
/// user cancelled or submitted blank text.
Future<String?> promptForCollectionName(
  BuildContext context, {
  required String title,
  String? initialValue,
  String confirmLabel = 'Create',
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// "Delete collection?" confirmation, framed non-destructively (mirrors
/// `book_card.dart`'s "Remove from library?" dialog) — deleting a
/// collection only forgets the grouping; the books in it, and any files on
/// disk or Drive, are untouched.
Future<bool> confirmDeleteCollectionDialog(
  BuildContext context,
  String name,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete collection?'),
      content: Text(
        '"$name" will be deleted. The books in it stay in your library — '
        'only the grouping is removed.',
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

/// Deletes collection [id] (see `CollectionsNotifier.delete`) and, if it was
/// the active [selectedCollectionProvider] selection, falls back to
/// [AllBooks] so the grid doesn't keep filtering to a now-nonexistent
/// collection.
void deleteCollectionAndResetSelection(WidgetRef ref, String id) {
  ref.read(collectionsProvider.notifier).delete(id);
  final current = ref.read(selectedCollectionProvider);
  if (current case Custom(collectionId: final selectedId)
      when selectedId == id) {
    ref.read(selectedCollectionProvider.notifier).select(const AllBooks());
  }
}
