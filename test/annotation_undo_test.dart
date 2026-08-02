// Unit test for the delete-with-undo flow's core building block: capturing
// a removed GraphNode and re-upserting it fully restores it — the same
// remove-then-upsert sequence `_ReaderScreenState._deleteAnnotationWithUndo`
// (lib/features/reader/reader_screen.dart) performs when the SnackBar's
// Undo action fires. Exercises GraphNodesNotifier directly rather than the
// full reader widget, mirroring test/graph_default_board_test.dart's
// ProviderContainer setup — no pdfrx/widget dependency needed to prove the
// provider-level contract that makes undo work.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagetether/core/models/graph/graph_node.dart';
import 'package:pagetether/core/models/graph/node_kind.dart';
import 'package:pagetether/core/storage/library_store.dart';
import 'package:pagetether/features/graph/graph_providers.dart';
import 'package:pagetether/features/library/library_providers.dart'
    show libraryStoreProvider;

Future<ProviderContainer> _container({List<GraphNode> nodes = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      libraryStoreProvider.overrideWithValue(LibraryStore(prefs)),
      graphNodesProvider.overrideWith(() => GraphNodesNotifier(nodes)),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'removing a node then re-upserting the captured node restores it',
    () async {
      final node = GraphNode(
        id: 'highlight-1',
        boardId: 'board-1',
        kind: NodeKind.highlight,
        contentText: 'some passage',
      );
      final container = await _container(nodes: [node]);
      addTearDown(container.dispose);
      final notifier = container.read(graphNodesProvider.notifier);

      notifier.remove(node.id);
      expect(container.read(graphNodesProvider), isEmpty);

      // Undo: re-upsert the exact GraphNode captured before deletion.
      notifier.upsert(node);

      expect(container.read(graphNodesProvider), [node]);
    },
  );

  test('undo restores the node, leaving unrelated nodes untouched', () async {
    final kept = GraphNode(
      id: 'keep',
      boardId: 'board-1',
      kind: NodeKind.underline,
    );
    final deleted = GraphNode(
      id: 'delete-me',
      boardId: 'board-1',
      kind: NodeKind.highlight,
    );
    final container = await _container(nodes: [kept, deleted]);
    addTearDown(container.dispose);
    final notifier = container.read(graphNodesProvider.notifier);

    notifier.remove(deleted.id);
    expect(container.read(graphNodesProvider), [kept]);

    notifier.upsert(deleted);

    expect(container.read(graphNodesProvider), hasLength(2));
    expect(container.read(graphNodesProvider), containsAll([kept, deleted]));
  });
}
