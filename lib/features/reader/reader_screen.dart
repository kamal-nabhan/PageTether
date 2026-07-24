import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/models/book.dart';
import '../../core/theme/app_theme.dart';
import 'pdf_layouts.dart';
import 'pdf_source.dart';
import 'widgets/pagination_bar.dart';

/// Renders a single PDF with pdfrx.
///
/// This is the core of Phase 1: it opens whatever [PdfSource] the book
/// carries (a file path on desktop/mobile, raw bytes on web), and offers a
/// scroll/flip layout toggle plus pagination controls. No annotation
/// engine, sync, or cloud storage — purely local rendering.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  bool _isHorizontal = false;
  late final PdfSource? _source = PdfSource.fromBook(widget.book);

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to library',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
        actions: source == null
            ? null
            : [
                IconButton(
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.zoom_out_rounded),
                  onPressed: () => _controller.zoomDown(),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.zoom_in_rounded),
                  onPressed: () => _controller.zoomUp(),
                ),
                IconButton(
                  tooltip: _isHorizontal
                      ? 'Switch to vertical scrolling'
                      : 'Switch to horizontal page flip',
                  icon: Icon(
                    _isHorizontal
                        ? Icons.view_agenda_rounded
                        : Icons.view_carousel_rounded,
                  ),
                  onPressed: () => setState(() => _isHorizontal = !_isHorizontal),
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: source == null
          ? const _NoSourceView()
          : Column(
              children: [
                Expanded(child: _PdfSurface(
                  source: source,
                  controller: _controller,
                  isHorizontal: _isHorizontal,
                )),
                PaginationBar(controller: _controller),
              ],
            ),
    );
  }
}

/// Builds the actual [PdfViewer], branching on whether the source is a
/// filesystem path (desktop/mobile) or in-memory bytes (web).
class _PdfSurface extends StatelessWidget {
  const _PdfSurface({
    required this.source,
    required this.controller,
    required this.isHorizontal,
  });

  final PdfSource source;
  final PdfViewerController controller;
  final bool isHorizontal;

  @override
  Widget build(BuildContext context) {
    final params = PdfViewerParams(
      backgroundColor: AppColors.background,
      margin: 12,
      layoutPages: isHorizontal ? horizontalPdfPageLayout : null,
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => const Center(
        child: CircularProgressIndicator(color: AppColors.accentPurple),
      ),
      errorBannerBuilder: (context, error, stackTrace, documentRef) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not open this PDF.\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ),
    );

    final path = source.path;
    if (path != null) {
      return PdfViewer.file(path, controller: controller, params: params);
    }
    return PdfViewer.data(
      source.bytes!,
      sourceName: source.name,
      controller: controller,
      params: params,
    );
  }
}

class _NoSourceView extends StatelessWidget {
  const _NoSourceView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.picture_as_pdf_outlined,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No PDF source available for this book yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
