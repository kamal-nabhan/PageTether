import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/book.dart';
import '../library_providers.dart';

/// Opens the "Add to collection…" dialog for [book]: every collection shown
/// as a toggle-able checkbox reflecting live membership, plus an inline
/// field to create a new collection (which also adds [book] to it
/// immediately). Reachable from [BookCard]'s "⋮" overflow menu.
Future<void> showAddToCollectionDialog(
  BuildContext context,
  Book book,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _AddToCollectionDialog(bookId: book.id),
  );
}

class _AddToCollectionDialog extends ConsumerStatefulWidget {
  const _AddToCollectionDialog({required this.bookId});

  final String bookId;

  @override
  ConsumerState<_AddToCollectionDialog> createState() =>
      _AddToCollectionDialogState();
}

class _AddToCollectionDialogState
    extends ConsumerState<_AddToCollectionDialog> {
  final _newNameController = TextEditingController();

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  void _createAndAdd() {
    final created = ref
        .read(collectionsProvider.notifier)
        .create(_newNameController.text);
    if (created == null) return;
    ref.read(libraryProvider.notifier).addToCollection(widget.bookId, created.id);
    _newNameController.clear();
  }

  Book? _findBook() {
    for (final b in ref.watch(libraryProvider)) {
      if (b.id == widget.bookId) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider);
    final book = _findBook();

    // The book could theoretically vanish from the library while this
    // dialog is open (e.g. a Drive delete completing elsewhere) — close
    // rather than crash on a null lookup.
    if (book == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    return AlertDialog(
      title: const Text('Add to collection'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (collections.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No collections yet — create one below.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final collection in collections)
                      CheckboxListTile(
                        value: book.collectionIds.contains(collection.id),
                        title: Text(collection.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (checked) {
                          final notifier = ref.read(libraryProvider.notifier);
                          if (checked == true) {
                            notifier.addToCollection(
                              widget.bookId,
                              collection.id,
                            );
                          } else {
                            notifier.removeFromCollection(
                              widget.bookId,
                              collection.id,
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newNameController,
                    decoration: const InputDecoration(
                      hintText: 'New collection name',
                    ),
                    onSubmitted: (_) => setState(_createAndAdd),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Create and add',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => setState(_createAndAdd),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
