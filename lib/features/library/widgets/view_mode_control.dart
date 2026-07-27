import 'package:flutter/material.dart';

import '../../../core/models/library_view_mode.dart';

/// Popup control for switching the library's view mode (list vs. one of
/// three grid densities — see [LibraryViewMode]). A single compact icon
/// button rather than a width-hungry segmented control so it fits — and is
/// reachable identically — in both the desktop and mobile header layouts,
/// which share the same `_LibraryContent` widget in `library_screen.dart`.
class ViewModeControl extends StatelessWidget {
  const ViewModeControl({super.key, required this.mode, required this.onChanged});

  final LibraryViewMode mode;
  final ValueChanged<LibraryViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibraryViewMode>(
      tooltip: 'Change view',
      icon: Icon(mode.icon),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in LibraryViewMode.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(option.icon, size: 18),
                const SizedBox(width: 12),
                Text(option.label),
                if (option == mode) ...[
                  const Spacer(),
                  const SizedBox(width: 12),
                  const Icon(Icons.check_rounded, size: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
