import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/collection.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/settings_screen.dart';
import '../library_providers.dart';
import 'collection_prompts.dart';
import 'drive_auth_panel.dart';

/// The three built-in nav rows, in display order — paired with their icon
/// and label since (unlike a plain enum) [LibrarySelection]'s variants
/// aren't natively iterable.
const List<(LibrarySelection, IconData, String)> _builtInSelections = [
  (AllBooks(), Icons.grid_view_rounded, 'All Books'),
  (Favorites(), Icons.favorite_rounded, 'Favorites'),
  (Recent(), Icons.history_rounded, 'Recent'),
];

/// Permanent left sidebar shown on desktop-sized layouts.
///
/// Carries the PageTether brand header, the collection nav — the three
/// built-in views plus the user's own [Collection]s, each with Rename/Delete
/// affordances, and a "+ New collection" action — the primary "Open PDF"
/// action, and the Google Drive connect/account panel.
class LibrarySidebar extends ConsumerWidget {
  const LibrarySidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onOpenPdf,
  });

  final LibrarySelection selected;
  final ValueChanged<LibrarySelection> onSelect;
  final VoidCallback onOpenPdf;

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final name = await promptForCollectionName(
      context,
      title: 'New collection',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    final created = ref.read(collectionsProvider.notifier).create(name);
    if (created != null) onSelect(Custom(created.id));
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

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 12, 32),
              child: Row(
                children: [
                  const Expanded(child: _BrandHeader()),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: onOpenPdf,
                icon: const Icon(Icons.file_open_rounded, size: 18),
                label: const Text('Open PDF'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: DriveAuthPanel(),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: DriveUploadButton(),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'COLLECTIONS',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final (selection, icon, label) in _builtInSelections)
                      _NavItem(
                        icon: icon,
                        label: label,
                        selected: selection == selected,
                        onTap: () => onSelect(selection),
                      ),
                    if (collections.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Divider(height: 1),
                      ),
                      for (final collection in collections)
                        _CollectionNavItem(
                          collection: collection,
                          selected:
                              selected == Custom(collection.id),
                          onTap: () => onSelect(Custom(collection.id)),
                          onRename: () =>
                              _renameCollection(context, ref, collection),
                          onDelete: () =>
                              _deleteCollection(context, ref, collection),
                        ),
                    ],
                    _NavItem(
                      icon: Icons.add_rounded,
                      label: 'New collection',
                      selected: false,
                      onTap: () => _createCollection(context, ref),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Phase 3 • collections, favorites & recents',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            'PageTether',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? AppColors.accentPurple.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? AppColors.accentPurple : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A custom-collection row: like [_NavItem] but with a colored dot instead
/// of a fixed icon (see [Collection.colorIndex]) and a trailing "⋮" menu for
/// Rename/Delete.
class _CollectionNavItem extends StatelessWidget {
  const _CollectionNavItem({
    required this.collection,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final Collection collection;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dotGradient = kCoverGradients[collection.colorIndex % kCoverGradients.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? AppColors.accentPurple.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: dotGradient,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                ),
                PopupMenuButton<_CollectionAction>(
                  tooltip: 'Collection options',
                  icon: const Icon(Icons.more_vert_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  onSelected: (action) {
                    switch (action) {
                      case _CollectionAction.rename:
                        onRename();
                      case _CollectionAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _CollectionAction.rename,
                      child: Text('Rename…'),
                    ),
                    PopupMenuItem(
                      value: _CollectionAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _CollectionAction { rename, delete }
