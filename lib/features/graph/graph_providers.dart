// Riverpod state for the annotation graph model (Boards/GraphNodes/
// GraphEdges) — the local-store-backed lists plus the sync-pull-and-merge
// path, mirroring `features/library/library_providers.dart`'s
// LibraryNotifier/CollectionsNotifier exactly (see [BoardsNotifier],
// [GraphNodesNotifier], [GraphEdgesNotifier] below). No UI reads these yet
// (the canvas UI is a later phase) — this file exists so `SyncNotifier`
// (`features/settings/settings_providers.dart`) has something to pull/merge/
// push against, and so a later canvas feature has ready-made CRUD +
// last-write-wins sync to build on rather than inventing it per-screen.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/graph/board.dart';
import '../../core/models/graph/graph_edge.dart';
import '../../core/models/graph/graph_node.dart';
import '../../core/services/sync/sync_engine.dart';
import '../../core/storage/library_store.dart';
import '../library/library_providers.dart' show libraryStoreProvider;

/// Holds every persisted [Board]. Seeded in `main()` with
/// `LibraryStore.loadBoards()`'s result, mirroring
/// `CollectionsNotifier`/`LibraryNotifier`'s constructor-seeded pattern.
class BoardsNotifier extends Notifier<List<Board>> {
  BoardsNotifier([this._initial = const []]);

  final List<Board> _initial;

  @override
  List<Board> build() => _initial;

  LibraryStore get _store => ref.read(libraryStoreProvider);

  /// Inserts or updates [board] in place and persists it.
  void upsert(Board board) {
    final exists = state.any((b) => b.id == board.id);
    state = exists
        ? [for (final b in state) if (b.id == board.id) board else b]
        : [...state, board];
    unawaited(_store.upsertBoard(board));
  }

  /// Removes board [id]. No-op if it isn't known. Deliberately does not
  /// cascade to that board's nodes/edges — a later canvas feature that wants
  /// "delete board and everything on it" composes this with
  /// [GraphNodesNotifier.removeForBoard]/[GraphEdgesNotifier.removeForBoard]
  /// itself, the same way `CollectionsNotifier.delete` composes with
  /// `LibraryNotifier.removeCollectionFromAllBooks`.
  void remove(String id) {
    if (!state.any((b) => b.id == id)) return;
    state = [for (final b in state) if (b.id != id) b];
    unawaited(_store.removeBoard(id));
  }

  /// Merges [remoteBoards] (pulled via `SyncEngine.pullBoards`) into the
  /// local list — last-write-wins by `updated_at`, identical semantics to
  /// `LibraryNotifier.mergeRemoteBooks` (see that doc comment): a board known
  /// only remotely is added; a board known both locally and remotely only
  /// has its fields overwritten when the remote row is *strictly* newer;
  /// otherwise the local copy is left untouched. Returns how many boards
  /// were added vs. updated, for the sync summary.
  ({int added, int updated}) mergeRemoteBoards(List<SyncedBoard> remoteBoards) {
    var added = 0;
    var updated = 0;
    final byId = {for (final b in state) b.id: b};

    for (final remote in remoteBoards) {
      final local = byId[remote.id];
      if (local == null) {
        byId[remote.id] = Board(
          id: remote.id,
          title: remote.title,
          bookId: remote.bookId,
          isDefaultForBook: remote.isDefaultForBook,
          createdAt: remote.updatedAt,
          updatedAt: remote.updatedAt,
        );
        added++;
        continue;
      }
      if (!remote.updatedAt.isAfter(local.updatedAt)) continue;
      byId[remote.id] = local.copyWith(
        title: remote.title,
        bookId: remote.bookId,
        isDefaultForBook: remote.isDefaultForBook,
        updatedAt: remote.updatedAt,
      );
      updated++;
    }

    if (added == 0 && updated == 0) return (added: 0, updated: 0);
    state = byId.values.toList();
    unawaited(_store.saveAllBoards(state));
    return (added: added, updated: updated);
  }
}

final boardsProvider = NotifierProvider<BoardsNotifier, List<Board>>(
  BoardsNotifier.new,
);

/// Holds every persisted [GraphNode], across every board. Seeded in
/// `main()` with `LibraryStore.loadNodes()`'s result.
class GraphNodesNotifier extends Notifier<List<GraphNode>> {
  GraphNodesNotifier([this._initial = const []]);

  final List<GraphNode> _initial;

  @override
  List<GraphNode> build() => _initial;

  LibraryStore get _store => ref.read(libraryStoreProvider);

  /// Inserts or updates [node] in place and persists it.
  void upsert(GraphNode node) {
    final exists = state.any((n) => n.id == node.id);
    state = exists
        ? [for (final n in state) if (n.id == node.id) node else n]
        : [...state, node];
    unawaited(_store.upsertNode(node));
  }

  /// Removes node [id]. No-op if it isn't known. Deliberately does not
  /// cascade to edges referencing it — see [BoardsNotifier.remove]'s doc for
  /// why cascades are left to the caller.
  void remove(String id) {
    if (!state.any((n) => n.id == id)) return;
    state = [for (final n in state) if (n.id != id) n];
    unawaited(_store.removeNode(id));
  }

  /// Every node whose [GraphNode.boardId] is [boardId], in [upsert] order.
  void removeForBoard(String boardId) {
    final toRemove = [for (final n in state) if (n.boardId == boardId) n.id];
    if (toRemove.isEmpty) return;
    state = [for (final n in state) if (n.boardId != boardId) n];
    for (final id in toRemove) {
      unawaited(_store.removeNode(id));
    }
  }

