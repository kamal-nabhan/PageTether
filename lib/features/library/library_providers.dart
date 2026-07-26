import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `DetailedApiRequestError` doesn't live under `package:googleapis/common/`
// in this package version (16.x) — it's defined in `_discoveryapis_commons`
// and re-exported from each API's own library, so `drive/v3.dart` (already
// the app's one googleapis import, in `drive_service.dart`) is the correct
// place to pull it from. `show`-only (no prefix) so it can't collide with
// the local `drive` (a `DriveService` instance) variable used below.
import 'package:googleapis/drive/v3.dart' show DetailedApiRequestError;

import '../../core/models/book.dart';
import '../../core/models/collection.dart';
import '../../core/pdf/pdf_document_tools.dart';
import '../../core/pdf/pdf_source.dart';
import '../../core/services/auth/auth_exceptions.dart';
import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/drive/drive_service.dart';
import '../../core/storage/library_store.dart';
import '../../core/storage/pdf_hash.dart';
import '../../core/theme/app_theme.dart';

/// Which set of books the grid is currently filtered to: either one of the
/// three built-in views, or a specific user [Collection]'s id.
///
/// A sealed class (rather than the Phase 1.1 `LibraryCollection` enum it
/// replaces) so [Custom] can carry a collection id — there are arbitrarily
/// many user collections, not a fixed handful. Each variant overrides
/// `==`/`hashCode` for structural equality, so two [Custom] instances for
/// the same collection id compare equal and UI code can safely compare
/// `selected == someValue`.
sealed class LibrarySelection {
  const LibrarySelection();
}

final class AllBooks extends LibrarySelection {
  const AllBooks();
  @override
  bool operator ==(Object other) => other is AllBooks;
  @override
  int get hashCode => (AllBooks).hashCode;
}

final class Favorites extends LibrarySelection {
  const Favorites();
  @override
  bool operator ==(Object other) => other is Favorites;
  @override
  int get hashCode => (Favorites).hashCode;
}

final class Recent extends LibrarySelection {
  const Recent();
  @override
  bool operator ==(Object other) => other is Recent;
  @override
  int get hashCode => (Recent).hashCode;
}

final class Custom extends LibrarySelection {
  const Custom(this.collectionId);
  final String collectionId;
  @override
  bool operator ==(Object other) =>
      other is Custom && other.collectionId == collectionId;
  @override
  int get hashCode => Object.hash(Custom, collectionId);
}

/// Filters [books] down to whatever [selection] represents. [Recent] caps at
/// [recentLimit] and only counts a book as "opened" once its
/// [Book.lastOpenedAt] has actually been bumped past the Phase 1.1
/// (`library_bootstrap.dart`) `DateTime.fromMillisecondsSinceEpoch(0)`
/// sentinel used for the bundled sample book's never-really-opened default.
List<Book> filterBooksForSelection(
  List<Book> books,
  LibrarySelection selection, {
  int recentLimit = 20,
}) {
  switch (selection) {
    case AllBooks():
      return books;
    case Favorites():
      return [for (final b in books) if (b.isFavorite) b];
    case Recent():
      final opened = [
        for (final b in books)
          if (b.lastOpenedAt.millisecondsSinceEpoch > 0) b,
      ]..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      return opened.take(recentLimit).toList();
    case Custom(:final collectionId):
      return [for (final b in books) if (b.collectionIds.contains(collectionId)) b];
  }
}

/// Currently highlighted collection in the sidebar/bottom nav.
///
/// Riverpod 3 moved `StateProvider` to a legacy import and made `state =`
/// protected on plain [Notifier]s, so external widgets can no longer set it
/// directly — call [select] instead.
class SelectedCollectionNotifier extends Notifier<LibrarySelection> {
  @override
  LibrarySelection build() => const AllBooks();

  void select(LibrarySelection selection) => state = selection;
}

