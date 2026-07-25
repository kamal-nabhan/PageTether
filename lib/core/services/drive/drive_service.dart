import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../pdf/pdf_source.dart';
import 'byte_stream_source.dart';
import 'drive_cache.dart';
import 'upload_source.dart';

const _kLibraryFolderName = 'PageTether Library';
const _kFolderMimeType = 'application/vnd.google-apps.folder';
const _kPdfMimeType = 'application/pdf';

/// A single PDF listed in the "PageTether Library" Drive folder.
///
/// Deliberately a small app-local DTO rather than exposing `googleapis`'
/// `drive.File` all the way up to the UI/provider layer, so the rest of the
/// app doesn't need a `package:googleapis` import just to read a file name.
class DriveBookMeta {
  const DriveBookMeta({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.modifiedTime,
  });

  final String id;
  final String name;
  final int? sizeBytes;
  final DateTime? modifiedTime;
}

/// Wraps `googleapis` drive/v3 for everything PageTether's library needs:
/// finding (or creating) the app's library folder, and
/// uploading/listing/downloading/deleting PDFs within it.
///
/// Holds no session state of its own — construct it fresh with a short-lived
/// authenticated [http.Client] at each call site (see
/// `AuthNotifier.requireAuthClient`, used from `library_providers.dart`).
/// Pure Dart otherwise (no direct `dart:io`/`dart:html`), so this file
/// compiles and runs identically on every platform; the only
/// platform-specific pieces (opening a local file for upload, caching a
/// download) are isolated behind `upload_source.dart` / `drive_cache.dart`.
class DriveService {
  DriveService(http.Client client) : _api = drive.DriveApi(client);

  final drive.DriveApi _api;

  /// Finds the "PageTether Library" folder or creates it if this is the
  /// first time this account has connected. Safe under the least-privilege
  /// `drive.file` scope because a folder this app created is guaranteed to
  /// remain visible to it in later queries.
  Future<String> ensureLibraryFolder() async {
    final existing = await _api.files.list(
      q:
          "name = '$_kLibraryFolderName' and mimeType = '$_kFolderMimeType' "
          'and trashed = false',
      spaces: 'drive',
      $fields: 'files(id,name)',
      pageSize: 1,
    );
    final match = existing.files;
    if (match != null && match.isNotEmpty) {
      return match.first.id!;
    }

    final folder = await _api.files.create(
      drive.File()
        ..name = _kLibraryFolderName
        ..mimeType = _kFolderMimeType,
      $fields: 'id,name,mimeType',
    );
    return folder.id!;
  }

  /// Lists every PDF directly inside [folderId], most-recently-modified
  /// first.
  Future<List<DriveBookMeta>> listPdfs(String folderId) async {
    final result = await _api.files.list(
      q:
          "'$folderId' in parents and mimeType = '$_kPdfMimeType' "
          'and trashed = false',
      spaces: 'drive',
      $fields: 'files(id,name,size,modifiedTime)',
      orderBy: 'modifiedTime desc',
      pageSize: 200,
    );
    return [
      for (final file in result.files ?? const <drive.File>[])
        DriveBookMeta(
          id: file.id!,
          name: file.name ?? 'Untitled.pdf',
          sizeBytes: file.size == null ? null : int.tryParse(file.size!),
          modifiedTime: file.modifiedTime,
        ),
    ];
  }

  /// Uploads a local PDF into [folderId]. Exactly one of [filePath]
  /// (desktop/mobile) or [bytes] (web) must be provided — mirrors
  /// `PdfSource`'s dual-source pattern.
  ///
  /// [onProgress] fires with 0.0-1.0 as bytes are streamed into the upload
  /// request body. This is genuine determinate progress (not simulated): it
  /// reflects how much of the source the HTTP client has actually consumed
  /// so far, which is the best signal available from a single-shot
  /// `files.create` upload (a fully server-acknowledged byte count would
  /// need a resumable-upload session, which is out of scope for this
  /// phase — see the Phase 2 report).
  Future<DriveBookMeta> uploadPdf({
    required String folderId,
    required String name,
    String? filePath,
    Uint8List? bytes,
    void Function(double progress)? onProgress,
  }) async {
    assert(
      (filePath != null) ^ (bytes != null),
      'Provide exactly one of filePath or bytes',
    );

    final source = filePath != null
        ? await openUploadSource(filePath)
        : ByteStreamSource(stream: Stream.value(bytes!), length: bytes.length);

    final media = drive.Media(
      _withProgress(source.stream, source.length, onProgress),
      source.length,
      contentType: _kPdfMimeType,
    );

    final created = await _api.files.create(
      drive.File()
        ..name = name
        ..parents = [folderId],
      uploadMedia: media,
      $fields: 'id,name,size,modifiedTime',
    );

    return DriveBookMeta(
      id: created.id!,
      name: created.name ?? name,
      sizeBytes: created.size == null ? null : int.tryParse(created.size!),
      modifiedTime: created.modifiedTime,
    );
  }

  /// Downloads [fileId] to the local cache (desktop/mobile: a real file;
  /// web: in-memory bytes — see `drive_cache.dart`) and returns a
  /// ready-to-open [PdfSource]. Skips the network entirely if already
  /// cached.
  Future<PdfSource> downloadToCache(
    String fileId,
    String name, {
    void Function(double progress)? onProgress,
  }) {
    return getOrDownloadPdf(
      fileId: fileId,
      name: name,
      onProgress: onProgress,
      fetch: () async {
        final media =
            await _api.files.get(
                  fileId,
                  downloadOptions: drive.DownloadOptions.fullMedia,
                )
                as drive.Media;
        return ByteStreamSource(
          stream: media.stream,
          length: media.length ?? 0,
        );
      },
    );
  }

  /// Deletes [fileId] from Drive entirely (not just trashes it).
  Future<void> deleteFile(String fileId) => _api.files.delete(fileId);

  Stream<List<int>> _withProgress(
    Stream<List<int>> input,
    int total,
    void Function(double progress)? onProgress,
  ) {
    if (onProgress == null || total <= 0) return input;
    var sent = 0;
    return input.map((chunk) {
      sent += chunk.length;
      onProgress(sent / total);
      return chunk;
    });
  }
}
