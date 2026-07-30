import 'dart:math';

/// Generates an opaque, practically-unique id for a new [Board]/[GraphNode]/
/// [GraphEdge] — microsecond timestamp plus a random suffix, prefixed so ids
/// from the three tables are visually distinguishable in logs/debugging.
/// Mirrors `generateCollectionId` (`core/models/collection.dart`): an opaque
/// device-local string, never meaningful on its own, rather than pulling in
/// a dedicated uuid package for what is, at most, a few thousand
/// canvas-local nodes/edges/boards.
String generateGraphId(String prefix) {
  final suffix = Random().nextInt(0x7fffffff);
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$suffix';
}
