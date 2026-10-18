import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/format.dart';
import '../core/models.dart';
import 'providers.dart';

@immutable
class FilesState {
  const FilesState({
    this.path = '',
    this.parent,
    this.entries = const [],
    this.loading = true,
    this.error,
    this.selection = const {},
    this.clipboard = const [],
    this.cut = false,
    this.hiddenCount = 0,
    this.roots = const [],
    this.hasAccess = true,
    this.op,
    this.opLabel,
    this.filter = '',
  });

  final String path;
  final String? parent;
  final List<FileEntry> entries;
  final bool loading;
  final String? error;
  final Set<String> selection;
  final List<String> clipboard;
  final bool cut;
  final int hiddenCount;
  final List<StorageRoot> roots;
  final bool hasAccess;
  final OpEvent? op;
  final String? opLabel;
  final String filter;

  bool get selecting => selection.isNotEmpty;

  List<FileEntry> get visible {
    if (filter.isEmpty) return entries;
    final needle = filter.toLowerCase();
    return entries.where((e) => e.name.toLowerCase().contains(needle)).toList();
  }

  List<FileEntry> get selected => entries.where((e) => selection.contains(e.path)).toList();

  FilesState copyWith({
    String? path,
    String? parent,
    bool clearParent = false,
    List<FileEntry>? entries,
    bool? loading,
    String? error,
    bool clearError = false,
    Set<String>? selection,
    List<String>? clipboard,
    bool? cut,
    int? hiddenCount,
    List<StorageRoot>? roots,
    bool? hasAccess,
    OpEvent? op,
    String? opLabel,
    bool clearOp = false,
    String? filter,
  }) {
    return FilesState(
      path: path ?? this.path,
      parent: clearParent ? null : (parent ?? this.parent),
      entries: entries ?? this.entries,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      selection: selection ?? this.selection,
      clipboard: clipboard ?? this.clipboard,
      cut: cut ?? this.cut,
      hiddenCount: hiddenCount ?? this.hiddenCount,
      roots: roots ?? this.roots,
      hasAccess: hasAccess ?? this.hasAccess,
      op: clearOp ? null : (op ?? this.op),
      opLabel: clearOp ? null : (opLabel ?? this.opLabel),
      filter: filter ?? this.filter,
    );
  }
}

class FilesNotifier extends StateNotifier<FilesState> {
  FilesNotifier(this._ref) : super(const FilesState());

  final Ref _ref;
  StreamSubscription<String>? _watch;
  Timer? _debounce;
  bool _booted = false;
  final List<String> _back = [];

  Api get _api => _ref.read(apiProvider);

