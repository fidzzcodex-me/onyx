import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/file_icons.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/nav.dart';
import '../../state/providers.dart';
import '../../state/sftp_state.dart';
import '../../state/terminal_state.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../files/files_screen.dart';
import '../viewers/viewer_router.dart';
import 'transfers_screen.dart';

class RemoteBrowserScreen extends ConsumerStatefulWidget {
  const RemoteBrowserScreen({super.key, required this.sessionId, required this.profile, required this.home});

  final String sessionId;
  final ConnProfile profile;
  final String home;

  @override
  ConsumerState<RemoteBrowserScreen> createState() => _RemoteBrowserScreenState();
}

class _RemoteBrowserScreenState extends ConsumerState<RemoteBrowserScreen> {
  String _path = '';
  List<FileEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _selected = {};
  bool _showHidden = false;
  String _filter = '';
  bool _filtering = false;

  @override
  void initState() {
    super.initState();
    _open(widget.profile.initialPath?.isNotEmpty == true ? widget.profile.initialPath! : widget.home);
  }

  @override
  void dispose() {
    ref.read(apiProvider).sftp.disconnect(widget.sessionId).catchError((Object _) {});
    super.dispose();
  }

  Future<void> _open(String path, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final listing = await ref.read(apiProvider).sftp.list(widget.sessionId, path);
      if (!mounted) return;
      setState(() {
        _path = listing.path;
        _entries = listing.entries;
        _selected.clear();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (silent || _path.isNotEmpty) {
        setState(() => _loading = false);
        toastError(context, error);
      } else {
        setState(() {
          _loading = false;
          _error = OnyxError.from(error).message;
        });
      }
    }
  }

  String? get _parent {
    if (_path.isEmpty || _path == '/') return null;
    final trimmed = _path.endsWith('/') ? _path.substring(0, _path.length - 1) : _path;
    final cut = trimmed.lastIndexOf('/');
    return cut <= 0 ? '/' : trimmed.substring(0, cut);
  }

  List<FileEntry> get _visible {
    var list = _showHidden ? _entries : _entries.where((e) => !e.hidden).toList();
    if (_filter.isNotEmpty) {
      final needle = _filter.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(needle)).toList();
    }
    return list;
  }

  Future<void> _tap(FileEntry e) async {
    if (_selected.isNotEmpty) {
      setState(() => _selected.contains(e.path) ? _selected.remove(e.path) : _selected.add(e.path));
      return;
    }
    if (e.isDir) {
      await _open(e.path);
      return;
    }
    final kind = kindOf(isDir: false, ext: e.extension.toLowerCase(), mime: e.mime, name: e.name);
    final editable = (kind == FileKind.code || kind == FileKind.text) && e.size <= 2 * 1024 * 1024;
    if (editable) {
      await openRemoteText(context, sessionId: widget.sessionId, path: e.path, profile: widget.profile);
      return;
    }
    await _actions(e);
  }

  Future<void> _download(List<String> remotes) async {
    final dir = ref.read(settingsProvider).downloadDir;
    await runGuarded(context, () async {
      for (final r in remotes) {
        await ref.read(apiProvider).sftp.download(widget.sessionId, r, dir);
      }
      await ref.read(transfersProvider.notifier).refresh();
    }, success: remotes.length == 1 ? 'Unduhan ditambahkan ke antrean' : '${remotes.length} unduhan ditambahkan ke antrean');
    if (mounted) setState(_selected.clear);
  }

