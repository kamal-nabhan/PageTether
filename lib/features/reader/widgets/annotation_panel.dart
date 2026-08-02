import 'dart:async';

import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../settings/settings_providers.dart';
import '../annotation_geometry.dart';

/// The reader's collapsible, right-edge annotation panel — replaces the old
/// top [AnnotationToolbar] (see `annotation_toolbar.dart`, since deleted).
///
/// Rendered by `_ReaderScreenState` as a `Positioned` in the reader's
/// `Stack` (right side, vertically centered) rather than inside the reading
/// column, so it floats *over* the PDF and stays available in both normal
/// and immersive/fullscreen mode — the old toolbar lived in the `Column` and
/// was hidden (`if (!_immersive)`) in fullscreen, which was the actual bug
/// this replaces: fullscreen readers had no way to highlight/underline.
///
/// Collapsed, it's just a thin edge handle; expanded, it's a card stacking
/// Highlight/Underline/color/"Sync notes" vertically — a `Column` was chosen
/// deliberately (rather than, say, a `Row` of icons) so a later phase can
/// append more tools (notes, cards, etc.) without needing to redesign the
/// layout to avoid crowding.
///
/// A dumb widget driven entirely by callbacks/state from `_ReaderScreenState`
/// (mirrors the old `AnnotationToolbar`'s stance) — the one exception is the
/// nested [_SyncNotesButton], which does `ref.watch(syncRunProvider)` itself
/// so only that one button rebuilds while a sync is in flight, rather than
/// the whole panel (see `AnnotationOverlay`'s doc for the same isolation
/// pattern applied to graph-node changes).
///
/// Three ways to open it, per this PR's "platform-adaptive open gesture"
/// requirement — all wired without explicit platform branching, since each
/// degrades naturally on platforms where it doesn't apply:
/// - **Hover** (desktop/web): the outer [MouseRegion] expands on
///   `onEnter` and, after a short grace delay (so moving the mouse between
///   the handle and the card's buttons doesn't flicker it shut), collapses
///   on `onExit`. Touch devices never send hover events, so this is a no-op
///   there.
/// - **Tap the handle** (all platforms): toggles expanded/collapsed — the
///   universal affordance, since the handle is always visible.
/// - **Right-click anywhere on the reader** (desktop/web): handled by
///   `_ReaderScreenState` itself (see its class doc) via [onExpandedChanged],
///   since pdfrx's own secondary-tap surface is the whole viewer, not this
///   panel.
class AnnotationPanel extends StatefulWidget {
  const AnnotationPanel({
    super.key,
    required this.expanded,
    required this.onExpandedChanged,
    required this.selectedColorIndex,
    required this.onColorTap,
    required this.canCreate,
    required this.onHighlight,
    required this.onUnderline,
  });

  /// Whether the panel is currently showing its full card. Owned by
  /// `_ReaderScreenState` (not this widget) so a right-click on the reader
  /// surface — which this widget has no visibility into — can force it open
  /// too; see the class doc.
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// Index into [kAnnotationColors] — the color a new annotation will be
  /// created with.
  final int selectedColorIndex;
  final ValueChanged<int> onColorTap;

  /// Whether there's currently a non-empty text selection to turn into an
  /// annotation — disables the Highlight/Underline buttons otherwise.
  final bool canCreate;

  final VoidCallback onHighlight;
  final VoidCallback onUnderline;

  @override
  State<AnnotationPanel> createState() => _AnnotationPanelState();
}

class _AnnotationPanelState extends State<AnnotationPanel> {
  /// How long the pointer can be off the panel before it auto-collapses —
  /// long enough that moving from the handle to a button inside the
  /// just-opened card doesn't clip it shut, short enough that it still reads
  /// as "closes when you're done with it".
  static const _collapseGrace = Duration(milliseconds: 400);

  Timer? _collapseTimer;

  void _cancelCollapseTimer() {
    _collapseTimer?.cancel();
    _collapseTimer = null;
  }

  void _scheduleCollapse() {
    _cancelCollapseTimer();
    _collapseTimer = Timer(_collapseGrace, () {
      if (mounted) widget.onExpandedChanged(false);
    });
  }

  void _handleEnter(PointerEnterEvent _) {
    _cancelCollapseTimer();
    if (!widget.expanded) widget.onExpandedChanged(true);
  }

  void _handleExit(PointerExitEvent _) => _scheduleCollapse();

  void _handleHandleTap() {
    _cancelCollapseTimer();
    widget.onExpandedChanged(!widget.expanded);
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.15, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: widget.expanded
                ? _PanelCard(
                    key: const ValueKey('expanded'),
                    selectedColorIndex: widget.selectedColorIndex,
                    onColorTap: widget.onColorTap,
                    canCreate: widget.canCreate,
                    onHighlight: widget.onHighlight,
                    onUnderline: widget.onUnderline,
                  )
                : const SizedBox.shrink(key: ValueKey('collapsed')),
          ),
          _PanelHandle(expanded: widget.expanded, onTap: _handleHandleTap),
        ],
      ),
    );
  }
}

