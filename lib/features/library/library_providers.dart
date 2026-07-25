import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `DetailedApiRequestError` doesn't live under `package:googleapis/common/`
// in this package version (16.x) — it's defined in `_discoveryapis_commons`
// and re-exported from each API's own library, so `drive/v3.dart` (already
// the app's one googleapis import, in `drive_service.dart`) is the correct
// place to pull it from. `show`-only (no prefix) so it can't collide with
// the local `drive` (a `DriveService` instance) variable used below.
import 'package:googleapis/drive/v3.dart' show DetailedApiRequestError;

import '../../core/models/book.dart';
import '../../core/pdf/pdf_document_tools.dart';
import '../../core/pdf/pdf_source.dart';
import '../../core/services/auth/auth_exceptions.dart';
import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/drive/drive_service.dart';
import '../../core/storage/library_store.dart';
import '../../core/storage/pdf_hash.dart';
import '../../core/theme/app_theme.dart';

/// The collections shown in the sidebar (desktop) / bottom nav (mobile).
///
/// Phase 1.1 still treats these as visual/highlight-only filters — there is
/// no favorites/recent tracking yet, so selecting one just changes which
/// nav item is highlighted.
enum LibraryCollection { allBooks, favorites, recent }

extension LibraryCollectionLabel on LibraryCollection {
  String get label => switch (this) {
    LibraryCollection.allBooks => 'All Books',
    LibraryCollection.favorites => 'Favorites',
    LibraryCollection.recent => 'Recent',
  };
}

/// Currently highlighted collection in the sidebar/bottom nav.
///
/// Riverpod 3 moved `StateProvider` to a legacy import and made `state =`
/// protected on plain [Notifier]s, so external widgets can no longer set it
/// directly — call [select] instead.
class SelectedCollectionNotifier extends Notifier<LibraryCollection> {
  @override
  LibraryCollection build() => LibraryCollection.allBooks;

  void select(LibraryCollection collection) => state = collection;
}

final selectedCollectionProvider =
    NotifierProvider<SelectedCollectionNotifier, LibraryCollection>(
      SelectedCollectionNotifier.new,
    );

/// The book the reader screen should currently display.
///
/// Set right before navigating to the reader screen so it can pull the
/// [Book] (and therefore its PDF source) back out via Riverpod instead of
/// threading it through constructor arguments alone.
class SelectedBookNotifier extends Notifier<Book?> {
  @override
  Book? build() => null;

  void select(Book? book) => state = book;
}

final selectedBookProvider = NotifierProvider<SelectedBookNotifier, Book?>(
  SelectedBookNotifier.new,
);

/// The [LibraryStore] singleton. Overridden in `main()` with a real
/// instance backed by an already-initialized [SharedPreferences] — the
/// default here only exists so the provider graph type-checks before that
/// override is applied.
final libraryStoreProvider = Provider<LibraryStore>((ref) {
  throw UnimplementedError(
    'libraryStoreProvider must be overridden in main() with a real LibraryStore',
  );
});

/// Status of the most recent Drive hydrate/upload/download/delete action.
///
/// Kept separate from [libraryProvider]'s book list (rather than, say, a
/// per-book "loading" flag) so the UI can show one banner/spinner for
/// whatever Drive operation is in flight without conflating it with
/// individual book state.
sealed class DriveSyncState {
  const DriveSyncState();
}

class DriveSyncIdle extends DriveSyncState {
  const DriveSyncIdle();
}

class DriveSyncLoading extends DriveSyncState {
  const DriveSyncLoading(this.message);
  final String message;
}

class DriveSyncError extends DriveSyncState {
  const DriveSyncError(this.message);
  final String message;
}

class DriveSyncNotifier extends Notifier<DriveSyncState> {
  @override
  DriveSyncState build() => const DriveSyncIdle();

  void setLoading(String message) => state = DriveSyncLoading(message);
  void setError(String message) => state = DriveSyncError(message);
  void setIdle() => state = const DriveSyncIdle();
}

