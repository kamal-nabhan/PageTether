import 'dart:math';

import 'package:flutter/material.dart';

/// A user-defined grouping of books — distinct from the built-in All
/// Books/Favorites/Recent views (see `LibrarySelection` in
/// `library_providers.dart`).
///
/// Membership itself lives on each `Book.collectionIds` rather than here, so
/// adding/removing a single book only ever means editing that one book
/// record; deleting a collection is the one operation that must instead
/// sweep every book (see `LibraryNotifier.removeCollectionFromAllBooks`).
/// Persisted as a flat list via `LibraryStore.loadCollections`/
/// `saveCollections` under `pt.collections.v1`.
@immutable
class Collection {
  const Collection({required this.id, required this.name, this.colorIndex = 0});

  /// Stable, device-generated id — see [generateCollectionId]. Deliberately
  /// never derived from [name] so renaming a collection can never change the
  /// id every book's [collectionIds] refers to.
  final String id;

  final String name;

  /// Index into `kCoverGradients` (the same palette used for book covers),
  /// reused purely so each collection gets a distinct small accent color in
  /// the sidebar/sheet without maintaining a second palette.
  final int colorIndex;

  Collection copyWith({String? name, int? colorIndex}) => Collection(
    id: id,
    name: name ?? this.name,
    colorIndex: colorIndex ?? this.colorIndex,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorIndex': colorIndex,
  };

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled collection',
    colorIndex: json['colorIndex'] as int? ?? 0,
  );
}

/// Generates an opaque, practically-unique id for a new [Collection]:
/// microsecond timestamp plus a random suffix. Mirrors how Drive file ids
/// are treated elsewhere in the app — an opaque string, never meaningful on
/// its own — rather than pulling in a dedicated uuid package for what is, at
/// most, a few dozen device-local collections.
String generateCollectionId() {
  final suffix = Random().nextInt(0x7fffffff);
  return 'col_${DateTime.now().microsecondsSinceEpoch}_$suffix';
}