/// The thin always-visible edge handle — a chevron pill flush with the
/// screen's right edge.
class _PanelHandle extends StatelessWidget {
  const _PanelHandle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
      child: InkWell(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
        onTap: onTap,
        child: Container(
          width: 22,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(10),
            ),
          ),
          child: Icon(
            expanded ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            color: AppColors.textSecondary,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// The expanded card's contents — Highlight/Underline/color/sync, stacked
/// vertically. See [AnnotationPanel]'s doc for why a `Column` rather than a
/// `Row`.
class _PanelCard extends StatelessWidget {
  const _PanelCard({
    super.key,
    required this.selectedColorIndex,
    required this.onColorTap,
    required this.canCreate,
    required this.onHighlight,
    required this.onUnderline,
  });

  final int selectedColorIndex;
  final ValueChanged<int> onColorTap;
  final bool canCreate;
  final VoidCallback onHighlight;
  final VoidCallback onUnderline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      elevation: 6,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
      child: Container(
        // A fixed width, not just `mainAxisSize.min` on the Column below —
        // the reader positions this panel inside a `Center` (see
        // `_ReaderScreenState.build`), which hands its child *loose*
        // constraints up to the full screen width. Without an explicit
        // width here, a full-bleed child like `Divider` (which fills all
        // available width unless told otherwise) would happily claim that
        // entire loose width, ballooning the card out to the screen edge —
        // this fixes the card at a width that comfortably fits its icon
        // buttons/color swatches instead.
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(16),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PanelToolButton(
              tooltip: 'Highlight selected text',
              icon: const Icon(Icons.border_color_rounded),
              onPressed: canCreate ? onHighlight : null,
            ),
            _PanelToolButton(
              tooltip: 'Underline selected text',
              icon: const Icon(Icons.format_underline_rounded),
              onPressed: canCreate ? onUnderline : null,
            ),
            const SizedBox(height: 4),
            _ColorControl(
              selectedIndex: selectedColorIndex,
              onColorTap: onColorTap,
            ),
            const SizedBox(height: 4),
            const Divider(height: 17),
            const _SyncNotesButton(),
          ],
        ),
      ),
    );
  }
}

class _PanelToolButton extends StatelessWidget {
  const _PanelToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed);
  }
}

/// The color control: a single swatch showing the active color that expands
/// (on tap or hover) into the full [kAnnotationColors] set to choose from —
/// deliberately *not* five permanently-visible swatches (the old toolbar's
/// layout), to keep the collapsed card small per [AnnotationPanel]'s "room
/// for more tools" goal.
class _ColorControl extends StatefulWidget {
  const _ColorControl({required this.selectedIndex, required this.onColorTap});

  final int selectedIndex;
  final ValueChanged<int> onColorTap;

  @override
  State<_ColorControl> createState() => _ColorControlState();
}

class _ColorControlState extends State<_ColorControl> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  void _pick(int index) {
    widget.onColorTap(index);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _open = true),
      onExit: (_) => setState(() => _open = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < kAnnotationColors.length; i++)
                    if (i != widget.selectedIndex)
                      _Swatch(
                        color: Color(kAnnotationColors[i]),
                        selected: false,
                        onTap: () => _pick(i),
                      ),
                ],
              ),
            ),
          _Swatch(
            color: Color(kAnnotationColors[widget.selectedIndex]),
            selected: true,
            onTap: _toggle,
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
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
        width: 24,
        height: 24,
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

/// The manual "Sync notes" action (see this PR's sync-model doc): pushes/
/// pulls everything (books, collections, boards, nodes, edges) via
/// [SyncNotifier.syncNow] — the same routine Settings' "Sync now" button
/// uses — so annotations made this session don't have to wait for the
/// close-triggered [SyncNotifier.autoSync] in `_ReaderScreenState.dispose`.
///
/// A small self-contained [ConsumerWidget] rather than plumbing syncing/
/// state through `AnnotationPanel`'s constructor: it watches
/// [syncRunProvider] itself (spinner while [SyncRunInProgress]) and owns its
/// own completion feedback (a brief [SnackBar]), so only this one button
/// rebuilds while a sync runs rather than the whole panel.
class _SyncNotesButton extends ConsumerWidget {
  const _SyncNotesButton();

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(syncRunProvider.notifier).syncNow();
    final result = ref.read(syncRunProvider);
    final message = switch (result) {
      SyncRunSuccess() => 'Notes synced',
      SyncRunError(:final message) => message,
      _ => null,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(syncRunProvider) is SyncRunInProgress;
    return _PanelToolButton(
      tooltip: 'Sync notes',
      icon: syncing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_sync_rounded),
      onPressed: syncing ? null : () => unawaited(_sync(context, ref)),
    );
  }
}
