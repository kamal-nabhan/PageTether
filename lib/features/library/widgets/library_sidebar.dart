import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../library_providers.dart';

/// Permanent left sidebar shown on desktop-sized layouts.
///
/// Carries the PageTether brand header, the collection nav (highlight-only
/// in Phase 1) and the primary "Open PDF" action.
class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onOpenPdf,
  });

  final LibraryCollection selected;
  final ValueChanged<LibraryCollection> onSelect;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
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
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: _BrandHeader(),
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
            for (final collection in LibraryCollection.values)
              _NavItem(
                collection: collection,
                selected: collection == selected,
                onTap: () => onSelect(collection),
              ),
            const Spacer(),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Phase 1 • local PDFs only',
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
        Text(
          'PageTether',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.collection,
    required this.selected,
    required this.onTap,
  });

  final LibraryCollection collection;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (collection) {
    LibraryCollection.allBooks => Icons.grid_view_rounded,
    LibraryCollection.favorites => Icons.favorite_rounded,
    LibraryCollection.recent => Icons.history_rounded,
  };

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
                  _icon,
                  size: 19,
                  color: selected ? AppColors.accentPurple : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  collection.label,
                  style: TextStyle(
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
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
