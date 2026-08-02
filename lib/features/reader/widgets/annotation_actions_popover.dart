import 'package:flutter/material.dart';

import '../../../core/models/graph/graph_node.dart';
import '../../../core/theme/app_theme.dart';
import '../annotation_geometry.dart';

/// Shows a small contextual popover near [anchor] — the global position of
/// the tap that selected [node] (see `AnnotationTapCallback`'s doc in
/// `annotation_overlay.dart`, sourced from pdfrx's
/// `PdfOverlayInteractionDetails.globalPosition`) — offering the same
/// [kAnnotationColors] swatches used to create an annotation (tap = recolor
/// [node] via [onRecolor]) plus a one-tap [onDelete].
///
/// This replaces the old flow of "tap a highlight → the top toolbar switches
/// into a select mode with delete/recolor" with a menu that appears right
/// where the user tapped, so delete/recolor are one tap from the highlight
/// itself rather than a two-step select-then-act.
///
/// Deliberately a raw [OverlayEntry] rather than [showMenu]: [showMenu]'s
/// [PopupMenuItem]s each resolve to a single tap-to-pop value, which fights a
/// row of independently-tappable color swatches packed into one item. A bare
/// [OverlayEntry] gives full control over that row's taps *and* over
/// dismissal — a full-screen transparent barrier behind the card closes it on
/// any outside tap — and, because it's inserted into the nearest [Overlay]
/// (always present via [MaterialApp]) rather than depending on a [Scaffold]/
/// [AppBar], it works identically whether the reader is in its normal chrome
/// or fullscreen/immersive mode.
void showAnnotationActionsPopover({
  required BuildContext context,
  required Offset anchor,
  required GraphNode node,
  required ValueChanged<int> onRecolor,
  required VoidCallback onDelete,
}) {
  final overlayState = Overlay.of(context);
  final screenSize = MediaQuery.sizeOf(context);
  late final OverlayEntry entry;

  void dismiss() {
    if (entry.mounted) entry.remove();
  }

  final activeColorIndex = kAnnotationColors.indexOf(node.style.color ?? -1);

  // Clamp so the card never renders partly offscreen — a highlight near a
  // page edge would otherwise anchor a popover that spills past the
  // viewport.
  const cardWidth = 208.0;
  const cardHeight = 100.0;
  const edgeMargin = 8.0;
  final left = (anchor.dx - cardWidth / 2).clamp(
    edgeMargin,
    screenSize.width - cardWidth - edgeMargin,
  );
  final top = (anchor.dy + 16).clamp(
    edgeMargin,
    screenSize.height - cardHeight - edgeMargin,
  );

  entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        // Full-screen transparent barrier — any tap outside the card below
        // dismisses the popover.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismiss,
            onSecondaryTap: dismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: AppColors.panel,
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: cardWidth,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < kAnnotationColors.length; i++)
                        _PopoverSwatch(
                          color: Color(kAnnotationColors[i]),
                          selected: i == activeColorIndex,
                          onTap: () {
                            onRecolor(i);
                            dismiss();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Divider(height: 17),
                  InkWell(
                    onTap: () {
                      onDelete();
                      dismiss();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  overlayState.insert(entry);
}

class _PopoverSwatch extends StatelessWidget {
  const _PopoverSwatch({
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
      child: Container(
        width: 26,
        height: 26,
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
