import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../annotation_geometry.dart';

/// Which face [AnnotationToolbar] shows: [create] (offered whenever the
/// reader is open) lets the user turn the current text selection into a
/// highlight/underline; [select] replaces it while an existing annotation
/// is tapped (see `_ReaderScreenState._selectedAnnotationId`), offering
/// delete/recolor for that one annotation instead.
enum AnnotationToolbarMode { create, select }

/// The reader's highlight/underline toolbar — a slim bar under the app bar
/// (mirrors `PaginationBar`'s placement/styling at the bottom) with a row of
/// preset color swatches (see [kAnnotationColors]) plus mode-dependent
/// actions. Kept as a single dumb widget driven entirely by callbacks/
/// state from `_ReaderScreenState` — no provider reads of its own — since
/// both "create from selection" and "recolor/delete a selected annotation"
/// are simple, infrequent actions that don't need their own reactive state.
class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    super.key,
    required this.mode,
    required this.selectedColorIndex,
    required this.onColorTap,
    required this.canCreate,
    required this.onHighlight,
    required this.onUnderline,
    required this.onDelete,
    required this.onClose,
  });

  final AnnotationToolbarMode mode;

  /// Index into [kAnnotationColors] — the color a new annotation would use
  /// ([AnnotationToolbarMode.create]) or the color to recolor the selected
  /// annotation to on tap ([AnnotationToolbarMode.select]).
  final int selectedColorIndex;
  final ValueChanged<int> onColorTap;

  /// Whether there's currently a non-empty text selection to turn into an
  /// annotation — disables the Highlight/Underline buttons otherwise.
  final bool canCreate;

  final VoidCallback onHighlight;
  final VoidCallback onUnderline;

  /// Only used in [AnnotationToolbarMode.select].
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isSelect = mode == AnnotationToolbarMode.select;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < kAnnotationColors.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ColorSwatch(
                    color: Color(kAnnotationColors[i]),
                    selected: i == selectedColorIndex,
                    onTap: () => onColorTap(i),
                  ),
                ),
              const Spacer(),
              if (isSelect) ...[
                IconButton(
                  tooltip: 'Delete annotation',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onDelete,
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClose,
                ),
              ] else ...[
                IconButton(
                  tooltip: 'Highlight selected text',
                  icon: const Icon(Icons.border_color_rounded),
                  onPressed: canCreate ? onHighlight : null,
                ),
                IconButton(
                  tooltip: 'Underline selected text',
                  icon: const Icon(Icons.format_underline_rounded),
                  onPressed: canCreate ? onUnderline : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.textPrimary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}
