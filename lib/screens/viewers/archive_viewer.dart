import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/file_icons.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import 'viewer_common.dart';

class _Node {
  _Node(this.name, this.path, this.isDir, this.size, this.packed, this.modified);

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int packed;
  final int modified;
}

class ArchiveViewerScreen extends ConsumerStatefulWidget {
  const ArchiveViewerScreen({super.key, required this.entry});

  final FileEntry entry;

  @override
  ConsumerState<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends ConsumerState<ArchiveViewerScreen> {
  List<Map<String, dynamic>> _all = const [];
  String _prefix = '';
  bool _loading = true;
  String? _error;
  final Set<String> _selected = {};
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await ref.read(apiProvider).fs.archiveList(widget.entry.path);
      if (!mounted) return;
      setState(() {
        _all = entries;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = OnyxError.from(error).message;
          _loading = false;
        });
      }
    }
  }

  List<_Node> get _children {
    final seen = <String, _Node>{};
    for (final raw in _all) {
      final full = (raw['name'] as String).replaceAll('\\', '/');
      if (!full.startsWith(_prefix) || full == _prefix) continue;
      final rest = full.substring(_prefix.length);
      final slash = rest.indexOf('/');
      final name = slash < 0 ? rest : rest.substring(0, slash);
      if (name.isEmpty) continue;
      final isDir = slash >= 0 || (raw['isDir'] as bool? ?? false);
      final path = isDir ? '$_prefix$name/' : full;
      final existing = seen[path];
      final size = ((raw['size'] ?? 0) as num).toInt();
      final packed = ((raw['packed'] ?? 0) as num).toInt();
      if (existing == null) {
        seen[path] = _Node(name, path, isDir, isDir ? 0 : size, packed, ((raw['modified'] ?? 0) as num).toInt());
      } else if (isDir) {
        seen[path] = _Node(name, path, true, existing.size + size, existing.packed + packed, existing.modified);
      }
    }
    final list = seen.values.toList();
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  bool _back() {
    if (_selected.isNotEmpty) {
      setState(_selected.clear);
      return true;
    }
    if (_prefix.isEmpty) return false;
    final trimmed = _prefix.substring(0, _prefix.length - 1);
    final cut = trimmed.lastIndexOf('/');
    setState(() => _prefix = cut < 0 ? '' : trimmed.substring(0, cut + 1));
    return true;
  }

  Future<void> _preview(_Node node) async {
    final api = ref.read(apiProvider);
    try {
      final bytes = await api.fs.archiveRead(widget.entry.path, node.path);
      if (!mounted) return;
      final looksText = !bytes.take(4096).contains(0);
      await showSheet<void>(
        context,
        builder: (ctx) => SheetFrame(
          title: node.name,
          child: looksText ? _TextPreview(bytes: bytes, truncated: bytes.length < node.size) : _BinaryNote(node: node),
        ),
      );
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  Future<void> _extract(List<String>? only) async {
    final suggested = baseName(widget.entry.path).split('.').first;
    final name = await promptText(
      context,
      title: only == null ? 'Ekstrak semua ke folder' : 'Ekstrak ${only.length} item ke folder',
      initial: suggested,
      confirmLabel: 'Ekstrak',
      validator: (v) => v.contains('/') ? 'Nama folder tidak boleh memuat garis miring' : null,
    );
    if (name == null || !mounted) return;
    final dest = joinPath(parentOf(widget.entry.path), name);
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      await ref.read(apiProvider).fs.extract(
            widget.entry.path,
            dest,
            only: only,
            onProgress: (event) {
              if (mounted) setState(() => _progress = event.ratio);
            },
          );
      if (mounted) {
        toast(context, 'Diekstrak ke $name');
        setState(_selected.clear);
      }
    } catch (error) {
      if (mounted) toastError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final nodes = _loading || _error != null ? const <_Node>[] : _children;
    final totalSize = _all.fold<int>(0, (sum, e) => sum + ((e['size'] ?? 0) as num).toInt());
    return PopScope(
      canPop: _prefix.isEmpty && _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: ViewerScaffold(
        path: '${widget.entry.path}${_prefix.isEmpty ? '' : '!/$_prefix'}',
        actions: [
          if (_selected.isNotEmpty)
            IconButton(
              tooltip: 'Ekstrak yang dipilih',
              onPressed: _busy ? null : () => _extract(_selected.toList()),
              icon: const FaIcon(FontAwesomeIcons.boxOpen, size: 17),
            )
          else
            IconButton(
              tooltip: 'Ekstrak semua',
              onPressed: _busy || _all.isEmpty ? null : () => _extract(null),
              icon: const FaIcon(FontAwesomeIcons.boxOpen, size: 17),
            ),
        ],
        body: Column(
          children: [
            if (_busy) LinearProgressIndicator(value: _progress <= 0 ? null : _progress, minHeight: 2, color: p.accent, backgroundColor: p.surfaceAlt),
            Expanded(
              child: _loading
                  ? const Loading(label: 'Membaca arsip')
                  : _error != null
                      ? ErrorState(title: 'Arsip tidak dapat dibaca', message: _error!, onRetry: _load)
                      : nodes.isEmpty
                          ? const EmptyState(icon: FontAwesomeIcons.boxOpen, title: 'Folder kosong', message: 'Tidak ada isi pada jalur ini.')
                          : ListView.builder(
                              itemCount: nodes.length,
                              itemBuilder: (context, i) {
                                final n = nodes[i];
                                final selected = _selected.contains(n.path);
                                final kind = n.isDir ? FileKind.folder : kindOf(isDir: false, ext: extensionOf(n.name), name: n.name);
                                return InkWell(
                                  onTap: () {
                                    if (_selected.isNotEmpty) {
                                      setState(() => selected ? _selected.remove(n.path) : _selected.add(n.path));
                                    } else if (n.isDir) {
                                      setState(() => _prefix = n.path);
                                    } else {
                                      _preview(n);
                                    }
                                  },
                                  onLongPress: () => setState(() => selected ? _selected.remove(n.path) : _selected.add(n.path)),
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: 56),
                                    padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                                    color: selected ? p.accentMuted.withValues(alpha: 0.35) : null,
                                    child: Row(
                                      children: [
                                        SizedBox(width: 28, child: FaIcon(iconFor(kind), size: 18, color: colorFor(kind, p))),
                                        const SizedBox(width: Sp.x3),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                                              Text(
                                                [
                                                  formatBytes(n.size),
                                                  if (!n.isDir && n.packed > 0 && n.size > 0) 'terkompresi ${percent(100 - n.packed * 100 / n.size)}',
                                                  if (n.modified > 0) formatDate(n.modified),
                                                ].join('  ·  '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: context.text.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (selected) FaIcon(FontAwesomeIcons.circleCheck, size: 16, color: p.accent),
                                        if (!selected && n.isDir) FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: p.textMuted),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
        bottom: _all.isEmpty
            ? null
            : Material(
                color: p.surface,
                child: SafeArea(
                  top: false,
                  child: Container(
                    height: 44,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                    child: Text(
                      _selected.isNotEmpty
                          ? '${_selected.length} dipilih'
                          : '${_all.length} entri  ·  ${formatBytes(totalSize)} tidak terkompresi',
                      style: OnyxFonts.mono(size: 12, color: p.textSecondary),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.bytes, required this.truncated});

  final Uint8List bytes;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = utf8.decode(bytes, allowMalformed: true);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Sp.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.x3),
              child: Text('Pratinjau dipotong pada ${formatBytes(bytes.length)} pertama.', style: context.text.bodySmall?.copyWith(color: p.warning)),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Sp.x3),
            decoration: BoxDecoration(color: p.terminalBg, borderRadius: Rd.c, border: Border.all(color: p.border)),
            child: SelectableText(text, style: OnyxFonts.mono(size: 12, color: const Color(0xFFD4D4D4), height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _BinaryNote extends StatelessWidget {
  const _BinaryNote({required this.node});

  final _Node node;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Sp.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Berkas biner, ${formatBytes(node.size)}.', style: context.text.bodyMedium),
          const SizedBox(height: Sp.x2),
          Text('Pratinjau hanya untuk teks. Ekstrak berkas ini untuk membukanya.', style: context.text.bodySmall),
        ],
      ),
    );
  }
}