  /// Merges [remoteNodes] (pulled via `SyncEngine.pullNodes`) into the local
  /// list — last-write-wins by `updated_at`, identical semantics to
  /// `LibraryNotifier.mergeRemoteBooks`. A node's [GraphNode.createdAt] is
  /// purely local (see `SyncedGraphNode`'s doc comment on why `pt_nodes` has
  /// no `created_at` column): a newly-added node's `createdAt` is set to the
  /// remote row's `updatedAt` (the best available approximation), while an
  /// updated node keeps its existing local `createdAt` untouched via
  /// [GraphNode.copyWith]. Returns how many nodes were added vs. updated.
  ({int added, int updated}) mergeRemoteNodes(
    List<SyncedGraphNode> remoteNodes,
  ) {
    var added = 0;
    var updated = 0;
    final byId = {for (final n in state) n.id: n};

    for (final remote in remoteNodes) {
      final local = byId[remote.id];
      if (local == null) {
        byId[remote.id] = GraphNode(
          id: remote.id,
          boardId: remote.boardId,
          kind: remote.kind,
          x: remote.x,
          y: remote.y,
          w: remote.w,
          h: remote.h,
          rotation: remote.rotation,
          z: remote.z,
          style: remote.style,
          content: remote.content,
          anchor: remote.anchor,
          contentText: remote.contentText,
          badge: remote.badge,
          createdAt: remote.updatedAt,
          updatedAt: remote.updatedAt,
        );
        added++;
        continue;
      }
      if (!remote.updatedAt.isAfter(local.updatedAt)) continue;
      byId[remote.id] = local.copyWith(
        boardId: remote.boardId,
        kind: remote.kind,
        x: remote.x,
        y: remote.y,
        w: remote.w,
        h: remote.h,
        rotation: remote.rotation,
        z: remote.z,
        style: remote.style,
        content: remote.content,
        anchor: remote.anchor,
        contentText: remote.contentText,
        badge: remote.badge,
        updatedAt: remote.updatedAt,
      );
      updated++;
    }

    if (added == 0 && updated == 0) return (added: 0, updated: 0);
    state = byId.values.toList();
    unawaited(_store.saveAllNodes(state));
    return (added: added, updated: updated);
  }
}

final graphNodesProvider = NotifierProvider<GraphNodesNotifier, List<GraphNode>>(
  GraphNodesNotifier.new,
);

/// Holds every persisted [GraphEdge], across every board. Seeded in
/// `main()` with `LibraryStore.loadEdges()`'s result.
class GraphEdgesNotifier extends Notifier<List<GraphEdge>> {
  GraphEdgesNotifier([this._initial = const []]);

  final List<GraphEdge> _initial;

  @override
  List<GraphEdge> build() => _initial;

  LibraryStore get _store => ref.read(libraryStoreProvider);

  /// Inserts or updates [edge] in place and persists it.
  void upsert(GraphEdge edge) {
    final exists = state.any((e) => e.id == edge.id);
    state = exists
        ? [for (final e in state) if (e.id == edge.id) edge else e]
        : [...state, edge];
    unawaited(_store.upsertEdge(edge));
  }

  /// Removes edge [id]. No-op if it isn't known.
  void remove(String id) {
    if (!state.any((e) => e.id == id)) return;
    state = [for (final e in state) if (e.id != id) e];
    unawaited(_store.removeEdge(id));
  }

  /// Every edge whose [GraphEdge.boardId] is [boardId] — see
  /// [GraphNodesNotifier.removeForBoard]'s doc.
  void removeForBoard(String boardId) {
    final toRemove = [for (final e in state) if (e.boardId == boardId) e.id];
    if (toRemove.isEmpty) return;
    state = [for (final e in state) if (e.boardId != boardId) e];
    for (final id in toRemove) {
      unawaited(_store.removeEdge(id));
    }
  }

  /// Merges [remoteEdges] (pulled via `SyncEngine.pullEdges`) into the local
  /// list — last-write-wins by `updated_at`, identical semantics to
  /// `LibraryNotifier.mergeRemoteBooks`; a new edge's `createdAt` is set to
  /// the remote row's `updatedAt` for the same reason as
  /// `GraphNodesNotifier.mergeRemoteNodes` (see that doc). Returns how many
  /// edges were added vs. updated.
  ({int added, int updated}) mergeRemoteEdges(
    List<SyncedGraphEdge> remoteEdges,
  ) {
    var added = 0;
    var updated = 0;
    final byId = {for (final e in state) e.id: e};

    for (final remote in remoteEdges) {
      final local = byId[remote.id];
      if (local == null) {
        byId[remote.id] = GraphEdge(
          id: remote.id,
          boardId: remote.boardId,
          fromNodeId: remote.fromNodeId,
          toNodeId: remote.toNodeId,
          kind: remote.kind,
          label: remote.label,
          style: remote.style,
          createdAt: remote.updatedAt,
          updatedAt: remote.updatedAt,
        );
        added++;
        continue;
      }
      if (!remote.updatedAt.isAfter(local.updatedAt)) continue;
      byId[remote.id] = local.copyWith(
        boardId: remote.boardId,
        fromNodeId: remote.fromNodeId,
        toNodeId: remote.toNodeId,
        kind: remote.kind,
        label: remote.label,
        style: remote.style,
        updatedAt: remote.updatedAt,
      );
      updated++;
    }

    if (added == 0 && updated == 0) return (added: 0, updated: 0);
    state = byId.values.toList();
    unawaited(_store.saveAllEdges(state));
    return (added: added, updated: updated);
  }
}

final graphEdgesProvider = NotifierProvider<GraphEdgesNotifier, List<GraphEdge>>(
  GraphEdgesNotifier.new,
);
