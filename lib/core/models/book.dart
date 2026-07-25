import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Where a [Book]'s canonical copy lives.
///
/// [local] books only ever exist on this device (opened via the file
/// picker). [drive] books are backed by a file in the user's "PageTether
/// Library" Drive folder (see `core/services/drive/drive_service.dart`) —
/// they may or may not currently have a live local copy (see
/// [Book.hasLiveSource]); when they don't, the library offers "Download &
/// Read" instead of prompting a re-pick.
enum BookSource { local, drive }

/// A book entry shown on the library dashboard.
///
/// See [id] for how a [BookSource.drive] book is keyed — a content hash and
/// deduplicated with any matching local entry when uploaded from this
/// device, or `'drive:<fileId>'` when only known remotely. Metadata is
/// persisted via [toJson]/[fromJson] (see `core/storage/library_store.dart`);
/// [fileBytes] is deliberately excluded from persistence — it's only ever a
/// transient, in-memory source for the current session (see [openedOnWeb]).
@immutable
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.pageCount,
    required this.currentPage,
    required this.coverGradientIndex,
    required this.lastOpenedAt,
    this.coverThumbnail,
    this.assetPath,
    this.filePath,
    this.fileBytes,
    this.openedOnWeb = false,
    this.source = BookSource.local,
    this.driveFileId,
    this.driveSizeBytes,
  });

  /// Stable content id: sha256 of the PDF's raw bytes, hex-encoded, whenever
  /// the content is known locally — which is always true for
  /// [BookSource.local] books, and also true for a [BookSource.drive] book
  /// that was uploaded *from* this device (see
  /// `LibraryNotifier.uploadPickedPdfToDrive`), so uploading a book that's
  /// already in the library upgrades that same entry in place (adding
  /// [driveFileId]) instead of creating a duplicate. Only a Drive book this
  /// device has never had the bytes for (found via
  /// `LibraryNotifier.hydrateFromDrive`'s listing, not yet downloaded) falls
  /// back to `'drive:<fileId>'` — Drive file ids are already globally
  /// stable/unique, and hashing would require downloading the file first
  /// just to identify it.
  final String id;
  final String title;
  final String author;

  /// True page count, once known. 0 until it has been read from pdfrx.
  final int pageCount;

  /// 1-based last-read page.
  final int currentPage;

  /// Index into [kCoverGradients], used as the fallback cover when
  /// [coverThumbnail] hasn't been rendered (or failed to render).
  final int coverGradientIndex;

  /// PNG bytes of page 1, rendered via pdfrx. Cached in memory and
  /// persisted as base64 so it isn't re-rendered on every app start.
  final Uint8List? coverThumbnail;

  /// Set for the bundled sample book (`assets/sample.pdf`).
  final String? assetPath;

  /// Set on desktop/mobile when the book was opened from a real file path;
  /// lets the library reopen it directly without prompting the user again.
  final String? filePath;

  /// In-memory PDF bytes for the current session only. Populated right
  /// after picking a file (every platform, since the picker is asked for
  /// data) but never persisted across restarts — see [openedOnWeb].
  final Uint8List? fileBytes;

  /// True if this book's only-ever source has been web-picked bytes. Web
  /// browsers can't reopen a local file by path after a page reload, so
  /// once [fileBytes] is gone (a fresh session) [hasLiveSource] goes false
  /// and the library must prompt a re-pick instead of crashing.
  final bool openedOnWeb;

  final DateTime lastOpenedAt;

  /// Where this book's canonical copy lives. See [BookSource].
  final BookSource source;

  /// Set for [BookSource.drive] books: the Drive file id, used for
  /// download/delete calls against the Drive API, and as the match/reconcile
  /// key in `LibraryNotifier.hydrateFromDrive` — deliberately not [id],
  /// which may be a content hash rather than `'drive:<fileId>'` for a book
  /// uploaded from this device (see [id]).
  final String? driveFileId;

  /// Set for [BookSource.drive] books when known: the file size reported by
  /// Drive, purely for display (e.g. "12.4 MB") before it's downloaded.
  final int? driveSizeBytes;

  bool get isDriveBook => source == BookSource.drive;

  LinearGradient get coverGradient =>
      kCoverGradients[coverGradientIndex % kCoverGradients.length];

  /// Reading progress from 0.0 (not started) to 1.0 (finished). Derived
  /// from [currentPage]/[pageCount] rather than stored separately so the
  /// two numbers can never drift apart.
  double get progress {
    if (pageCount <= 0) return 0;
    return (currentPage / pageCount).clamp(0.0, 1.0);
  }

  int get progressPercent => (progress * 100).round();

  bool get isStarted => currentPage > 1;

  /// Whether the reader can open this book right now without prompting the
  /// user to re-pick the file (see [openedOnWeb]).
  bool get hasLiveSource =>
      assetPath != null || filePath != null || fileBytes != null;

  Book copyWith({
    String? title,
    String? author,
    int? pageCount,
    int? currentPage,
    int? coverGradientIndex,
    Uint8List? coverThumbnail,
    String? assetPath,
    String? filePath,
    Uint8List? fileBytes,
    bool? openedOnWeb,
    DateTime? lastOpenedAt,
    BookSource? source,
    String? driveFileId,
    int? driveSizeBytes,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      pageCount: pageCount ?? this.pageCount,
      currentPage: currentPage ?? this.currentPage,
      coverGradientIndex: coverGradientIndex ?? this.coverGradientIndex,
      coverThumbnail: coverThumbnail ?? this.coverThumbnail,
      assetPath: assetPath ?? this.assetPath,
      filePath: filePath ?? this.filePath,
      fileBytes: fileBytes ?? this.fileBytes,
      openedOnWeb: openedOnWeb ?? this.openedOnWeb,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      source: source ?? this.source,
      driveFileId: driveFileId ?? this.driveFileId,
      driveSizeBytes: driveSizeBytes ?? this.driveSizeBytes,
    );
  }

  /// Like [copyWith] but replaces [coverThumbnail] outright — including
  /// clearing it to null — rather than only overriding it when non-null.
  /// [copyWith]'s `newValue ?? this.coverThumbnail` pattern can never
  /// *remove* a cover, which is exactly what "Reset cover" needs to be able
  /// to do if re-rendering from the PDF fails (see
  /// `LibraryNotifier.resetCover`): falling back to the gradient cover
  /// rather than leaving a stale/custom one in place.
  Book withCoverThumbnail(Uint8List? coverThumbnail) {
    return Book(
      id: id,
      title: title,
      author: author,
      pageCount: pageCount,
      currentPage: currentPage,
      coverGradientIndex: coverGradientIndex,
      coverThumbnail: coverThumbnail,
      assetPath: assetPath,
      filePath: filePath,
      fileBytes: fileBytes,
      openedOnWeb: openedOnWeb,
      lastOpenedAt: lastOpenedAt,
      source: source,
      driveFileId: driveFileId,
      driveSizeBytes: driveSizeBytes,
    );
  }

  /// Serializes persistent metadata only. [fileBytes] is intentionally
  /// omitted (large, session-only); [coverThumbnail] is included as base64
  /// so covers survive a restart without re-rendering.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'pageCount': pageCount,
    'currentPage': currentPage,
    'coverGradientIndex': coverGradientIndex,
    'coverThumbnailBase64': coverThumbnail == null
        ? null
        : base64Encode(coverThumbnail!),
    'assetPath': assetPath,
    'filePath': filePath,
    'openedOnWeb': openedOnWeb,
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    'source': source.name,
    'driveFileId': driveFileId,
    'driveSizeBytes': driveSizeBytes,
  };

  factory Book.fromJson(Map<String, dynamic> json) {
    final thumbnailBase64 = json['coverThumbnailBase64'] as String?;
    return Book(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      author: json['author'] as String? ?? '',
      pageCount: json['pageCount'] as int? ?? 0,
      currentPage: json['currentPage'] as int? ?? 1,
      coverGradientIndex: json['coverGradientIndex'] as int? ?? 0,
      coverThumbnail: thumbnailBase64 == null
          ? null
          : base64Decode(thumbnailBase64),
      assetPath: json['assetPath'] as String?,
      filePath: json['filePath'] as String?,
      openedOnWeb: json['openedOnWeb'] as bool? ?? false,
      lastOpenedAt:
          DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: BookSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => BookSource.local,
      ),
      driveFileId: json['driveFileId'] as String?,
      driveSizeBytes: json['driveSizeBytes'] as int?,
    );
  }
}