final driveSyncProvider = NotifierProvider<DriveSyncNotifier, DriveSyncState>(
  DriveSyncNotifier.new,
);

/// 0.0-1.0 while a Drive upload *or* download is streaming; null otherwise.
/// A single global slot shared by both directions — concurrent transfers
/// are out of scope for this phase (see the Phase 2 report's "deferred"
/// notes).
class DriveTransferProgressNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  void set(double? value) => state = value;
}

final driveTransferProgressProvider =
    NotifierProvider<DriveTransferProgressNotifier, double?>(
      DriveTransferProgressNotifier.new,
    );

/// Holds the library's book list: whatever was persisted locally (via
/// [LibraryStore]) plus the bundled sample book, loaded once in `main()`
/// before `runApp` so the very first frame already shows real data — no
/// hardcoded mock entries.
class LibraryNotifier extends Notifier<List<Book>> {
  LibraryNotifier([this._initialBooks = const []]);

  final List<Book> _initialBooks;

  @override
  List<Book> build() => _initialBooks;

  LibraryStore get _store => ref.read(libraryStoreProvider);

  /// Opens the platform file picker restricted to PDFs.
  ///
  /// If the picked file's content hash matches a book already in the
  /// library (e.g. a desktop file that moved, or a web re-pick after a
  /// reload lost its in-memory bytes), the existing entry is refreshed in
  /// place instead of duplicated, so progress carries over. Returns the
  /// resulting [Book], or null if the user cancelled the picker.
  Future<Book?> openLocalPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      // Reading bytes on every platform (not just web) keeps content
      // hashing and cover-thumbnail rendering simple and uniform, at the
      // cost of reading the file into memory once at pick time.
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) return null;
    final String? path = file.path;

    final id = contentIdForBytes(bytes);
    final source = PdfSource.data(bytes, name: file.name);
    final pageCount = await readPdfPageCount(source);

    final existingIndex = state.indexWhere((b) => b.id == id);
    final Book book;
    if (existingIndex != -1) {
      book = state[existingIndex].copyWith(
        pageCount: pageCount > 0 ? pageCount : state[existingIndex].pageCount,
        filePath: path,
        fileBytes: bytes,
        openedOnWeb: path == null,
        lastOpenedAt: DateTime.now(),
      );
    } else {
      book = Book(
        id: id,
        title: _titleFromFileName(file.name),
        author: 'Opened from device',
        pageCount: pageCount,
        currentPage: 1,
        coverGradientIndex: state.length % kCoverGradients.length,
        filePath: path,
        fileBytes: bytes,
        openedOnWeb: path == null,
        lastOpenedAt: DateTime.now(),
      );
    }

    state = [book, for (final b in state) if (b.id != id) b];
    unawaited(_store.upsert(book));
    unawaited(_ensureThumbnail(book));
    return book;
  }

  /// Records reading progress for [bookId] (a content id) and persists it
  /// immediately. No-ops if the book isn't in the library (e.g. it was
  /// removed) or nothing actually changed.
  void recordProgress(
    String bookId, {
    required int currentPage,
    required int pageCount,
  }) {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;

    final existing = state[index];
    final resolvedPageCount = pageCount > 0 ? pageCount : existing.pageCount;
    if (existing.currentPage == currentPage &&
        existing.pageCount == resolvedPageCount) {
      return;
    }

    final updated = existing.copyWith(
      currentPage: currentPage,
      pageCount: resolvedPageCount,
      lastOpenedAt: DateTime.now(),
    );
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Renders and caches the page-1 cover thumbnail for [book] if it doesn't
  /// have one yet. Fire-and-forget: failures just leave the gradient
  /// fallback in place.
  Future<void> _ensureThumbnail(Book book) async {
    if (book.coverThumbnail != null) return;
    final source = PdfSource.fromBook(book);
    if (source == null) return;

    final thumbnail = await renderCoverThumbnail(source);
    if (thumbnail == null) return;

    final index = state.indexWhere((b) => b.id == book.id);
    if (index == -1) return;
    final updated = state[index].copyWith(coverThumbnail: thumbnail);
    state = [for (final b in state) if (b.id == book.id) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Opens the platform image picker, downscales the chosen image to a
  /// ~512px-long-edge thumbnail (see [_thumbnailFromImageBytes] — this
  /// matters on web, where [LibraryStore] is backed by browser local
  /// storage with a ~5MB ceiling and every cover is stored as base64), and
  /// sets it as [bookId]'s cover via [setCustomCover]. No-ops if the user
  /// cancels the picker or the image can't be decoded.
  Future<void> pickAndSetCover(String bookId) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final thumbnail = await _thumbnailFromImageBytes(bytes);
    if (thumbnail == null) return;
    setCustomCover(bookId, thumbnail);
  }

  /// Sets [bookId]'s cover to the given (already-thumbnail-sized) PNG
  /// [bytes] and persists it, mirroring how [_ensureThumbnail] persists a
  /// rendered cover. No-ops if [bookId] isn't in the library.
  void setCustomCover(String bookId, Uint8List bytes) {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;
    final updated = state[index].withCoverThumbnail(bytes);
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Re-renders [bookId]'s cover from page 1 of its PDF, discarding any
  /// custom cover set via [setCustomCover]. Only meaningful when the book
  /// has a live PDF source right now (see [Book.hasLiveSource] — a
  /// not-yet-downloaded Drive book has none); callers should disable the
  /// "Reset cover" action otherwise. Falls back to the gradient cover (by
  /// clearing [Book.coverThumbnail] to null) if rendering fails, rather than
  /// leaving a stale cover in place — unlike [_ensureThumbnail], this is an
  /// explicit user action, so silently doing nothing on failure would look
  /// like a bug rather than a no-op.
  Future<void> resetCover(String bookId) async {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;
    final source = PdfSource.fromBook(state[index]);
    if (source == null) return;

    final thumbnail = await renderCoverThumbnail(source);

    final freshIndex = state.indexWhere((b) => b.id == bookId);
    if (freshIndex == -1) return;
    final updated = state[freshIndex].withCoverThumbnail(thumbnail);
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Decodes [bytes] as an image and re-encodes it as PNG, downscaled so
  /// its longer edge is at most [maxDimension] (a no-larger-than-needed
  /// resize, not an upscale). Returns null (never throws) if the bytes
  /// can't be decoded as an image.
  ///
  /// Uses `dart:ui`'s codec directly rather than pulling in an image
  /// processing package: [ui.instantiateImageCodec]'s `targetWidth`/
  /// `targetHeight` do the actual downsampling during decode, so this is a
  /// single extra (cheap, since it's scoped to one user-picked image)
  /// re-decode rather than a full-resolution decode followed by a separate
  /// resize pass.
  Future<Uint8List?> _thumbnailFromImageBytes(
    Uint8List bytes, {
    int maxDimension = 512,
  }) async {
    try {
      final probeCodec = await ui.instantiateImageCodec(bytes);
      final probeFrame = await probeCodec.getNextFrame();
      final originalWidth = probeFrame.image.width;
      final originalHeight = probeFrame.image.height;
      probeFrame.image.dispose();
      if (originalWidth <= 0 || originalHeight <= 0) return null;

      final longEdge = originalWidth > originalHeight
          ? originalWidth
          : originalHeight;
      final scale = longEdge > maxDimension ? maxDimension / longEdge : 1.0;
      final targetWidth = (originalWidth * scale).round();
      final targetHeight = (originalHeight * scale).round();

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Finds/creates the "PageTether Library" Drive folder and merges its
  /// PDFs into the library as `source: drive` entries, alongside whatever
  /// local books are already there. Safe to call repeatedly (e.g. every
  /// time the user reconnects, hits "Refresh", or the app resumes) —
  /// existing Drive entries are refreshed in place by id (keeping any
  /// locally-cached file path and reading progress) rather than duplicated.
  ///
  /// **Authoritative for Drive books**: any local [BookSource.drive] entry
  /// whose file id is no longer in this listing (deleted from Drive
  /// directly, or from another device) is removed from the library too —
  /// this is what gives cross-device deletes eventual consistency. Local
  /// (non-Drive) books are never touched here regardless of what Drive
  /// returns.
  Future<void> hydrateFromDrive() async {
    final syncNotifier = ref.read(driveSyncProvider.notifier);
    syncNotifier.setLoading('Loading your Drive library…');
    try {
      final client = await ref
          .read(authProvider.notifier)
          .requireAuthClient();
      final drive = DriveService(client);
      final folderId = await drive.ensureLibraryFolder();
      final files = await drive.listPdfs(folderId);
      final driveIds = {for (final file in files) 'drive:${file.id}'};

      final byId = {for (final b in state) b.id: b};
      for (final file in files) {
        final incoming = _driveBookFromMeta(file);
        final existing = byId[incoming.id];
        // Only refresh the Drive-side metadata (name/size) — preserve any
        // locally-cached file path and reading progress we already knew
        // about from a previous session.
        byId[incoming.id] = existing == null
            ? incoming
            : existing.copyWith(
                title: incoming.title,
                driveSizeBytes: incoming.driveSizeBytes,
              );
      }
      byId.removeWhere(
        (id, book) => book.source == BookSource.drive && !driveIds.contains(id),
      );

      state = byId.values.toList()
        ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      unawaited(_store.saveAll(state));
      syncNotifier.setIdle();
    } on DriveAuthUnavailableException catch (e) {
      syncNotifier.setError(e.reason);
    } catch (e) {
      syncNotifier.setError('Could not load your Drive library: $e');
    }
  }

  /// Opens the platform file picker and uploads the chosen PDF into the
  /// Drive library folder, reporting progress via [driveTransferProgressProvider].
  /// Returns the resulting [Book] (already carrying the just-picked bytes,
  /// so it can render/open immediately without a redundant download), or
  /// null if the user cancelled the picker or the upload failed.
  Future<Book?> uploadPickedPdfToDrive() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) return null;
    final String? path = file.path;

    final progressNotifier = ref.read(driveTransferProgressProvider.notifier);
    final syncNotifier = ref.read(driveSyncProvider.notifier);
    progressNotifier.set(0);
    syncNotifier.setLoading('Uploading ${file.name}…');
    try {
      final client = await ref
          .read(authProvider.notifier)
          .requireAuthClient();
      final drive = DriveService(client);
      final folderId = await drive.ensureLibraryFolder();
      final meta = await drive.uploadPdf(
        folderId: folderId,
        name: file.name,
        filePath: path,
        bytes: path == null ? bytes : null,
        onProgress: progressNotifier.set,
      );

      final pageCount = await readPdfPageCount(
        PdfSource.data(bytes, name: file.name),
      );
      final book = _driveBookFromMeta(meta).copyWith(
        pageCount: pageCount,
        filePath: path,
        fileBytes: bytes,
        lastOpenedAt: DateTime.now(),
      );

      state = [book, for (final b in state) if (b.id != book.id) b];
      unawaited(_store.upsert(book));
      unawaited(_ensureThumbnail(book));
      syncNotifier.setIdle();
      return book;
    } on DriveAuthUnavailableException catch (e) {
      syncNotifier.setError(e.reason);
      return null;
    } catch (e) {
      syncNotifier.setError('Upload failed: $e');
      return null;
    } finally {
      progressNotifier.set(null);
    }
  }

  /// Downloads a Drive book's PDF into the local cache (skipping the
  /// network entirely if already cached — see `drive_cache.dart`) and
  /// returns the resulting live [Book] with `filePath`/`fileBytes`
  /// populated, ready to open in the reader. Returns null if [bookId] isn't
  /// a known Drive book or the download failed.
  Future<Book?> downloadDriveBook(String bookId) async {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return null;
    final book = state[index];
    final fileId = book.driveFileId;
    if (fileId == null) return null;

    final syncNotifier = ref.read(driveSyncProvider.notifier);
    progressNotifier.set(0);
    syncNotifier.setLoading('Downloading ${book.title}…');
    try {
      final client = await ref
          .read(authProvider.notifier)
          .requireAuthClient();
      final drive = DriveService(client);
      final source = await drive.downloadToCache(
        fileId,
        book.title,
        onProgress: progressNotifier.set,
      );
      final pageCount = await readPdfPageCount(source);

      final updated = book.copyWith(
        pageCount: pageCount > 0 ? pageCount : book.pageCount,
        filePath: source.path,
        fileBytes: source.bytes,
        lastOpenedAt: DateTime.now(),
      );
      state = [for (final b in state) if (b.id == bookId) updated else b];
      unawaited(_store.upsert(updated));
      unawaited(_ensureThumbnail(updated));
      syncNotifier.setIdle();
      return updated;
    } on DriveAuthUnavailableException catch (e) {
      syncNotifier.setError(e.reason);
      return null;
    } catch (e) {
      syncNotifier.setError('Download failed: $e');
      return null;
    } finally {
      progressNotifier.set(null);
    }
  }

  /// Deletes a Drive book from Drive and removes it from the library.
  /// Returns false (and surfaces the error via [driveSyncProvider]) if
  /// [bookId] isn't a known Drive book or the delete call failed.
  ///
  /// A 404 from `files.delete` (the file is already gone — e.g. deleted from
  /// another device, or a previous attempt that actually succeeded on
  /// Drive's side before this app's local state got a chance to update) is
  /// treated as success rather than a real error: either way, the desired
  /// end state — this book no longer exists in Drive or the local
  /// library — is already true.
  Future<bool> deleteDriveBook(String bookId) async {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return false;
    final book = state[index];
    final fileId = book.driveFileId;
    if (fileId == null) return false;

    final syncNotifier = ref.read(driveSyncProvider.notifier);
    syncNotifier.setLoading('Deleting ${book.title}…');
    try {
      final client = await ref
          .read(authProvider.notifier)
          .requireAuthClient();
      final drive = DriveService(client);
      await drive.deleteFile(fileId);
      state = [for (final b in state) if (b.id != bookId) b];
      unawaited(_store.saveAll(state));
      syncNotifier.setIdle();
      return true;
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        state = [for (final b in state) if (b.id != bookId) b];
        unawaited(_store.saveAll(state));
        syncNotifier.setIdle();
        return true;
      }
      syncNotifier.setError('Delete failed: $e');
      return false;
    } on DriveAuthUnavailableException catch (e) {
      syncNotifier.setError(e.reason);
      return false;
    } catch (e) {
      syncNotifier.setError('Delete failed: $e');
      return false;
    }
  }

  DriveTransferProgressNotifier get progressNotifier =>
      ref.read(driveTransferProgressProvider.notifier);

  Book _driveBookFromMeta(DriveBookMeta file) {
    return Book(
      id: 'drive:${file.id}',
      title: _titleFromFileName(file.name),
      author: 'Google Drive',
      pageCount: 0,
      currentPage: 1,
      coverGradientIndex: file.id.hashCode.abs() % kCoverGradients.length,
      lastOpenedAt:
          file.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      source: BookSource.drive,
      driveFileId: file.id,
      driveSizeBytes: file.sizeBytes,
    );
  }

  static String _titleFromFileName(String fileName) {
    final withoutExtension = fileName.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    return withoutExtension.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<Book>>(
  LibraryNotifier.new,
);
