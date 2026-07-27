import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/models/book.dart';
import '../../core/pdf/pdf_source.dart';
import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/auth/auth_state.dart';
import '../../core/services/fullscreen/fullscreen_service.dart';
import '../../core/services/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../library/library_providers.dart';
import '../settings/settings_providers.dart';
import 'pdf_layouts.dart';
import 'widgets/pagination_bar.dart';

/// Renders a single PDF with pdfrx.
///
/// This is the core of Phase 1.1: it opens whatever [PdfSource] the book
/// carries (bundled asset, a file path on desktop/mobile, or raw bytes),
/// resumes to the last-read page, tracks reading progress back into
/// [libraryProvider] as the user pages through, and offers both a
/// scroll/flip layout toggle and a fullscreen/immersive reading mode.
///
/// Also owns this one book's reading-position sync (replacing the old
/// library-wide-push-on-any-change approach): while [Book.id] === the book
/// open here, [_ReaderScreenState] pulls that single Supabase row on open
/// and every 30s (adopting + jumping to it if it's strictly newer — see
/// `LibraryNotifier.mergeRemoteBookAndGetPage`), and pushes that single row
/// after a 4s dwell on whatever page the user stops on (and once more on
/// close). See [_ReaderScreenState._pullAndMaybeJump]/
/// [_ReaderScreenState._pushBookRow]. Entirely quiet on failure and a no-op
/// unless both [SyncCredentials.isConfigured] and
/// [AuthStateSignedIn.canSync] — see [_ReaderScreenState._canSync].
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

  /// How long the reader waits after the *last* page change before pushing
  /// this book's row to Supabase — every forward/backward page change resets
  /// this, so a burst of flipping only pushes once, ~4s after the user
  /// actually settles on a page. See the class doc.
  static const _dwellPushDelay = Duration(seconds: 4);

  /// How often the reader re-pulls this book's row while open, in case
  /// reading continued on another device. See the class doc.
  static const _pullInterval = Duration(seconds: 30);

  Timer? _dwellPushTimer;
  Timer? _pullTimer;

  /// Guards the "on open" pull (see [_onViewerReady]) so it only ever runs
  /// once per reader session, even if pdfrx's `onViewerReady` callback were
  /// ever invoked more than once.
  bool _pulledOnOpen = false;

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
    _dwellPushTimer?.cancel();
    _pullTimer?.cancel();
    // Final push on close — fire-and-forget: `dispose()` can't be async, and
    // `_pushBookRow` itself no-ops quietly if sync isn't configured/signed
    // in, so this is always safe to call unconditionally.
    unawaited(_pushBookRow());
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

    if (_canSync) {
      _dwellPushTimer?.cancel();
      _dwellPushTimer = Timer(_dwellPushDelay, () => unawaited(_pushBookRow()));
    }
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

  /// True only when reading-position sync is actually usable right now: a
  /// Supabase project is configured *and* the user is signed in to Google
  /// with a resolved sync identity — the same gate `SyncNotifier`/
  /// `SyncController` use for the full-library sync. Re-checked on every
  /// call (rather than cached) since either half can change while the
  /// reader is open (e.g. the user signs in from Settings mid-read).
  bool get _canSync {
    final credentials = ref.read(syncCredentialsProvider);
    final auth = ref.read(authProvider);
    return credentials.isConfigured && auth is AuthStateSignedIn && auth.canSync;
  }

  /// Called by pdfrx once the document + controller are actually ready to
  /// interact with (see `PdfViewerParams.onViewerReady`) — this is the
  /// earliest point [_controller.goToPage] is safe to call, so it's also
  /// where the "on open" pull-and-maybe-jump fires and the 30s periodic pull
  /// timer starts (see the class doc).
  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    if (_pulledOnOpen) return;
    _pulledOnOpen = true;
    if (!_canSync) return;
    unawaited(_pullAndMaybeJump());
    _pullTimer = Timer.periodic(_pullInterval, (_) => unawaited(_pullAndMaybeJump()));
  }

  /// Pulls this one book's row from Supabase, merges it in via
  /// `LibraryNotifier.mergeRemoteBookAndGetPage` (last-write-wins — only
  /// adopts a strictly-newer remote row), and jumps the viewer to the
  /// resulting page **only** when that merge actually adopted a different
  /// page than the viewer is currently showing — this is what keeps a
  /// same-page periodic pull from ever causing a jarring no-op "jump".
  /// Quiet on any failure (offline, bad credentials, etc.) — reflected only
  /// via [autoSyncStatusProvider], never surfaced as an error in the reader.
  Future<void> _pullAndMaybeJump() async {
    if (!mounted || !_canSync) return;
    final client = ref.read(supabaseClientProvider);
    final userId = ref.read(authProvider.notifier).syncUserId;
    if (client == null || userId == null) return;
    try {
      final remote = await SyncEngine(client).pullBook(userId, widget.book.id);
      if (remote == null || !mounted) return;
      final newPage = ref
          .read(libraryProvider.notifier)
          .mergeRemoteBookAndGetPage(remote);
      if (newPage == null || newPage < 1 || !_controller.isReady) return;
      final currentPage = _controller.pageNumber;
      if (currentPage != null && currentPage != newPage) {
        await _controller.goToPage(pageNumber: newPage);
      }
      if (mounted) ref.read(autoSyncStatusProvider.notifier).setSynced();
    } catch (e) {
      if (mounted) ref.read(autoSyncStatusProvider.notifier).setFailed('$e');
    }
  }

  /// Pushes this one book's current row (title/author/progress/favorite/
  /// collections/etc. — see `SyncEngine.pushBook`) to Supabase: fired after
  /// a 4s dwell on a page (see [_onControllerChanged]) and once more from
  /// [dispose]. Reads the freshest copy of the book straight from
  /// [libraryProvider] rather than [widget.book] since [_flushProgress] has
  /// almost certainly already landed a newer `currentPage`/`updatedAt` by
  /// the time this fires (400ms debounce vs. this 4s dwell). Quiet on any
  /// failure — see [_pullAndMaybeJump]'s doc.
  Future<void> _pushBookRow() async {
    if (!mounted || !_canSync) return;
    final client = ref.read(supabaseClientProvider);
    final userId = ref.read(authProvider.notifier).syncUserId;
    if (client == null || userId == null) return;
    Book? book;
    for (final b in ref.read(libraryProvider)) {
      if (b.id == widget.book.id) {
        book = b;
        break;
      }
    }
    if (book == null) return;
    try {
      await SyncEngine(client).pushBook(userId, book);
      if (mounted) ref.read(autoSyncStatusProvider.notifier).setSynced();
    } catch (e) {
      if (mounted) ref.read(autoSyncStatusProvider.notifier).setFailed('$e');
    }
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
                            onViewerReady: _onViewerReady,
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
    required this.onViewerReady,
  });

  final PdfSource source;
  final PdfViewerController controller;
  final bool isHorizontal;
  final int initialPageNumber;
  final PdfViewerReadyCallback onViewerReady;

  @override
  Widget build(BuildContext context) {
    final params = PdfViewerParams(
      backgroundColor: AppColors.background,
      margin: 12,
      layoutPages: isHorizontal ? horizontalPdfPageLayout : null,
      onViewerReady: onViewerReady,
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
