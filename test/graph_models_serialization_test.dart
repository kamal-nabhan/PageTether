// Serialization round-trip tests for the annotation graph model
// (lib/core/models/graph/): Board, GraphNode, GraphEdge, and their value
// types (NodeAnchor, NodeRegion, NodeContent, GraphStyle). Pure logic, no
// device/network — mirrors test/models_serialization_test.dart's coverage
// of Book/Collection.
import 'package:flutter_test/flutter_test.dart';
import 'package:pagetether/core/models/graph/board.dart';
import 'package:pagetether/core/models/graph/graph_edge.dart';
import 'package:pagetether/core/models/graph/graph_node.dart';
import 'package:pagetether/core/models/graph/graph_style.dart';
import 'package:pagetether/core/models/graph/node_anchor.dart';
import 'package:pagetether/core/models/graph/node_content.dart';
import 'package:pagetether/core/models/graph/node_kind.dart';
import 'package:pagetether/core/models/graph/node_region.dart';

void main() {
  group('GraphStyle.toJson/fromJson', () {
    test('round-trips every field', () {
      const style = GraphStyle(
        color: 0xFF112233,
        opacity: 0.5,
        strokeWidth: 3.5,
        fill: 0xFF445566,
        extra: {'dash': 'dotted'},
      );
      final decoded = GraphStyle.fromJson(style.toJson());

      expect(decoded, style);
    });

    test('fromJson(null) yields GraphStyle.empty', () {
      expect(GraphStyle.fromJson(null), GraphStyle.empty);
    });

    test('fromJson defaults missing numeric fields', () {
      final decoded = GraphStyle.fromJson({});
      expect(decoded.color, isNull);
      expect(decoded.opacity, 1.0);
      expect(decoded.strokeWidth, 1.0);
      expect(decoded.fill, isNull);
      expect(decoded.extra, isEmpty);
    });
  });

  group('NodeContent.toJson/fromJson', () {
    test('TextNodeContent round-trips', () {
      const content = TextNodeContent(text: 'hello world');
      final decoded = NodeContent.fromJson(content.toJson());
      expect(decoded, content);
    });

    test('VectorNodeContent round-trips multiple strokes', () {
      const content = VectorNodeContent(
        paths: [
          [0, 0, 1, 1, 2, 2],
          [5, 5, 6, 6],
        ],
      );
      final decoded = NodeContent.fromJson(content.toJson());
      expect(decoded, content);
    });

    test('ImageNodeContent round-trips', () {
      const content = ImageNodeContent(imageRef: 'drive:abc123');
      final decoded = NodeContent.fromJson(content.toJson());
      expect(decoded, content);
    });

    test('fromJson(null) yields EmptyNodeContent', () {
      expect(NodeContent.fromJson(null), const EmptyNodeContent());
    });

    test('fromJson defaults to EmptyNodeContent for an unrecognized type', () {
      final decoded = NodeContent.fromJson({'type': 'some-future-kind'});
      expect(decoded, const EmptyNodeContent());
    });
  });

  group('NodeRegion.toJson/fromJson', () {
    test('NormalizedRectRegion round-trips', () {
      const region = NormalizedRectRegion(
        NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
      );
      final decoded = NodeRegion.fromJson(region.toJson());
      expect(decoded, region);
    });

    test('TextQuadsRegion round-trips multiple quads', () {
      const region = TextQuadsRegion([
        NormalizedRect(x: 0.0, y: 0.1, w: 0.5, h: 0.05),
        NormalizedRect(x: 0.0, y: 0.16, w: 0.3, h: 0.05),
      ]);
      final decoded = NodeRegion.fromJson(region.toJson());
      expect(decoded, region);
    });

    test('fromJson(null) falls back to a zero-sized NormalizedRectRegion', () {
      expect(
        NodeRegion.fromJson(null),
        const NormalizedRectRegion(NormalizedRect.zero),
      );
    });

    test('fromJson defaults to a zero rect for an unrecognized type', () {
      final decoded = NodeRegion.fromJson({'type': 'future-region-shape'});
      expect(decoded, const NormalizedRectRegion(NormalizedRect.zero));
    });
  });

  group('NodeAnchor.toJson/fromJson', () {
    test('round-trips every field', () {
      const anchor = NodeAnchor(
        bookId: 'book-1',
        page: 42,
        region: NormalizedRectRegion(
          NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.05),
        ),
        sourceText: 'the quoted passage',
      );
      final decoded = NodeAnchor.fromJson(anchor.toJson());
      expect(decoded, anchor);
    });

    test('round-trips with no region/sourceText', () {
      const anchor = NodeAnchor(bookId: 'book-1', page: 1);
      final decoded = NodeAnchor.fromJson(anchor.toJson());
      expect(decoded, anchor);
    });

    test('fromJson(null) yields null', () {
      expect(NodeAnchor.fromJson(null), isNull);
    });

    test('fromJson yields null when bookId is missing', () {
      expect(NodeAnchor.fromJson({'page': 5}), isNull);
    });
  });

  group('GraphNode.toJson/fromJson', () {
    test('round-trips every field', () {
      final node = GraphNode(
        id: 'node-1',
        boardId: 'board-1',
        kind: NodeKind.highlight,
        x: 10,
        y: 20,
        w: 100,
        h: 30,
        rotation: 0.5,
        z: 2,
        style: const GraphStyle(color: 0xFFAABBCC, opacity: 0.8),
        content: const TextNodeContent(text: 'note body'),
        anchor: const NodeAnchor(
          bookId: 'book-1',
          page: 7,
          sourceText: 'source passage',
        ),
        contentText: 'source passage',
        badge: 'TODO',
        deleted: false,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
      );

      final decoded = GraphNode.fromJson(node.toJson());

      expect(decoded.id, node.id);
      expect(decoded.boardId, node.boardId);
      expect(decoded.kind, node.kind);
      expect(decoded.x, node.x);
      expect(decoded.y, node.y);
      expect(decoded.w, node.w);
      expect(decoded.h, node.h);
      expect(decoded.rotation, node.rotation);
      expect(decoded.z, node.z);
      expect(decoded.style, node.style);
      expect(decoded.content, node.content);
      expect(decoded.anchor, node.anchor);
      expect(decoded.contentText, node.contentText);
      expect(decoded.badge, node.badge);
      expect(decoded.deleted, node.deleted);
      expect(decoded.createdAt, node.createdAt);
      expect(decoded.updatedAt, node.updatedAt);
    });

    test('fromJson fills sensible defaults for missing fields', () {
      final decoded = GraphNode.fromJson({'id': 'legacy-node'});

      expect(decoded.id, 'legacy-node');
      expect(decoded.boardId, '');
      expect(decoded.kind, NodeKind.textNote);
      expect(decoded.x, 0);
      expect(decoded.y, 0);
      expect(decoded.w, 0);
      expect(decoded.h, 0);
      expect(decoded.rotation, 0);
      expect(decoded.z, 0);
      expect(decoded.style, GraphStyle.empty);
      expect(decoded.content, const EmptyNodeContent());
      expect(decoded.anchor, isNull);
      expect(decoded.contentText, '');
      expect(decoded.badge, isNull);
      expect(decoded.deleted, isFalse);
    });

    test('fromJson never throws on an unrecognized kind', () {
      final decoded = GraphNode.fromJson({
        'id': 'future-node',
        'kind': 'someKindFromAFutureBuild',
      });
      expect(decoded.kind, NodeKind.textNote);
    });

    test('toJson/fromJson round-trips a tombstoned (deleted) node', () {
      final node = GraphNode(
        id: 'node-1',
        boardId: 'board-1',
        kind: NodeKind.highlight,
        deleted: true,
        updatedAt: DateTime.utc(2026, 3, 1),
      );
      final decoded = GraphNode.fromJson(node.toJson());
      expect(decoded.deleted, isTrue);
    });
  });

  group('GraphEdge.toJson/fromJson', () {
    test('round-trips every field', () {
      final edge = GraphEdge(
        id: 'edge-1',
        boardId: 'board-1',
        fromNodeId: 'node-a',
        toNodeId: 'node-b',
        kind: EdgeKind.explains,
        label: 'explains',
        style: const GraphStyle(strokeWidth: 2.0),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
      );

      final decoded = GraphEdge.fromJson(edge.toJson());

      expect(decoded.id, edge.id);
      expect(decoded.boardId, edge.boardId);
      expect(decoded.fromNodeId, edge.fromNodeId);
      expect(decoded.toNodeId, edge.toNodeId);
      expect(decoded.kind, edge.kind);
      expect(decoded.label, edge.label);
      expect(decoded.style, edge.style);
      expect(decoded.createdAt, edge.createdAt);
      expect(decoded.updatedAt, edge.updatedAt);
    });

    test('fromJson fills sensible defaults for missing fields', () {
      final decoded = GraphEdge.fromJson({'id': 'legacy-edge'});

      expect(decoded.id, 'legacy-edge');
      expect(decoded.boardId, '');
      expect(decoded.fromNodeId, '');
      expect(decoded.toNodeId, '');
      expect(decoded.kind, EdgeKind.arrow);
      expect(decoded.label, isNull);
      expect(decoded.style, GraphStyle.empty);
    });

    test('fromJson never throws on an unrecognized kind', () {
      final decoded = GraphEdge.fromJson({
        'id': 'future-edge',
        'kind': 'someKindFromAFutureBuild',
      });
      expect(decoded.kind, EdgeKind.arrow);
    });
  });

  group('Board.toJson/fromJson', () {
    test('round-trips every field', () {
      final board = Board(
        id: 'board-1',
        title: 'My Canvas',
        bookId: 'book-1',
        isDefaultForBook: true,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
      );

      final decoded = Board.fromJson(board.toJson());

      expect(decoded.id, board.id);
      expect(decoded.title, board.title);
      expect(decoded.bookId, board.bookId);
      expect(decoded.isDefaultForBook, board.isDefaultForBook);
      expect(decoded.createdAt, board.createdAt);
      expect(decoded.updatedAt, board.updatedAt);
    });

    test('round-trips a free-form board with no bookId', () {
      final board = Board(id: 'board-2', title: 'Cross-book research');
      final decoded = Board.fromJson(board.toJson());
      expect(decoded.bookId, isNull);
      expect(decoded.isDefaultForBook, isFalse);
    });

    test('fromJson fills sensible defaults for missing fields', () {
      final decoded = Board.fromJson({'id': 'legacy-board'});
      expect(decoded.id, 'legacy-board');
      expect(decoded.title, 'Untitled board');
      expect(decoded.bookId, isNull);
      expect(decoded.isDefaultForBook, isFalse);
    });
  });
}
