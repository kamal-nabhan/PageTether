import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';

/// Local persistence for the library's book metadata.
///
/// Backed by [SharedPreferences] as the interim local store for Phase 1.1
/// (a proper database arrives in a later sync phase — this is intentionally
/// simple). Everything lives under one JSON object mapping each book's
/// content id (see `pdf_hash.dart`) to its serialized record, so a single
/// key holds the whole library.
class LibraryStore {
  LibraryStore(this._prefs);

  static const _key = 'pt.library.v1';

  final SharedPreferences _prefs;

  /// Loads every persisted book, most-recently-opened first.
  Future<List<Book>> loadAll() async {
    final decoded = _readMap();
    final books = decoded.values
        .map((entry) => Book.fromJson(entry as Map<String, dynamic>))
        .toList();
    books.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return books;
  }

  /// Inserts or updates a single book record in place.
  Future<void> upsert(Book book) async {
    final decoded = _readMap();
    decoded[book.id] = book.toJson();
    await _writeMap(decoded);
  }

  /// Deletes a single book record, mirroring [upsert]. No-op if [id] isn't
  /// present.
  Future<void> remove(String id) async {
    final decoded = _readMap();
    if (decoded.remove(id) == null) return;
    await _writeMap(decoded);
  }

  /// Replaces the entire persisted library with [books].
  Future<void> saveAll(List<Book> books) async {
    await _writeMap({for (final book in books) book.id: book.toJson()});
  }

  Map<String, dynamic> _readMap() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Corrupt/incompatible local data should never crash the app — start
      // fresh instead of throwing.
      return <String, dynamic>{};
    }
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    await _prefs.setString(_key, jsonEncode(map));
  }
}
