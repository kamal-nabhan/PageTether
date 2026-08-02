// Row (de)serialization tests for SyncedBoard/SyncedGraphNode/SyncedGraphEdge
// (lib/core/services/sync/sync_engine.dart) — mirrors
// test/sync_engine_test.dart's coverage of SyncedBook/SyncedCollection.
// Asserts the row keys these produce/consume match schema.sql's
// pt_boards/pt_nodes/pt_edges column names exactly, since a mismatch there
// would silently null out columns on upsert. Pure logic — no real Supabase
// client involved.
import 'package:flutter_test/flutter_test.dart';
import 'package:pagetether/core/models/graph/graph_edge.dart';
import 'package:pagetether/core/models/graph/graph_style.dart';
import 'package:pagetether/core/models/graph/node_anchor.dart';
import 'package:pagetether/core/models/graph/node_content.dart';
import 'package:pagetether/core/models/graph/node_kind.dart';
import 'package:pagetether/core/models/graph/node_region.dart';
import 'package:pagetether/core/services/sync/sync_engine.dart';

void main() {
  group('SyncedBoard.fromRow/toRow', () {
    test('fromRow parses a schema.sql-shaped pt_boards row', () {
      final row = {
        'user_id': 'user-1',
        'id': 'board-1',
        'title': 'My Canvas',
        'book_id': 'book-1',
        'is_default_for_book': true,
        'updated_at': '2026-03-15T10:30:00.000Z',
      };
      final board = SyncedBoard.fromRow(row);

      expect(board.id, 'board-1');
      expect(board.title, 'My Canvas');
      expect(board.bookId, 'book-1');
      expect(board.isDefaultForBook, isTrue);
      expect(board.updatedAt, DateTime.parse('2026-03-15T10:30:00.000Z'));
    });

    test('fromRow defaults missing optional columns', () {
      final board = SyncedBoard.fromRow({'id': 'board-1'});
      expect(board.title, '');
      expect(board.bookId, isNull);
      expect(board.isDefaultForBook, isFalse);
    });

    test('toRow produces exactly the pt_boards columns from schema.sql', () {
      final board = SyncedBoard(
        id: 'board-1',
        title: 'My Canvas',
        bookId: 'book-1',
        isDefaultForBook: true,
        updatedAt: DateTime.utc(2026, 3, 15, 10, 30),
      );
      final row = board.toRow('user-1');

      expect(row.keys.toSet(), {
        'user_id',
        'id',
        'title',
        'book_id',
        'is_default_for_book',
        'updated_at',
      });
      expect(row['user_id'], 'user-1');
      expect(row['id'], 'board-1');
      expect(row['book_id'], 'book-1');
      expect(row['is_default_for_book'], isTrue);
    });

    test('round-trips through fromRow(toRow(...))', () {
      final original = SyncedBoard(
        id: 'board-2',
        title: 'Round Trip',
        bookId: null,
        isDefaultForBook: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final roundTripped = SyncedBoard.fromRow(original.toRow('user-1'));

      expect(roundTripped.id, original.id);
      expect(roundTripped.title, original.title);
      expect(roundTripped.bookId, original.bookId);
      expect(roundTripped.isDefaultForBook, original.isDefaultForBook);
      expect(roundTripped.updatedAt, original.updatedAt);
    });
  });

  group('SyncedGraphNode.fromRow/toRow', () {
    test('fromRow parses a schema.sql-shaped pt_nodes row', () {
      final row = {
        'user_id': 'user-1',
        'id': 'node-1',
        'board_id': 'board-1',
        'kind': 'highlight',
        'x': 1.5,
        'y': 2.5,
        'w': 100.0,
        'h': 20.0,
        'rotation': 0.0,
        'z': 3.0,
        'style': {'color': 0xFF112233, 'opacity': 0.9},
        'content': {'type': 'text', 'text': 'body'},
        'anchor': {'bookId': 'book-1', 'page': 4},
        'content_text': 'source passage',
        'badge': 'TODO',
        'updated_at': '2026-03-15T10:30:00.000Z',
      };
      final node = SyncedGraphNode.fromRow(row);

      expect(node.id, 'node-1');
      expect(node.boardId, 'board-1');
      expect(node.kind, NodeKind.highlight);
      expect(node.x, 1.5);
      expect(node.y, 2.5);
      expect(node.w, 100.0);
      expect(node.h, 20.0);
      expect(node.z, 3.0);
      expect(node.style.color, 0xFF112233);
      expect(node.content, const TextNodeContent(text: 'body'));
      expect(node.anchor, const NodeAnchor(bookId: 'book-1', page: 4));
      expect(node.contentText, 'source passage');
      expect(node.badge, 'TODO');
      expect(node.deleted, isFalse);
      expect(node.updatedAt, DateTime.parse('2026-03-15T10:30:00.000Z'));
    });

    test(
      'fromRow defaults missing optional columns, unrecognized kind falls back',
      () {
        final node = SyncedGraphNode.fromRow({
          'id': 'node-1',
          'kind': 'someFutureKind',
        });
        expect(node.boardId, '');
        expect(node.kind, NodeKind.textNote);
        expect(node.x, 0);
        expect(node.style, GraphStyle.empty);
        expect(node.content, const EmptyNodeContent());
        expect(node.anchor, isNull);
        expect(node.contentText, '');
        expect(node.badge, isNull);
        expect(node.deleted, isFalse);
      },
    );

    test('fromRow parses a tombstoned (deleted: true) row', () {
      final node = SyncedGraphNode.fromRow({
        'id': 'node-1',
        'kind': 'highlight',
        'deleted': true,
      });
      expect(node.deleted, isTrue);
    });

    test('toRow produces exactly the pt_nodes columns from schema.sql', () {
      final node = SyncedGraphNode(
        id: 'node-1',
        boardId: 'board-1',
        kind: NodeKind.ink,
        x: 1,
        y: 2,
        w: 3,
        h: 4,
        rotation: 0,
        z: 0,
        style: GraphStyle.empty,
        content: const VectorNodeContent(
          paths: [
            [0, 0, 1, 1],
          ],
        ),
        anchor: null,
        contentText: '',
        badge: null,
        deleted: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final row = node.toRow('user-1');

      expect(row.keys.toSet(), {
        'user_id',
        'id',
        'board_id',
        'kind',
        'x',
        'y',
        'w',
        'h',
        'rotation',
        'z',
        'style',
        'content',
        'anchor',
        'content_text',
        'badge',
        'deleted',
        'updated_at',
      });
      expect(row['kind'], 'ink');
      expect(row['anchor'], isNull);
      expect(row['deleted'], isFalse);
    });

    test('round-trips through fromRow(toRow(...))', () {
      final original = SyncedGraphNode(
        id: 'node-2',
        boardId: 'board-1',
        kind: NodeKind.regionClip,
        x: 5,
        y: 6,
        w: 7,
        h: 8,
        rotation: 1.2,
        z: 9,
        style: const GraphStyle(color: 0xFFABCDEF),
        content: const ImageNodeContent(imageRef: 'drive:xyz'),
        anchor: const NodeAnchor(
          bookId: 'book-1',
          page: 2,
          region: NormalizedRectRegion(
            NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
          ),
        ),
        contentText: 'clip text',
        badge: 'note',
        deleted: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final roundTripped = SyncedGraphNode.fromRow(original.toRow('user-1'));

      expect(roundTripped.id, original.id);
      expect(roundTripped.boardId, original.boardId);
      expect(roundTripped.kind, original.kind);
      expect(roundTripped.x, original.x);
      expect(roundTripped.style, original.style);
      expect(roundTripped.content, original.content);
      expect(roundTripped.anchor, original.anchor);
      expect(roundTripped.contentText, original.contentText);
      expect(roundTripped.badge, original.badge);
      expect(roundTripped.deleted, original.deleted);
      expect(roundTripped.updatedAt, original.updatedAt);
    });

    test('round-trips a tombstoned node through fromRow(toRow(...))', () {
      // Verifies the delete-propagation path end to end at the sync-row
      // layer: a node tombstoned via GraphNodesNotifier.setDeleted (deleted:
      // true) must still carry that flag through a push (toRow) and a pull
      // (fromRow) unchanged, since that's exactly what lets the delete reach
      // another device — see GraphNode's class doc.
      final original = SyncedGraphNode(
        id: 'node-3',
        boardId: 'board-1',
        kind: NodeKind.highlight,
        x: 0,
        y: 0,
        w: 0,
        h: 0,
        rotation: 0,
        z: 0,
        style: GraphStyle.empty,
        content: const EmptyNodeContent(),
        anchor: null,
        contentText: 'deleted highlight',
        badge: null,
        deleted: true,
        updatedAt: DateTime.utc(2026, 4, 1),
      );
      final roundTripped = SyncedGraphNode.fromRow(original.toRow('user-1'));

      expect(roundTripped.deleted, isTrue);
      expect(roundTripped.updatedAt, original.updatedAt);
    });
  });

  group('SyncedGraphEdge.fromRow/toRow', () {
    test('fromRow parses a schema.sql-shaped pt_edges row', () {
      final row = {
        'user_id': 'user-1',
        'id': 'edge-1',
        'board_id': 'board-1',
        'from_node_id': 'node-a',
        'to_node_id': 'node-b',
        'kind': 'explains',
        'label': 'explains',
        'style': {'strokeWidth': 2.0},
        'updated_at': '2026-02-01T09:00:00.000Z',
      };
      final edge = SyncedGraphEdge.fromRow(row);

      expect(edge.id, 'edge-1');
      expect(edge.boardId, 'board-1');
      expect(edge.fromNodeId, 'node-a');
      expect(edge.toNodeId, 'node-b');
      expect(edge.kind, EdgeKind.explains);
      expect(edge.label, 'explains');
      expect(edge.style.strokeWidth, 2.0);
      expect(edge.updatedAt, DateTime.parse('2026-02-01T09:00:00.000Z'));
    });

    test(
      'fromRow defaults missing optional columns, unrecognized kind falls back',
      () {
        final edge = SyncedGraphEdge.fromRow({
          'id': 'edge-1',
          'kind': 'someFutureKind',
        });
        expect(edge.boardId, '');
        expect(edge.fromNodeId, '');
        expect(edge.toNodeId, '');
        expect(edge.kind, EdgeKind.arrow);
        expect(edge.label, isNull);
        expect(edge.style, GraphStyle.empty);
      },
    );

    test('toRow produces exactly the pt_edges columns from schema.sql', () {
      final edge = SyncedGraphEdge(
        id: 'edge-1',
        boardId: 'board-1',
        fromNodeId: 'node-a',
        toNodeId: 'node-b',
        kind: EdgeKind.link,
        label: null,
        style: GraphStyle.empty,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final row = edge.toRow('user-1');

      expect(row.keys.toSet(), {
        'user_id',
        'id',
        'board_id',
        'from_node_id',
        'to_node_id',
        'kind',
        'label',
        'style',
        'updated_at',
      });
      expect(row['kind'], 'link');
    });

    test('round-trips through fromRow(toRow(...))', () {
      final original = SyncedGraphEdge(
        id: 'edge-2',
        boardId: 'board-1',
        fromNodeId: 'node-a',
        toNodeId: 'node-b',
        kind: EdgeKind.arrow,
        label: 'flows to',
        style: const GraphStyle(color: 0xFF000000),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final roundTripped = SyncedGraphEdge.fromRow(original.toRow('user-1'));

      expect(roundTripped.id, original.id);
      expect(roundTripped.boardId, original.boardId);
      expect(roundTripped.fromNodeId, original.fromNodeId);
      expect(roundTripped.toNodeId, original.toNodeId);
      expect(roundTripped.kind, original.kind);
      expect(roundTripped.label, original.label);
      expect(roundTripped.style, original.style);
      expect(roundTripped.updatedAt, original.updatedAt);
    });
  });
}