  Future<void> _upload({bool folder = false}) async {
    final api = ref.read(apiProvider).sftp;
    try {
      final List<String> picked;
      if (folder) {
        final dir = await FilePicker.platform.getDirectoryPath();
        picked = dir == null ? const [] : [dir];
      } else {
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        picked = result?.paths.whereType<String>().toList() ?? const [];
      }
      if (picked.isEmpty || !mounted) return;
      var count = 0;
      for (final path in picked) {
        count += await api.upload(widget.sessionId, path, _path);
      }
      await ref.read(transfersProvider.notifier).refresh();
      if (mounted) toast(context, '$count berkas ditambahkan ke antrean unggah');
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  Future<void> _mkdir() async {
    final name = await promptText(context, title: 'Folder baru', confirmLabel: 'Buat', validator: validateName);
    if (name == null || !mounted) return;
    await runGuarded(context, () async {
      await ref.read(apiProvider).sftp.mkdir(widget.sessionId, joinPath(_path, name));
      await _open(_path, silent: true);
    });
  }

  Future<void> _rename(FileEntry e) async {
    final name = await promptText(context, title: 'Ganti nama', initial: e.name, confirmLabel: 'Ganti', validator: validateName);
    if (name == null || name == e.name || !mounted) return;
    await runGuarded(context, () async {
      await ref.read(apiProvider).sftp.rename(widget.sessionId, e.path, joinPath(parentOf(e.path), name));
      await _open(_path, silent: true);
    });
  }

  Future<void> _delete(List<FileEntry> items) async {
    final ok = await confirm(
      context,
      title: items.length == 1 ? 'Hapus "${items.first.name}"?' : 'Hapus ${items.length} item?',
      message: 'Penghapusan di server bersifat permanen dan tidak melewati sampah.',
      confirmLabel: 'Hapus',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runGuarded(context, () async {
      for (final e in items) {
        await ref.read(apiProvider).sftp.delete(widget.sessionId, e.path, recursive: true);
      }
      await _open(_path, silent: true);
    });
  }

  Future<void> _chmod(FileEntry e) async {
    final value = await promptText(
      context,
      title: 'Izin ${e.name}',
      hint: 'Oktal, contoh 644',
      initial: '644',
      confirmLabel: 'Terapkan',
      keyboard: TextInputType.number,
      validator: (v) => RegExp(r'^[0-7]{3,4}$').hasMatch(v) ? null : 'Masukkan 3 atau 4 digit oktal, contoh 755',
    );
    if (value == null || !mounted) return;
    await runGuarded(context, () async {
      await ref.read(apiProvider).sftp.chmod(widget.sessionId, e.path, int.parse(value, radix: 8));
      await _open(_path, silent: true);
    }, success: 'Izin diubah ke $value');
  }

  Future<void> _actions(FileEntry e) {
    return showActionSheet(
      context,
      title: e.name,
      subtitle: e.isDir ? 'Folder' : '${formatBytes(e.size)}  ·  ${e.mode}',
      actions: [
        SheetAction('Unduh', FontAwesomeIcons.download, () => _download([e.path]), subtitle: ref.read(settingsProvider).downloadDir),
        if (!e.isDir) SheetAction('Buka sebagai teks', FontAwesomeIcons.fileLines, () => openRemoteText(context, sessionId: widget.sessionId, path: e.path, profile: widget.profile)),
        SheetAction('Ganti nama', FontAwesomeIcons.pen, () => _rename(e)),
        SheetAction('Ubah izin', FontAwesomeIcons.lock, () => _chmod(e)),
        SheetAction('Salin jalur', FontAwesomeIcons.link, () => copyText(context, e.path, message: 'Jalur disalin')),
        SheetAction('Hapus', FontAwesomeIcons.trashCan, () => _delete([e]), danger: true),
      ],
    );
  }

  Future<void> _sync() async {
    final local = await FilePicker.platform.getDirectoryPath();
    if (local == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SyncScreen(sessionId: widget.sessionId, local: local, remote: _path)));
    if (mounted) _open(_path, silent: true);
  }

  Future<void> _openTerminal() async {
    try {
      await ref.read(terminalProvider.notifier).newSsh(widget.profile.id);
      ref.read(tabProvider.notifier).state = AppTab.terminal;
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final transfers = ref.watch(transfersProvider);
    final items = _visible;
    final parent = _parent;
    return PopScope(
      canPop: parent == null && _selected.isEmpty && !_filtering,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selected.isNotEmpty) {
          setState(_selected.clear);
        } else if (_filtering) {
          setState(() {
            _filtering = false;
            _filter = '';
          });
        } else if (parent != null) {
          _open(parent);
        }
      },
      child: Scaffold(
        appBar: OnyxAppBar(
          title: widget.profile.name,
          ribbon: PathRibbon(path: _path.isEmpty ? '/' : _path, prefix: '${widget.profile.username}@${widget.profile.host}', onSegment: _open),
          actions: [
            IconButton(tooltip: 'Saring', onPressed: () => setState(() => _filtering = !_filtering), icon: const FaIcon(FontAwesomeIcons.magnifyingGlass, size: 16)),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Transfer',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransfersScreen())),
                  icon: const FaIcon(FontAwesomeIcons.arrowRightArrowLeft, size: 16),
                ),
                if (transfers.activeCount > 0)
                  Positioned(
                    right: 6,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(8)),
                      child: Text('${transfers.activeCount}', style: OnyxFonts.mono(size: 10, color: p.onAccent, weight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Menu server',
              color: p.elevated,
              icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 17),
              onSelected: (v) {
                switch (v) {
                  case 'mkdir':
                    _mkdir();
                  case 'upload_folder':
                    _upload(folder: true);
                  case 'sync':
                    _sync();
                  case 'hidden':
                    setState(() => _showHidden = !_showHidden);
                  case 'refresh':
                    _open(_path);
                  case 'terminal':
                    _openTerminal();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'mkdir', child: Text('Folder baru')),
                const PopupMenuItem(value: 'upload_folder', child: Text('Unggah folder')),
                const PopupMenuItem(value: 'sync', child: Text('Sinkronkan folder')),
                if (widget.profile.isSsh) const PopupMenuItem(value: 'terminal', child: Text('Buka terminal SSH')),
                PopupMenuItem(value: 'hidden', child: Text(_showHidden ? 'Sembunyikan berkas tersembunyi' : 'Tampilkan berkas tersembunyi')),
                const PopupMenuItem(value: 'refresh', child: Text('Segarkan')),
              ],
            ),
          ],
        ),
        floatingActionButton: _selected.isNotEmpty || _loading || _error != null
            ? null
            : FloatingActionButton.extended(
                onPressed: _upload,
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
                icon: const FaIcon(FontAwesomeIcons.upload, size: 15),
                label: const Text('Unggah'),
              ),
        body: Column(
          children: [
            if (_filtering)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x2),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _filter = v),
                  decoration: const InputDecoration(hintText: 'Saring nama di folder ini'),
                ),
              ),
            if (_selected.isNotEmpty)
              Container(
                color: p.surface,
                padding: const EdgeInsets.symmetric(horizontal: Sp.x2),
                child: Row(
                  children: [
                    IconButton(tooltip: 'Batal pilih', onPressed: () => setState(_selected.clear), icon: const FaIcon(FontAwesomeIcons.xmark, size: 16)),
                    Expanded(child: Text('${_selected.length} dipilih', style: context.text.titleMedium)),
                    IconButton(tooltip: 'Unduh', onPressed: () => _download(_selected.toList()), icon: const FaIcon(FontAwesomeIcons.download, size: 16)),
                    IconButton(
                      tooltip: 'Hapus',
                      onPressed: () => _delete(_entries.where((e) => _selected.contains(e.path)).toList()),
                      icon: FaIcon(FontAwesomeIcons.trashCan, size: 16, color: p.error),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Loading(label: 'Memuat folder')
                  : _error != null
                      ? ErrorState(title: 'Tidak dapat membuka server', message: _error!, onRetry: () => _open(_path.isEmpty ? widget.home : _path))
                      : RefreshIndicator(
                          onRefresh: () => _open(_path, silent: true),
                          child: items.isEmpty
                              ? ListView(children: [
                                  SizedBox(
                                    height: 320,
                                    child: EmptyState(
                                      icon: FontAwesomeIcons.folderOpen,
                                      title: _filter.isNotEmpty ? 'Tidak ada yang cocok' : 'Folder kosong',
                                      message: _filter.isNotEmpty ? 'Ubah kata kunci saringan.' : 'Tekan Unggah untuk menambahkan berkas ke folder ini.',
                                    ),
                                  ),
                                ])
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 96),
                                  itemCount: items.length + (parent != null ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (parent != null && index == 0) {
                                      return InkWell(
                                        onTap: () => _open(parent),
                                        child: Container(
                                          constraints: const BoxConstraints(minHeight: 52),
                                          padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
                                          child: Row(children: [
                                            SizedBox(width: 28, child: FaIcon(FontAwesomeIcons.arrowTurnUp, size: 15, color: p.textMuted)),
                                            const SizedBox(width: Sp.x3),
                                            Text('..', style: OnyxFonts.mono(size: 14, color: p.textSecondary)),
                                          ]),
                                        ),
                                      );
                                    }
                                    final e = items[index - (parent != null ? 1 : 0)];
                                    final selected = _selected.contains(e.path);
                                    final kind = kindOf(isDir: e.isDir, ext: e.extension.toLowerCase(), mime: e.mime, isLink: e.isLink, name: e.name);
                                    return InkWell(
                                      onTap: () => _tap(e),
                                      onLongPress: () => setState(() => selected ? _selected.remove(e.path) : _selected.add(e.path)),
                                      child: Container(
                                        constraints: const BoxConstraints(minHeight: 60),
                                        padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                                        color: selected ? p.accentMuted.withValues(alpha: 0.35) : null,
                                        child: Row(
                                          children: [
                                            SizedBox(width: 28, child: FaIcon(iconFor(kind), size: 19, color: colorFor(kind, p))),
                                            const SizedBox(width: Sp.x3),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                                                  Text(
                                                    [if (!e.isDir) formatBytes(e.size), if (e.modified > 0) formatDate(e.modified), e.mode].where((s) => s.isNotEmpty).join('  ·  '),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: context.text.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (selected)
                                              FaIcon(FontAwesomeIcons.circleCheck, size: 17, color: p.accent)
                                            else
                                              IconButton(tooltip: 'Aksi', onPressed: () => _actions(e), icon: FaIcon(FontAwesomeIcons.ellipsisVertical, size: 15, color: p.textMuted)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key, required this.sessionId, required this.local, required this.remote});

  final String sessionId;
  final String local;
  final String remote;

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  List<Map<String, dynamic>> _diff = const [];
  bool _loading = true;
  bool _running = false;
  String? _error;
  String _mode = 'up';

  @override
  void initState() {
    super.initState();
    _compare();
  }

  Future<void> _compare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diff = await ref.read(apiProvider).sftp.compare(widget.sessionId, widget.local, widget.remote);
      if (mounted) {
        setState(() {
          _diff = diff;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = OnyxError.from(error).message;
        });
      }
    }
  }

  Future<void> _run() async {
    final ok = await confirm(
      context,
      title: 'Mulai sinkronisasi?',
      message: switch (_mode) {
        'up' => 'Berkas yang baru atau berubah di perangkat akan diunggah ke server. Tidak ada yang dihapus.',
        'down' => 'Berkas yang baru atau berubah di server akan diunduh ke perangkat. Tidak ada yang dihapus.',
        _ => 'Berkas yang lebih baru di salah satu sisi akan disalin ke sisi lainnya. Tidak ada yang dihapus.',
      },
      confirmLabel: 'Sinkronkan',
    );
    if (!ok || !mounted) return;
    setState(() => _running = true);
    try {
      final count = await ref.read(apiProvider).sftp.sync(widget.sessionId, widget.local, widget.remote, _mode);
      await ref.read(transfersProvider.notifier).refresh();
      if (mounted) {
        toast(context, '$count transfer ditambahkan ke antrean');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _running = false);
        toastError(context, error);
      }
    }
  }

  (String, Color) _label(String status, OnyxPalette p) => switch (status) {
        'only_local' => ('Hanya di perangkat', p.info),
        'only_remote' => ('Hanya di server', p.info),
        'newer_local' => ('Perangkat lebih baru', p.warning),
        'newer_remote' => ('Server lebih baru', p.warning),
        'size_diff' => ('Ukuran berbeda', p.warning),
        _ => ('Sama', p.success),
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final changed = _diff.where((e) => e['status'] != 'same').toList();
    return Scaffold(
      appBar: OnyxAppBar(title: 'Sinkronkan folder', ribbon: PathRibbon(path: widget.remote, prefix: 'server')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Sp.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lokal: ${widget.local}', style: OnyxFonts.mono(size: 12, color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Sp.x3),
                SegmentedSync(value: _mode, onChanged: (v) => setState(() => _mode = v)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Loading(label: 'Membandingkan folder')
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _compare)
                    : changed.isEmpty
                        ? const EmptyState(icon: FontAwesomeIcons.circleCheck, title: 'Sudah sama', message: 'Tidak ada perbedaan antara kedua folder.')
                        : ListView.separated(
                            itemCount: changed.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: p.divider),
                            itemBuilder: (context, i) {
                              final e = changed[i];
                              final (text, color) = _label((e['status'] ?? '') as String, p);
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x3),
                                child: Row(
                                  children: [
                                    Expanded(child: Text((e['path'] ?? '') as String, style: OnyxFonts.mono(size: 12, color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                    const SizedBox(width: Sp.x2),
                                    Pill(text, color: color),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3 + MediaQuery.paddingOf(context).bottom),
            decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
            child: Row(
              children: [
                Expanded(child: Text('${changed.length} perbedaan', style: OnyxFonts.mono(size: 12, color: p.textSecondary))),
                OnyxButton(label: 'Sinkronkan', icon: FontAwesomeIcons.arrowsRotate, loading: _running, onPressed: changed.isEmpty || _loading ? null : _run),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SegmentedSync extends StatelessWidget {
  const SegmentedSync({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Sp.x2,
      runSpacing: Sp.x2,
      children: [
        ChoiceChip(label: const Text('Unggah'), selected: value == 'up', onSelected: (_) => onChanged('up')),
        ChoiceChip(label: const Text('Unduh'), selected: value == 'down', onSelected: (_) => onChanged('down')),
        ChoiceChip(label: const Text('Dua arah'), selected: value == 'two', onSelected: (_) => onChanged('two')),
      ],
    );
  }
}
