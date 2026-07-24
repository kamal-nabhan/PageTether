import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/theme/app_theme.dart';

/// Bottom bar with prev/next controls, a "Page X of Y" indicator, and a
/// jump-to-page field. Listens to [controller] directly (rather than
/// relying on the parent screen's setState) so only this small bar rebuilds
/// as the user scrolls or flips pages.
class PaginationBar extends StatefulWidget {
  const PaginationBar({super.key, required this.controller});

  final PdfViewerController controller;

  @override
  State<PaginationBar> createState() => _PaginationBarState();
}

class _PaginationBarState extends State<PaginationBar> {
  final _pageFieldController = TextEditingController();
  final _pageFieldFocus = FocusNode();

  @override
  void dispose() {
    _pageFieldController.dispose();
    _pageFieldFocus.dispose();
    super.dispose();
  }

  void _goTo(int pageNumber, int pageCount) {
    final clamped = pageNumber.clamp(1, pageCount);
    widget.controller.goToPage(pageNumber: clamped);
  }

  void _submitJump(int pageCount) {
    final value = int.tryParse(_pageFieldController.text);
    if (value != null) {
      _goTo(value, pageCount);
    }
    _pageFieldFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final ready = widget.controller.isReady;
              final pageCount = ready ? widget.controller.pageCount : 0;
              final pageNumber = ready ? (widget.controller.pageNumber ?? 1) : 0;
              final percent = ready && pageCount > 0
                  ? ((pageNumber / pageCount) * 100).round()
                  : null;

              if (!_pageFieldFocus.hasFocus) {
                final text = ready ? '$pageNumber' : '';
                if (_pageFieldController.text != text) {
                  _pageFieldController.text = text;
                }
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: ready && pageNumber > 1
                        ? () => _goTo(pageNumber - 1, pageCount)
                        : null,
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _pageFieldController,
                      focusNode: _pageFieldFocus,
                      enabled: ready,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onSubmitted: (_) => _submitJump(pageCount),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'of ${ready ? pageCount : '-'}${percent != null ? ' • $percent%' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Go to page',
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    onPressed: ready ? () => _submitJump(pageCount) : null,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Next page',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: ready && pageNumber < pageCount
                        ? () => _goTo(pageNumber + 1, pageCount)
                        : null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
