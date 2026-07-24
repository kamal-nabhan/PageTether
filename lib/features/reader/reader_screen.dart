import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/models/book.dart';
import '../../core/pdf/pdf_source.dart';
import '../../core/services/fullscreen/fullscreen_service.dart';
import '../../core/theme/app_theme.dart';
import '../library/library_providers.dart';
import 'pdf_layouts.dart';
import 'widgets/pagination_bar.dart';

/// Renders a single PDF with pdfrx.
///
/// This is the core of Phase 1.1: it opens whatever [PdfSource] the book
/// carries (bundled asset, a file path on desktop/mobile, or raw bytes),
/// resumes to the last-read page, tracks reading progress back into
/// [libraryProvider] as the user pages through, and offers both a
/// scroll/flip layout toggle and a fullscreen/immersive reading mode. No
/// annotation engine, sync, or cloud storage — purely local rendering.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controller = PdfViewerController();
  bool _isHorizontal = false;
  bool _immersive = false;
  Timer? _progressDebounce;
  late final PdfSource? _source = PdfSource.fromBook(widget.book);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_progressDebounce?.isActive ?? false) {
      _progressDebounce!.cancel();
      _flushProgress();
    }
    if (_immersive) {
      // Best-effort: never leave the app (or the browser tab) stuck in
      // native fullscreen after navigating away from the reader.
      unawaited(FullscreenService.exit());
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_controller.isReady) return;
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 400), _flushProgress);
  }

  void _flushProgress() {
    if (!_controller.isReady) return;
    final pageNumber = _controller.pageNumber;
    if (pageNumber == null) return;
    ref.read(libraryProvider.notifier).recordProgress(
      widget.book.id,
      currentPage: pageNumber,
      pageCount: _controller.pageCount,
    );
  }

  Future<void> _toggleImmersive() async {
    final next = !_immersive;
    setState(() => _immersive = next);
    if (next) {
      await FullscreenService.enter();
    } else {
      await FullscreenService.exit();
    }
  }

  Future<void> _exitImmersiveIfActive() async {
    if (!_immersive) return;
    await _toggleImmersive();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _exitImmersiveIfActive,
        const SingleActivator(LogicalKeyboardKey.f11): _toggleImmersive,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: _immersive
              ? null
              : AppBar(
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
                          IconButton(
                            tooltip: 'Enter fullscreen (F11)',
                            icon: const Icon(Icons.fullscreen_rounded),
                            onPressed: _toggleImmersive,
                          ),
                          const SizedBox(width: 8),
                        ],
                ),
          body: source == null
              ? const _NoSourceView()
              : Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: _PdfSurface(
                            source: source,
                            controller: _controller,
                            isHorizontal: _isHorizontal,
                            initialPageNumber: widget.book.currentPage < 1
                                ? 1
                                : widget.book.currentPage,
                          ),
                        ),
                        if (!_immersive) PaginationBar(controller: _controller),
                      ],
                    ),
                    if (_immersive)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _ImmersiveExitButton(onPressed: _toggleImmersive),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Builds the actual [PdfViewer], branching on whether the source is the
/// bundled asset, a filesystem path (desktop/mobile), or in-memory bytes
/// (web / current session).
class _PdfSurface extends StatelessWidget {
  const _PdfSurface({
    required this.source,
    required this.controller,
    required this.isHorizontal,
    required this.initialPageNumber,
  });

  final PdfSource source;
  final PdfViewerController controller;
  final bool isHorizontal;
  final int initialPageNumber;

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

    final assetPath = source.assetPath;
    if (assetPath != null) {
      return PdfViewer.asset(
        assetPath,
        controller: controller,
        params: params,
        initialPageNumber: initialPageNumber,
      );
    }
    final path = source.path;
    if (path != null) {
      return PdfViewer.file(
        path,
        controller: controller,
        params: params,
        initialPageNumber: initialPageNumber,
      );
    }
    return PdfViewer.data(
      source.bytes!,
      sourceName: source.name,
      controller: controller,
      params: params,
      initialPageNumber: initialPageNumber,
    );
  }
}

class _ImmersiveExitButton extends StatelessWidget {
  const _ImmersiveExitButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'Exit fullscreen (Esc)',
        icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
        onPressed: onPressed,
      ),
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
