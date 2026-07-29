import 'package:flutter/foundation.dart';

/// The "stuff inside" a [GraphNode] — a discriminated union (tagged by a
/// `type` string in JSON) so a text note, a hand-drawn stroke, and an
/// embedded image can all live in [GraphNode.content] without a dozen
/// always-null fields on [GraphNode] itself. A later canvas renderer,
/// Obsidian exporter, or AI summarizer switches on the concrete subtype;
/// anything that only needs to search/embed the node's text instead reads
/// [GraphNode.contentText] and never has to pattern-match this union at all.
sealed class NodeContent {
  const NodeContent();

  Map<String, dynamic> toJson();

  /// Defensive: a missing or unrecognized `type` (e.g. a content variant a
  /// future app version introduced) decodes to [EmptyNodeContent] rather
  /// than throwing — mirrors `Book.fromJson`'s "never crash on bad local
  /// data" stance.
  factory NodeContent.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EmptyNodeContent();
    switch (json['type'] as String?) {
      case 'text':
        return TextNodeContent(text: json['text'] as String? ?? '');
      case 'vector':
        final rawPaths = json['paths'] as List<dynamic>? ?? const [];
        return VectorNodeContent(
          paths: [
            for (final path in rawPaths)
              [
                for (final n in (path as List<dynamic>? ?? const []))
                  (n as num).toDouble(),
              ],
          ],
        );
      case 'image':
        return ImageNodeContent(imageRef: json['imageRef'] as String? ?? '');
      default:
        return const EmptyNodeContent();
    }
  }
}

/// No structured content — the default for kinds whose meaning lives
/// entirely in [GraphNode.anchor]/[GraphNode.contentText] (e.g. a plain
/// [NodeKind.highlight], which is "just" a region + its source text) or for
/// content this build doesn't recognize (see [NodeContent.fromJson]).
class EmptyNodeContent extends NodeContent {
  const EmptyNodeContent();

  @override
  Map<String, dynamic> toJson() => {'type': 'empty'};

  @override
  bool operator ==(Object other) => other is EmptyNodeContent;
  @override
  int get hashCode => (EmptyNodeContent).hashCode;
}

/// A free-standing block of text ([NodeKind.textNote], [NodeKind.aiSummary]).
class TextNodeContent extends NodeContent {
  const TextNodeContent({required this.text});

  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};

  @override
  bool operator ==(Object other) =>
      other is TextNodeContent && other.text == text;
  @override
  int get hashCode => Object.hash(TextNodeContent, text);
}

/// Freehand ink/shape geometry ([NodeKind.ink], [NodeKind.shape]): one entry
/// per stroke, each a flat `[x0, y0, x1, y1, …]` list of board-space points —
/// plain `double`s rather than e.g. `Offset` so this stays JSON-native (no
/// custom point codec needed) all the way through to the `pt_nodes.content`
/// jsonb column.
class VectorNodeContent extends NodeContent {
  const VectorNodeContent({required this.paths});

  final List<List<double>> paths;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'vector',
    'paths': [for (final path in paths) [...path]],
  };

  @override
  bool operator ==(Object other) {
    if (other is! VectorNodeContent) return false;
    if (other.paths.length != paths.length) return false;
    for (var i = 0; i < paths.length; i++) {
      if (!listEquals(other.paths[i], paths[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([for (final path in paths) Object.hashAll(path)]);
}

/// An embedded image's reference ([NodeKind.image]) — a Drive file id, local
/// cache key, or similar opaque string (mirrors `Book.driveFileId`'s
/// "identify, don't embed the bytes" pattern) — never raw image bytes.
class ImageNodeContent extends NodeContent {
  const ImageNodeContent({required this.imageRef});

  final String imageRef;

  @override
  Map<String, dynamic> toJson() => {'type': 'image', 'imageRef': imageRef};

  @override
  bool operator ==(Object other) =>
      other is ImageNodeContent && other.imageRef == imageRef;
  @override
  int get hashCode => Object.hash(ImageNodeContent, imageRef);
}
