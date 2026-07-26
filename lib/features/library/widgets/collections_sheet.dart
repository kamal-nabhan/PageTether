import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/collection.dart';
import '../../../core/theme/app_theme.dart';
import '../library_providers.dart';
import 'collection_prompts.dart';

/// Mobile counterpart to the desktop sidebar's collection list (see
/// `library_sidebar.dart`): the bottom nav only has room for the three
/// built-in views, so custom collections live behind this bottom sheet
/// instead, opened via the nav's 4th "Collections" destination (see
/// `library_screen.dart`).
///
/// Tapping a collection selects it (see [selectedCollectionProvider]) and
/// closes the sheet; each row also has a "⋮" menu for Rename/Delete, and a
/// "+ New collection" row creates (and immediately selects) a new one.
class CollectionsSheet extends ConsumerWidget {
  const CollectionsSheet({super.key});

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final name = await promptForCollectionName(
      context,
      title: 'New collection',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    final created = ref.read(collectionsProvider.notifier).create(name);
    if (created == null) return;
    ref.read(selectedCollectionProvider.notifier).select(Custom(created.id));
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _renameCollection(
    BuildContext context,
    WidgetRef ref,
    Collection collection,
  ) async {
    final name = await promptForCollectionName(
      context,
      title: 'Rename collection',
      initialValue: collection.name,
      confirmLabel: 'Rename',
    );
    if (name == null) return;
    ref.read(collectionsProvider.notifier).rename(collection.id, name);
  }

  Future<void> _deleteCollection(
    BuildContext context,
    WidgetRef ref,
    Collection collection,
  ) async {
    if (!await confirmDeleteCollectionDialog(context, collection.name)) return;
    deleteCollectionAndResetSelection(ref, collection.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    final selected = ref.watch(selectedCollectionProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Collections', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (collections.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No collections yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final collection in collections)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: kCoverGradients[collection.colorIndex %
                                kCoverGradients.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(collection.name),
                        selected: selected == Custom(collection.id),
                        selectedColor: AppColors.accentPurple,
                        trailing: PopupMenuButton<_SheetAction>(
                          tooltip: 'Collection options',
                          icon: const Icon(Icons.more_vert_rounded, size: 18),
                          onSelected: (action) {
                            switch (action) {
                              case _SheetAction.rename:
                                _renameCollection(context, ref, collection);
                              case _SheetAction.delete:
                                _deleteCollection(context, ref, collection);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _SheetAction.rename,
                              child: Text('Rename…'),
                            ),
                            PopupMenuItem(
                              value: _SheetAction.delete,
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                        onTap: () {
                          ref
                              .read(selectedCollectionProvider.notifier)
                              .select(Custom(collection.id));
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_rounded),
              title: const Text('New collection'),
              onTap: () => _createCollection(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SheetAction { rename, delete }
