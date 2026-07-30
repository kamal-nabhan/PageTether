// Unit tests for LibraryStore's boards/nodes/edges persistence
// (lib/core/storage/library_store.dart, pt.boards.v1/pt.nodes.v1/
// pt.edges.v1) — mirrors test/library_store_test.dart's coverage of the
// book/collection store. Uses SharedPreferences.setMockInitialValues so no
// real platform storage is touched.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagetether/core/models/graph/board.dart';
import 'package:pagetether/core/models/graph/graph_edge.dart';
import 'package:pagetether/core/models/graph/graph_node.dart';
import 'package:pagetether/core/models/graph/node_kind.dart';
import 'package:pagetether/core/storage/library_store.dart';

Board _board(String id, {String? bookId}) =>
    Board(id: id, title: 'Board $id', bookId: bookId);

GraphNode _node(String id, {String boardId = 'b1'}) => GraphNode(
  id: id,
  boardId: boardId,
  kind: NodeKind.textNote,
  contentText: 'text for $id',
);

GraphEdge _edge(String id, {String boardId = 'b1'}) => GraphEdge(
  id: id,
  boardId: boardId,
  fromNodeId: 'n1',
  toNodeId: 'n2',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LibraryStore boards', () {
    test('loadBoards starts empty', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      expect(await store.loadBoards(), isEmpty);
    });

    test('upsertBoard then loadBoards round-trips a board', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertBoard(_board('b1', bookId: 'book-1'));

      final loaded = await store.loadBoards();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'b1');
      expect(loaded.first.bookId, 'book-1');
    });

    test('upsertBoard overwrites an existing record with the same id', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertBoard(_board('b1'));
      await store.upsertBoard(_board('b1').copyWith(title: 'Renamed'));

      final loaded = await store.loadBoards();
      expect(loaded, hasLength(1));
      expect(loaded.first.title, 'Renamed');
    });

    test('removeBoard deletes a single record', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertBoard(_board('b1'));
      await store.upsertBoard(_board('b2'));
      await store.removeBoard('b1');

      final loaded = await store.loadBoards();
      expect(loaded.map((b) => b.id), ['b2']);
    });

    test('removeBoard is a no-op for an unknown id', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertBoard(_board('b1'));
      await store.removeBoard('does-not-exist');
      expect(await store.loadBoards(), hasLength(1));
    });

    test('saveAllBoards replaces the entire persisted list', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertBoard(_board('b1'));
      await store.saveAllBoards([_board('b2'), _board('b3')]);

      final loaded = await store.loadBoards();
      expect(loaded.map((b) => b.id).toSet(), {'b2', 'b3'});
    });
  });

  group('LibraryStore graph nodes', () {
    test('loadNodes starts empty', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      expect(await store.loadNodes(), isEmpty);
    });

    test('upsertNode then loadNodes round-trips a node', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertNode(_node('n1'));

      final loaded = await store.loadNodes();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'n1');
      expect(loaded.first.kind, NodeKind.textNote);
      expect(loaded.first.contentText, 'text for n1');
    });

    test('upsertNode overwrites an existing record with the same id', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertNode(_node('n1'));
      await store.upsertNode(_node('n1').copyWith(contentText: 'edited'));

      final loaded = await store.loadNodes();
      expect(loaded, hasLength(1));
      expect(loaded.first.contentText, 'edited');
    });

    test('removeNode deletes a single record', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertNode(_node('n1'));
      await store.upsertNode(_node('n2'));
      await store.removeNode('n1');

      final loaded = await store.loadNodes();
      expect(loaded.map((n) => n.id), ['n2']);
    });

    test('saveAllNodes replaces the entire persisted list', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertNode(_node('n1'));
      await store.saveAllNodes([_node('n2'), _node('n3')]);

      final loaded = await store.loadNodes();
      expect(loaded.map((n) => n.id).toSet(), {'n2', 'n3'});
    });
  });

  group('LibraryStore graph edges', () {
    test('loadEdges starts empty', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      expect(await store.loadEdges(), isEmpty);
    });

    test('upsertEdge then loadEdges round-trips an edge', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertEdge(_edge('e1'));

      final loaded = await store.loadEdges();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'e1');
      expect(loaded.first.fromNodeId, 'n1');
      expect(loaded.first.toNodeId, 'n2');
    });

    test('removeEdge deletes a single record', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertEdge(_edge('e1'));
      await store.upsertEdge(_edge('e2'));
      await store.removeEdge('e1');

      final loaded = await store.loadEdges();
      expect(loaded.map((e) => e.id), ['e2']);
    });

    test('saveAllEdges replaces the entire persisted list', () async {
      final store = LibraryStore(await SharedPreferences.getInstance());
      await store.upsertEdge(_edge('e1'));
      await store.saveAllEdges([_edge('e2'), _edge('e3')]);

      final loaded = await store.loadEdges();
      expect(loaded.map((e) => e.id).toSet(), {'e2', 'e3'});
    });
  });
}