final selectedCollectionProvider =
    NotifierProvider<SelectedCollectionNotifier, LibrarySelection>(
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
  /// PDFs into the library, alongside whatever local books are already
  /// there. Safe to call repeatedly (e.g. every time the user reconnects,
  /// hits "Refresh", the app resumes, or — on desktop, where `resumed`
  /// doesn't always fire — the window regains focus; see
  /// `library_screen.dart`).
  ///
  /// **Matches by [Book.driveFileId]**, not [Book.id]: an uploaded book is
  /// keyed by its content hash (see `uploadPickedPdfToDrive`), not
  /// `'drive:<fileId>'`, so matching by id alone would fail to find it here
  /// and add a duplicate entry. A Drive file with no matching local book
  /// (never downloaded to this device) is added fresh, keyed
  /// `'drive:<fileId>'` since its content can't be hashed without
  /// downloading it first.
  ///
  /// **Authoritative for Drive books**: any local book whose [Book.driveFileId]
  /// is no longer in this listing (deleted from Drive directly, or from
  /// another device) is removed from the library too — this is what gives
  /// cross-device deletes eventual consistency, regardless of whether that
  /// book happens to be content-hash-keyed or `'drive:<fileId>'`-keyed.
  /// Pure-local books ([Book.driveFileId] null) are never touched here
  /// regardless of what Drive returns.
  ///
  /// Also rehydrates a live source for any known Drive book that doesn't
  /// have one yet: if this device's disk cache already has a copy (from a
  /// previous download, or from [uploadPickedPdfToDrive] seeding it), its
  /// [Book.filePath] is set to that cached copy so the library shows "Open"
  /// instead of a redundant "Download & Read" — only a genuinely new device
  /// (no local cache) keeps that prompt.
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
      final driveFileIds = {for (final file in files) file.id};

      final byDriveFileId = {
        for (final b in state)
          if (b.driveFileId != null) b.driveFileId!: b,
      };
      final updatedBooks = {for (final b in state) b.id: b};

      for (final file in files) {
        final existing = byDriveFileId[file.id];
        if (existing != null) {
          // Only refresh the Drive-side metadata (name/size) — preserve any
          // locally-cached file path and reading progress we already knew
          // about from a previous session.
          updatedBooks[existing.id] = existing.copyWith(
            title: _titleFromFileName(file.name),
            driveSizeBytes: file.sizeBytes,
          );
        } else {
          final incoming = _driveBookFromMeta(file);
          updatedBooks[incoming.id] = incoming;
        }
      }
      updatedBooks.removeWhere(
        (id, book) =>
            book.driveFileId != null &&
            !driveFileIds.contains(book.driveFileId),
      );

      for (final entry in updatedBooks.entries.toList()) {
        final book = entry.value;
        if (book.driveFileId == null || book.hasLiveSource) continue;
        final cachedPath = await drive.cachedPathForFileId(
          book.driveFileId!,
          book.title,
        );
        if (cachedPath != null) {
          updatedBooks[entry.key] = book.copyWith(filePath: cachedPath);
        }
      }

      state = updatedBooks.values.toList()
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
  ///
  /// The resulting book is keyed by the picked file's **content hash**, not
  /// a `'drive:<fileId>'` id (see [Book.id]) — if this content is already in
  /// the library as a local book, that same entry is upgraded in place
  /// (gaining [BookSource.drive] + [Book.driveFileId]) rather than adding a
  /// second card for the same PDF. Either way the local disk cache is also
  /// seeded with the picked bytes (see [DriveService.seedCache]), so
  /// reopening this book on this device never re-downloads it from Drive.
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
    final contentId = contentIdForBytes(bytes);

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
      // `file_picker` returns a non-null (but unusable) `path` on web, so
      // the upload-by-path-vs-bytes choice must key off `kIsWeb`, not
      // nullness of `path` alone — otherwise web hits "Uploading by file
      // path is not supported on web".
      final useBytes = kIsWeb || path == null;
      final meta = await drive.uploadPdf(
        folderId: folderId,
        name: file.name,
        filePath: useBytes ? null : path,
        bytes: useBytes ? bytes : null,
        onProgress: progressNotifier.set,
      );

      final pageCount = await readPdfPageCount(
        PdfSource.data(bytes, name: file.name),
      );

      final existingIndex = state.indexWhere((b) => b.id == contentId);
      final Book book;
      if (existingIndex != -1) {
        // Already in the library as a local (or previously-uploaded) book —
        // upgrade that entry in place instead of creating a duplicate card.
        final existing = state[existingIndex];
        book = existing.copyWith(
          pageCount: pageCount > 0 ? pageCount : existing.pageCount,
          filePath: path,
          fileBytes: bytes,
          lastOpenedAt: DateTime.now(),
          source: BookSource.drive,
          driveFileId: meta.id,
          driveSizeBytes: meta.sizeBytes,
        );
      } else {
        book = Book(
          id: contentId,
          title: _titleFromFileName(file.name),
          author: 'Google Drive',
          pageCount: pageCount,
          currentPage: 1,
          coverGradientIndex: state.length % kCoverGradients.length,
          filePath: path,
          fileBytes: bytes,
          lastOpenedAt: DateTime.now(),
          source: BookSource.drive,
          driveFileId: meta.id,
          driveSizeBytes: meta.sizeBytes,
        );
      }

      state = [book, for (final b in state) if (b.id != book.id) b];
      unawaited(_store.upsert(book));
      unawaited(_ensureThumbnail(book));
      // Seed the fileId-keyed disk cache with what we just uploaded so a
      // later open on this device (even after a fresh install/library-store
      // reset that lost `book.filePath`) is a cache hit, not a re-download.
      // No-op on web (no on-disk cache there — see `drive_cache_stub.dart`).
      unawaited(drive.seedCache(meta.id, book.title, bytes));
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
  ///
  /// Deliberately does **not** re-key a `'drive:<fileId>'` book to its
  /// content hash after downloading (which would let a later local re-pick
  /// of the same PDF dedupe against it, mirroring `uploadPickedPdfToDrive`):
  /// on non-web platforms the downloaded [PdfSource] only carries a
  /// `filePath`, not `bytes`, so hashing it here would mean reading the
  /// whole file back off disk into memory purely to compute an id — an
  /// extra cost for every download with no benefit unless that same file is
  /// later also opened locally. Left as future work rather than done
  /// unconditionally.
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

  /// Removes a purely local book (see [Book.driveFileId]) from the library
  /// and its persisted record. Non-destructive: unlike [deleteDriveBook],
  /// this never touches Google Drive — it only forgets this device's
  /// library entry (and, with it, the book's reading progress). No-op if
  /// [bookId] isn't in the library.
  void removeFromLibrary(String bookId) {
    if (!state.any((b) => b.id == bookId)) return;
    state = [for (final b in state) if (b.id != bookId) b];
    unawaited(_store.remove(bookId));
  }

  /// Flips [bookId]'s [Book.isFavorite] flag and persists it. No-op if
  /// [bookId] isn't in the library.
  void toggleFavorite(String bookId) {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;
    final updated = state[index].copyWith(isFavorite: !state[index].isFavorite);
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Adds [bookId] to [collectionId]'s membership set and persists it.
  /// No-op if [bookId] isn't in the library or is already a member.
  void addToCollection(String bookId, String collectionId) {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;
    final existing = state[index];
    if (existing.collectionIds.contains(collectionId)) return;
    final updated = existing.copyWith(
      collectionIds: {...existing.collectionIds, collectionId},
    );
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Removes [bookId] from [collectionId]'s membership set and persists it.
  /// No-op if [bookId] isn't in the library or wasn't a member.
  void removeFromCollection(String bookId, String collectionId) {
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;
    final existing = state[index];
    if (!existing.collectionIds.contains(collectionId)) return;
    final updated = existing.copyWith(
      collectionIds: {...existing.collectionIds}..remove(collectionId),
    );
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
  }

  /// Scrubs [collectionId] from every book that references it. Called when
  /// the collection itself is deleted (see `CollectionsNotifier.delete`) so
  /// no book is left pointing at a now-nonexistent collection id.
  void removeCollectionFromAllBooks(String collectionId) {
    final toUpdate = [
      for (final b in state)
        if (b.collectionIds.contains(collectionId))
          b.copyWith(collectionIds: {...b.collectionIds}..remove(collectionId)),
    ];
    if (toUpdate.isEmpty) return;
    final byId = {for (final b in toUpdate) b.id: b};
    state = [for (final b in state) byId[b.id] ?? b];
    for (final b in toUpdate) {
      unawaited(_store.upsert(b));
    }
  }

  /// Renames [bookId]'s [Book.title] and/or [Book.author] and persists it.
  /// Either argument left null keeps that field unchanged; both null is a
  /// no-op. Also a no-op if [bookId] isn't in the library.
  void renameBook(String bookId, {String? title, String? author}) {
    if (title == null && author == null) return;
    final index = state.indexWhere((b) => b.id == bookId);
    if (index == -1) return;
    final updated = state[index].copyWith(title: title, author: author);
    state = [for (final b in state) if (b.id == bookId) updated else b];
    unawaited(_store.upsert(updated));
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

/// Holds the user's custom [Collection]s (distinct from the built-in
/// All Books/Favorites/Recent views — see [LibrarySelection]). Loaded once
/// in `main()` before `runApp`, mirroring how [LibraryNotifier] is seeded
/// with [loadInitialLibrary]'s result.
class CollectionsNotifier extends Notifier<List<Collection>> {
  CollectionsNotifier([this._initialCollections = const []]);

  final List<Collection> _initialCollections;

  @override
  List<Collection> build() => _initialCollections;

  LibraryStore get _store => ref.read(libraryStoreProvider);

  /// Creates and persists a new collection named [name] (trimmed). Returns
  /// null (no-op) if [name] is blank after trimming.
  Collection? create(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final collection = Collection(
      id: generateCollectionId(),
      name: trimmed,
      colorIndex: state.length % kCoverGradients.length,
    );
    state = [...state, collection];
    unawaited(_store.saveCollections(state));
    return collection;
  }

  /// Renames collection [id] to [name] (trimmed). No-op if [name] is blank
  /// after trimming or [id] isn't a known collection.
  void rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = state.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final updated = state[index].copyWith(name: trimmed);
    state = [for (final c in state) if (c.id == id) updated else c];
    unawaited(_store.saveCollections(state));
  }

  /// Deletes collection [id] and scrubs it from every book's membership
  /// (see [LibraryNotifier.removeCollectionFromAllBooks]), so no book keeps
  /// pointing at a now-nonexistent collection. No-op if [id] isn't known.
  void delete(String id) {
    if (!state.any((c) => c.id == id)) return;
    state = [for (final c in state) if (c.id != id) c];
    unawaited(_store.saveCollections(state));
    ref.read(libraryProvider.notifier).removeCollectionFromAllBooks(id);
  }
}

final collectionsProvider =
    NotifierProvider<CollectionsNotifier, List<Collection>>(
      CollectionsNotifier.new,
    );
