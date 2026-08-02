// Unit test for the delete-with-undo flow's core building block:
// tombstoning a node then un-tombstoning it fully restores it (still
// visible, [GraphNode.deleted] back to false) — the same
// `setDeleted(id, true)` / `setDeleted(id, false)` sequence
// `_ReaderScreenState._deleteAnnotationWithUndo`
// (lib/features/reader/reader_screen.dart) performs when the SnackBar's
// Undo action fires. Exercises GraphNodesNotifier directly rather than the
// full reader widget, mirroring test/graph_default_board_test.dart's
// ProviderContainer setup — no pdfrx/widget dependency needed to prove the
// provider-level contract that makes undo work.
//
// Deliberately tombstone-based (not remove-then-upsert): a hard
// GraphNodesNotifier.remove never reaches Supabase (see that method's doc),
// so it can't be what backs a delete that's meant to sync — see
// GraphNodesNotifier.setDeleted's doc and GraphNode's class doc for why
// deletion is a synced `deleted` flag instead.
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
    'tombstoning a node then un-tombstoning it restores it (deleted: false)',
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

      notifier.setDeleted(node.id, true);
      // The node stays in state (so the tombstone itself can sync) — it's
      // AnnotationOverlay's job to filter deleted nodes out of the UI, not
      // the notifier's.
      expect(container.read(graphNodesProvider), hasLength(1));
      expect(container.read(graphNodesProvider).single.deleted, isTrue);

      // Undo: setDeleted(id, false) rather than re-upserting the originally
      // captured node — see this file's header doc for why.
      notifier.setDeleted(node.id, false);

      expect(container.read(graphNodesProvider), hasLength(1));
      final restored = container.read(graphNodesProvider).single;
      expect(restored.deleted, isFalse);
      expect(restored.contentText, 'some passage');
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

    notifier.setDeleted(deleted.id, true);
    expect(
      container
          .read(graphNodesProvider)
          .firstWhere((n) => n.id == kept.id)
          .deleted,
      isFalse,
    );
    expect(
      container
          .read(graphNodesProvider)
          .firstWhere((n) => n.id == deleted.id)
          .deleted,
      isTrue,
    );

    notifier.setDeleted(deleted.id, false);

    expect(container.read(graphNodesProvider), hasLength(2));
    expect(
      container.read(graphNodesProvider).every((n) => n.deleted == false),
      isTrue,
    );
  });

  test('setDeleted is a no-op for an unknown id', () async {
    final container = await _container();
    addTearDown(container.dispose);
    final notifier = container.read(graphNodesProvider.notifier);

    notifier.setDeleted('does-not-exist', true);

    expect(container.read(graphNodesProvider), isEmpty);
  });

  test(
    'setDeleted bumps updatedAt so an undo also wins last-write-wins remotely',
    () async {
      final node = GraphNode(
        id: 'n1',
        boardId: 'board-1',
        kind: NodeKind.highlight,
        updatedAt: DateTime.utc(2020, 1, 1),
      );
      final container = await _container(nodes: [node]);
      addTearDown(container.dispose);
      final notifier = container.read(graphNodesProvider.notifier);

      notifier.setDeleted(node.id, true);
      final afterDelete = container.read(graphNodesProvider).single;
      expect(afterDelete.updatedAt.isAfter(node.updatedAt), isTrue);

      notifier.setDeleted(node.id, false);
      final afterUndo = container.read(graphNodesProvider).single;
      // Not strictly-after afterDelete's timestamp (two back-to-back
      // DateTime.now() calls could tie on a coarse clock) — just confirms the
      // undo is itself a fresh stamp past the node's original updatedAt,
      // rather than reverting to it.
      expect(afterUndo.updatedAt.isAfter(node.updatedAt), isTrue);
      expect(afterUndo.updatedAt.isBefore(afterDelete.updatedAt), isFalse);
    },
  );
}