  Future<void> boot() async {
    if (_booted) return;
    _booted = true;
    _watch = _api.fs.changes().listen((changed) {
      if (changed == state.path) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 150), () => refresh(silent: true));
      }
    });
    try {
      final roots = await _api.fs.roots();
      final access = await _api.fs.hasAccess();
      state = state.copyWith(roots: roots, hasAccess: access);
      final settings = _ref.read(settingsProvider);
      StorageRoot? start;
      for (final r in roots) {
        if (r.id == settings.lastRoot) start = r;
      }
      start ??= roots.isEmpty ? null : roots.first;
      if (start != null) await open(start.path, pushHistory: false);
    } catch (error) {
      state = state.copyWith(loading: false, error: describeError(error));
    }
  }

  Future<void> recheckAccess() async {
    try {
      final access = await _api.fs.hasAccess();
      final roots = await _api.fs.roots();
      state = state.copyWith(hasAccess: access, roots: roots);
      if (access) await refresh();
    } catch (_) {}
  }

  Future<void> open(String path, {bool pushHistory = true}) async {
    if (pushHistory && state.path.isNotEmpty && state.path != path) _back.add(state.path);
    state = state.copyWith(loading: true, clearError: true, selection: {}, filter: '');
    await _load(path);
  }

  Future<void> _load(String path) async {
    final settings = _ref.read(settingsProvider);
    try {
      final listing = await _api.fs.list(path, showHidden: settings.showHidden, sort: settings.sort, ascending: settings.ascending);
      state = state.copyWith(
        path: listing.path,
        parent: listing.parent,
        clearParent: listing.parent == null,
        entries: listing.entries,
        hiddenCount: listing.hiddenCount,
        loading: false,
        clearError: true,
      );
      await _api.fs.watch(listing.path);
    } catch (error) {
      state = state.copyWith(path: path, loading: false, error: describeError(error), entries: const []);
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (state.path.isEmpty) return boot();
    if (!silent) state = state.copyWith(loading: true);
    await _load(state.path);
  }

  Future<void> up() async {
    final parent = state.parent;
    if (parent != null) await open(parent, pushHistory: false);
  }

  bool goBack() {
    if (state.selecting) {
      clearSelection();
      return true;
    }
    if (state.filter.isNotEmpty) {
      state = state.copyWith(filter: '');
      return true;
    }
    if (_back.isNotEmpty) {
      final previous = _back.removeLast();
      open(previous, pushHistory: false);
      return true;
    }
    if (state.parent != null) {
      up();
      return true;
    }
    return false;
  }

  void setFilter(String value) => state = state.copyWith(filter: value);

  void toggle(String path) {
    final next = {...state.selection};
    if (!next.remove(path)) next.add(path);
    state = state.copyWith(selection: next);
  }

  void selectAll() => state = state.copyWith(selection: state.visible.map((e) => e.path).toSet());

  void clearSelection() => state = state.copyWith(selection: {});

  void copySelection({required bool cut}) {
    state = state.copyWith(clipboard: state.selection.toList(), cut: cut, selection: {});
  }

  void copyPaths(List<String> paths, {required bool cut}) {
    state = state.copyWith(clipboard: paths, cut: cut, selection: {});
  }

  void clearClipboard() => state = state.copyWith(clipboard: const []);

  Future<void> paste({String conflict = 'rename'}) async {
    if (state.clipboard.isEmpty) return;
    final sources = state.clipboard;
    final move = state.cut;
    state = state.copyWith(opLabel: move ? 'Memindahkan' : 'Menyalin');
    try {
      await _api.fs.copy(sources, state.path, move: move, conflict: conflict, onProgress: (e) => state = state.copyWith(op: e));
      if (move) state = state.copyWith(clipboard: const []);
    } finally {
      state = state.copyWith(clearOp: true);
      await refresh(silent: true);
    }
  }

  Future<void> delete(List<String> paths) async {
    final settings = _ref.read(settingsProvider);
    await _api.fs.delete(paths, trash: settings.useTrash);
    state = state.copyWith(selection: {});
    await refresh(silent: true);
  }

  Future<void> rename(FileEntry entry, String name) async {
    await _api.fs.rename(entry.path, joinPath(parentOf(entry.path), name));
    state = state.copyWith(selection: {});
    await refresh(silent: true);
  }

  Future<void> newFolder(String name) async {
    await _api.fs.mkdir(joinPath(state.path, name));
    await refresh(silent: true);
  }

  Future<void> newFile(String name) async {
    await _api.fs.createFile(joinPath(state.path, name));
    await refresh(silent: true);
  }

  Future<void> compress(List<String> sources, String output, String format) async {
    state = state.copyWith(opLabel: 'Mengompres');
    try {
      await _api.fs.compress(sources, output, format, onProgress: (e) => state = state.copyWith(op: e));
    } finally {
      state = state.copyWith(clearOp: true, selection: {});
      await refresh(silent: true);
    }
  }

  Future<void> extract(String archive, String dest, {List<String>? only}) async {
    state = state.copyWith(opLabel: 'Mengekstrak');
    try {
      await _api.fs.extract(archive, dest, only: only, onProgress: (e) => state = state.copyWith(op: e));
    } finally {
      state = state.copyWith(clearOp: true, selection: {});
      await refresh(silent: true);
    }
  }

  Future<void> applySettingsChange() => refresh(silent: true);

  @override
  void dispose() {
    _watch?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

final filesProvider = StateNotifierProvider<FilesNotifier, FilesState>((ref) => FilesNotifier(ref));
