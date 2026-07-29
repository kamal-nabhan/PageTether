// Unit tests for BoardsNotifier/GraphNodesNotifier/GraphEdgesNotifier's
// last-write-wins remote merge (lib/features/graph/graph_providers.dart) —
// mirrors test/library_notifier_merge_test.dart's coverage of
// LibraryNotifier.mergeRemoteBooks. Drives each notifier via a real
// ProviderContainer with libraryStoreProvider backed by mocked
// SharedPreferences — no real Supabase calls.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagetether/core/models/graph/board.dart';
import 'package:pagetether/core/models/graph/graph_edge.dart';
import 'package:pagetether/core/models/graph/graph_node.dart';
import 'package:pagetether/core/models/graph/graph_style.dart';
import 'package:pagetether/core/models/graph/node_content.dart';
import 'package:pagetether/core/models/graph/node_kind.dart';
import 'package:pagetether/core/services/sync/sync_engine.dart';
import 'package:pagetether/core/storage/library_store.dart';
import 'package:pagetether/features/graph/graph_providers.dart';
import 'package:pagetether/features/library/library_providers.dart'
    show libraryStoreProvider;

Future<ProviderContainer> _container({
  List<Board> boards = const [],
  List<GraphNode> nodes = const [],
  List<GraphEdge> edges = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      libraryStoreProvider.overrideWithValue(LibraryStore(prefs)),
      boardsProvider.overrideWith(() => BoardsNotifier(boards)),
      graphNodesProvider.overrideWith(() => GraphNodesNotifier(nodes)),
      graphEdgesProvider.overrideWith(() => GraphEdgesNotifier(edges)),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardsNotifier.mergeRemoteBoards', () {
    test('adds a board that only exists remotely', () async {
      final container = await _container();
      addTearDown(container.dispose);

      final remote = SyncedBoard(
        id: 'r1',
        title: 'Remote board',
        bookId: 'book-1',
        isDefaultForBook: true,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final result = container
          .read(boardsProvider.notifier)
          .mergeRemoteBoards([remote]);

      expect(result, (added: 1, updated: 0));
      final board = container.read(boardsProvider).single;
      expect(board.title, 'Remote board');
      expect(board.bookId, 'book-1');
      expect(board.isDefaultForBook, isTrue);
    });

    test('keeps the local copy when local.updatedAt is strictly newer', () async {
      final local = Board(
        id: 'b1',
        title: 'Local title',
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      final container = await _container(boards: [local]);
      addTearDown(container.dispose);

      final remote = SyncedBoard(
        id: 'b1',
        title: 'Stale remote',
        bookId: null,
        isDefaultForBook: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final result = container
          .read(boardsProvider.notifier)
          .mergeRemoteBoards([remote]);

      expect(result, (added: 0, updated: 0));
      expect(container.read(boardsProvider).single.title, 'Local title');
    });

    test('keeps the local copy when timestamps are exactly equal', () async {
      final same = DateTime.utc(2026, 3, 1);
      final local = Board(id: 'b1', title: 'Local', updatedAt: same);
      final container = await _container(boards: [local]);
      addTearDown(container.dispose);

      final remote = SyncedBoard(
        id: 'b1',
        title: 'Remote',
        bookId: null,
        isDefaultForBook: false,
        updatedAt: same,
      );
      final result = container
          .read(boardsProvider.notifier)
          .mergeRemoteBoards([remote]);

      expect(result, (added: 0, updated: 0));
      expect(container.read(boardsProvider).single.title, 'Local');
    });

    test('adopts the remote row when it is strictly newer than local', () async {
      final local = Board(
        id: 'b1',
        title: 'Old title',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final container = await _container(boards: [local]);
      addTearDown(container.dispose);

      final remoteUpdatedAt = DateTime.utc(2026, 2, 1);
      final remote = SyncedBoard(
        id: 'b1',
        title: 'New title from another device',
        bookId: 'book-2',
        isDefaultForBook: true,
        updatedAt: remoteUpdatedAt,
      );
      final result = container
          .read(boardsProvider.notifier)
          .mergeRemoteBoards([remote]);

      expect(result, (added: 0, updated: 1));
      final board = container.read(boardsProvider).single;
      expect(board.title, 'New title from another device');
      expect(board.bookId, 'book-2');
      expect(board.updatedAt, remoteUpdatedAt);
    });

    test('is a no-op when remoteBoards is empty', () async {
      final local = Board(id: 'b1', title: 'Local', updatedAt: DateTime.utc(2026, 1, 1));
      final container = await _container(boards: [local]);
      addTearDown(container.dispose);

      final result = container
          .read(boardsProvider.notifier)
          .mergeRemoteBoards(const []);
      expect(result, (added: 0, updated: 0));
    });
  });

  group('GraphNodesNotifier.mergeRemoteNodes', () {
    SyncedGraphNode remoteNode({
      required String id,
      required DateTime updatedAt,
      String contentText = 'remote text',
      NodeKind kind = NodeKind.textNote,
    }) => SyncedGraphNode(
      id: id,
      boardId: 'board-1',
      kind: kind,
      x: 1,
      y: 2,
      w: 3,
      h: 4,
      rotation: 0,
      z: 0,
      style: GraphStyle.empty,
      content: const EmptyNodeContent(),
      anchor: null,
      contentText: contentText,
      badge: null,
      updatedAt: updatedAt,
    );

    test('adds a node that only exists remotely', () async {
      final container = await _container();
      addTearDown(container.dispose);

      final remote = remoteNode(id: 'n1', updatedAt: DateTime.utc(2026, 1, 1));
      final result = container
          .read(graphNodesProvider.notifier)
          .mergeRemoteNodes([remote]);

      expect(result, (added: 1, updated: 0));
      final node = container.read(graphNodesProvider).single;
      expect(node.contentText, 'remote text');
      // No pt_nodes.created_at column — a newly-added node's createdAt is
      // approximated as the remote row's updatedAt.
      expect(node.createdAt, remote.updatedAt);
    });

    test('keeps the local copy when local.updatedAt is strictly newer', () async {
      final local = GraphNode(
        id: 'n1',
        boardId: 'board-1',
        kind: NodeKind.textNote,
        contentText: 'local text',
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      final container = await _container(nodes: [local]);
      addTearDown(container.dispose);

      final remote = remoteNode(
        id: 'n1',
        updatedAt: DateTime.utc(2026, 1, 1),
        contentText: 'stale remote text',
      );
      final result = container
          .read(graphNodesProvider.notifier)
          .mergeRemoteNodes([remote]);

      expect(result, (added: 0, updated: 0));
      expect(container.read(graphNodesProvider).single.contentText, 'local text');
    });

    test('adopts the remote row when strictly newer, preserving local createdAt', () async {
      final localCreatedAt = DateTime.utc(2025, 1, 1);
      final local = GraphNode(
        id: 'n1',
        boardId: 'board-1',
        kind: NodeKind.textNote,
        contentText: 'old text',
        createdAt: localCreatedAt,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final container = await _container(nodes: [local]);
      addTearDown(container.dispose);

      final remoteUpdatedAt = DateTime.utc(2026, 2, 1);
      final remote = remoteNode(
        id: 'n1',
        updatedAt: remoteUpdatedAt,
        contentText: 'new text from another device',
        kind: NodeKind.highlight,
      );
      final result = container
          .read(graphNodesProvider.notifier)
          .mergeRemoteNodes([remote]);

      expect(result, (added: 0, updated: 1));
      final node = container.read(graphNodesProvider).single;
      expect(node.contentText, 'new text from another device');
      expect(node.kind, NodeKind.highlight);
      expect(node.updatedAt, remoteUpdatedAt);
      // createdAt is a purely local concept the merge never overwrites for
      // an already-known node.
      expect(node.createdAt, localCreatedAt);
    });

    test('is a no-op when remoteNodes is empty', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final result = container
          .read(graphNodesProvider.notifier)
          .mergeRemoteNodes(const []);
      expect(result, (added: 0, updated: 0));
    });
  });

  group('GraphEdgesNotifier.mergeRemoteEdges', () {
    SyncedGraphEdge remoteEdge({
      required String id,
      required DateTime updatedAt,
      String? label = 'remote label',
    }) => SyncedGraphEdge(
      id: id,
      boardId: 'board-1',
      fromNodeId: 'a',
      toNodeId: 'b',
      kind: EdgeKind.arrow,
      label: label,
      style: GraphStyle.empty,
      updatedAt: updatedAt,
    );

    test('adds an edge that only exists remotely', () async {
      final container = await _container();
      addTearDown(container.dispose);

      final remote = remoteEdge(id: 'e1', updatedAt: DateTime.utc(2026, 1, 1));
      final result = container
          .read(graphEdgesProvider.notifier)
          .mergeRemoteEdges([remote]);

      expect(result, (added: 1, updated: 0));
      expect(container.read(graphEdgesProvider).single.label, 'remote label');
    });

    test('keeps the local copy when local.updatedAt is strictly newer', () async {
      final local = GraphEdge(
        id: 'e1',
        boardId: 'board-1',
        fromNodeId: 'a',
        toNodeId: 'b',
        label: 'local label',
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      final container = await _container(edges: [local]);
      addTearDown(container.dispose);

      final remote = remoteEdge(
        id: 'e1',
        updatedAt: DateTime.utc(2026, 1, 1),
        label: 'stale remote label',
      );
      final result = container
          .read(graphEdgesProvider.notifier)
          .mergeRemoteEdges([remote]);

      expect(result, (added: 0, updated: 0));
      expect(container.read(graphEdgesProvider).single.label, 'local label');
    });

    test('adopts the remote row when it is strictly newer than local', () async {
      final local = GraphEdge(
        id: 'e1',
        boardId: 'board-1',
        fromNodeId: 'a',
        toNodeId: 'b',
        label: 'old label',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final container = await _container(edges: [local]);
      addTearDown(container.dispose);

      final remoteUpdatedAt = DateTime.utc(2026, 2, 1);
      final remote = remoteEdge(
        id: 'e1',
        updatedAt: remoteUpdatedAt,
        label: 'new label from another device',
      );
      final result = container
          .read(graphEdgesProvider.notifier)
          .mergeRemoteEdges([remote]);

      expect(result, (added: 0, updated: 1));
      final edge = container.read(graphEdgesProvider).single;
      expect(edge.label, 'new label from another device');
      expect(edge.updatedAt, remoteUpdatedAt);
    });

    test('is a no-op when remoteEdges is empty', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final result = container
          .read(graphEdgesProvider.notifier)
          .mergeRemoteEdges(const []);
      expect(result, (added: 0, updated: 0));
    });
  });
}
