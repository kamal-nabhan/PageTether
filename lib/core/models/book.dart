import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A book entry shown on the library dashboard.
///
/// Phase 1 only ever populates this from local mock/sample data or from a
/// file the user just opened through the file picker — there is no
/// persistence, cloud sync, or metadata extraction yet.
@immutable
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.progress,
    required this.currentPage,
    required this.pageCount,
    required this.coverGradient,
    this.filePath,
    this.fileBytes,
  });

  final String id;
  final String title;
  final String author;

  /// Reading progress from 0.0 (not started) to 1.0 (finished).
  final double progress;
  final int currentPage;
  final int pageCount;

  /// Gradient used to render the mock cover banner on the book card.
  final LinearGradient coverGradient;

  /// Populated on desktop/mobile when the book was opened from a local
  /// file path. Null for pure mock entries and for web-picked files.
  final String? filePath;

  /// Populated on web (or whenever the picker only returns bytes) so the
  /// reader can open the document straight from memory.
  final Uint8List? fileBytes;

  bool get hasSource => filePath != null || fileBytes != null;

  int get progressPercent => (progress * 100).round();
}
