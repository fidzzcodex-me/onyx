import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/file_icons.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/files_state.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';
import '../viewers/viewer_router.dart';
import 'file_sheets.dart';
import 'files_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.root});

  final String root;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  bool _regex = false;
  bool _case = false;
  bool _hidden = false;
  bool _busy = false;
  bool _truncated = false;
  bool _searched = false;
  String? _error;
  String? _opId;
  List<FileEntry> _results = const [];

  @override
  void dispose() {
    if (_opId != null && _busy) ref.read(apiProvider).fs.cancelOp(_opId!);
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _searched = true;
      _results = const [];
    });
    try {
      final (id, future) = await ref.read(apiProvider).fs.startSearch(widget.root, text, regex: _regex, caseSensitive: _case, hidden: _hidden);
      _opId = id;
      final done = await future;
      if (!mounted) return;
      setState(() {
        _results = asMapList(done.raw['results']).map(FileEntry.fromMap).toList();
        _truncated = done.raw['truncated'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: OnyxAppBar(title: 'Cari berkas', ribbon: PathRibbon(path: widget.root)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: OnyxField(controller: _query, label: 'Nama', hint: _regex ? 'Pola regex' : 'Bagian dari nama', autofocus: true, action: TextInputAction.search, onSubmitted: (_) => _run())),
                  const SizedBox(width: Sp.x2),
                  OnyxButton(label: _busy ? 'Berhenti' : 'Cari', kind: _busy ? OnyxButtonKind.danger : OnyxButtonKind.primary, onPressed: _busy ? () => ref.read(apiProvider).fs.cancelOp(_opId ?? '') : _run),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
              child: Row(
                children: [
                  _Chip('Regex', _regex, () => setState(() => _regex = !_regex)),
                  _Chip('Peka huruf besar', _case, () => setState(() => _case = !_case)),
                  _Chip('Termasuk tersembunyi', _hidden, () => setState(() => _hidden = !_hidden)),
                ],
              ),
            ),
            const SizedBox(height: Sp.x2),
            Expanded(
              child: Builder(builder: (context) {
                if (_busy) return const Loading(label: 'Mencari');
                if (_error != null) return ErrorState(message: _error!, title: 'Pencarian gagal');
                if (!_searched) return const EmptyState(icon: FontAwesomeIcons.magnifyingGlass, title: 'Cari di folder ini', message: 'Pencarian mencakup semua subfolder. Maksimal 1000 hasil.');
                if (_results.isEmpty) return EmptyState(icon: FontAwesomeIcons.magnifyingGlass, title: 'Tidak ditemukan', message: 'Tidak ada nama yang cocok dengan "${_query.text.trim()}".');
                return Column(
                  children: [
                    if (_truncated)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x1),
                        child: Text('Hasil dipotong di 1000. Perketat kata kunci.', style: context.text.bodySmall?.copyWith(color: p.warning)),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final e = _results[i];
                          final kind = kindOf(isDir: e.isDir, ext: e.extension, mime: e.mime, name: e.name);
                          return InkWell(
                            onTap: () {
                              if (e.isDir) {
                                ref.read(filesProvider.notifier).open(e.path);
                                Navigator.pop(context);
                              } else {
                                openLocalFile(context, ref, e);
                              }
                            },
                            onLongPress: () => showFileActions(context, ref, e),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                              child: Row(
                                children: [
                                  SizedBox(width: 28, child: FaIcon(iconFor(kind), size: 16, color: colorFor(kind, p))),
                                  const SizedBox(width: Sp.x2),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text(parentOf(e.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: OnyxFonts.mono(size: 11, color: p.textMuted)),
                                      ],
                                    ),
                                  ),
                                  if (!e.isDir) Text(formatBytes(e.size), style: context.text.bodySmall),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.on, this.onTap);

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x1),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.dialog,
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? p.accentMuted : p.surfaceAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? p.accent : p.border),
          ),
          child: Text(label, style: context.text.labelMedium?.copyWith(color: on ? p.text : p.textSecondary)),
        ),
      ),
    );
  }
}

class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key, required this.root});

  final String root;

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  bool _busy = true;
  String? _error;
  String? _opId;
  List<Map<String, dynamic>> _groups = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    if (_opId != null && _busy) ref.read(apiProvider).fs.cancelOp(_opId!);
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (id, future) = await ref.read(apiProvider).fs.startDuplicates(widget.root);
      _opId = id;
      final done = await future;
      if (mounted) setState(() => _groups = asMapList(done.raw['groups']));
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: OnyxAppBar(title: 'Berkas ganda', ribbon: PathRibbon(path: widget.root)),
      body: SafeArea(
        child: _busy
            ? const Loading(label: 'Membandingkan isi berkas')
            : _error != null
                ? ErrorState(message: _error!, onRetry: _run)
                : _groups.isEmpty
                    ? const EmptyState(icon: FontAwesomeIcons.clone, title: 'Tidak ada berkas ganda', message: 'Berkas di bawah 1 KB diabaikan. Pembanding memakai SHA-256 isi berkas.')
                    : ListView.builder(
                        padding: const EdgeInsets.all(Sp.x4),
                        itemCount: _groups.length,
                        itemBuilder: (context, i) {
                          final g = _groups[i];
                          final paths = (g['paths'] as List).cast<String>();
                          final size = (g['size'] as num).toInt();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: Sp.x3),
                            child: OnyxCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Pill('${paths.length} salinan', color: p.warning),
                                      const SizedBox(width: Sp.x2),
                                      Text('${formatBytes(size)} per berkas', style: context.text.bodySmall),
                                      const Spacer(),
                                      Text('hemat ${formatBytes(size * (paths.length - 1))}', style: context.text.labelSmall),
                                    ],
                                  ),
                                  const SizedBox(height: Sp.x2),
                                  for (final path in paths)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(path, style: OnyxFonts.mono(size: 11, color: p.textSecondary))),
                                          IconButton(
                                            tooltip: 'Hapus salinan ini',
                                            onPressed: () async {
                                              final ok = await confirm(context, title: 'Hapus salinan?', message: path, confirmLabel: 'Hapus', danger: true);
                                              if (!ok || !context.mounted) return;
                                              await runGuarded(context, () async {
                                                await ref.read(apiProvider).fs.delete([path], trash: ref.read(settingsProvider).useTrash);
                                                setState(() {
                                                  paths.remove(path);
                                                  if (paths.length < 2) _groups = List.of(_groups)..remove(g);
                                                });
                                              });
                                            },
                                            icon: FaIcon(FontAwesomeIcons.trashCan, size: 14, color: p.error),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
