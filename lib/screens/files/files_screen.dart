import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/file_icons.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/files_state.dart';
import '../../state/settings.dart';
import '../../state/nav.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../viewers/viewer_router.dart';
import 'file_sheets.dart';
import 'search_screen.dart';
import 'trash_screen.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> with WidgetsBindingObserver {
  bool _grid = false;
  bool _filtering = false;
  final TextEditingController _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tabBackProvider)[AppTab.files] = _handleBack;
      ref.read(filesProvider.notifier).boot();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _filter.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !ref.read(filesProvider).hasAccess) {
      ref.read(filesProvider.notifier).recheckAccess();
    }
  }

  bool _handleBack() {
    if (_filtering) {
      setState(() => _filtering = false);
      _filter.clear();
      ref.read(filesProvider.notifier).setFilter('');
      return true;
    }
    return ref.read(filesProvider.notifier).goBack();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingFilesPathProvider, (previous, next) {
      if (next == null) return;
      ref.read(pendingFilesPathProvider.notifier).state = null;
      ref.read(filesProvider.notifier).open(next);
    });
    final state = ref.watch(filesProvider);
    final notifier = ref.read(filesProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final p = context.palette;

    final PreferredSizeWidget bar = state.selecting
        ? _SelectionBar(state: state)
        : OnyxAppBar(
            automaticLeading: false,
            title: 'Berkas',
            ribbon: state.path.isEmpty ? null : PathRibbon(path: state.path, onSegment: notifier.open),
            actions: [
              IconButton(
                tooltip: 'Cari',
                onPressed: state.path.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchScreen(root: state.path))),
                icon: const FaIcon(FontAwesomeIcons.magnifyingGlass, size: 17),
              ),
              IconButton(
                tooltip: _grid ? 'Tampilan daftar' : 'Tampilan kisi',
                onPressed: () => setState(() => _grid = !_grid),
                icon: FaIcon(_grid ? FontAwesomeIcons.list : FontAwesomeIcons.tableCells, size: 17),
              ),
              _MoreMenu(state: state, onFilter: () => setState(() => _filtering = true)),
            ],
          );

    return Scaffold(
      appBar: bar,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (!state.hasAccess) _AccessBanner(onOpen: () async {
              await ref.read(apiProvider).fs.openAccessSettings();
            }),
            if (_filtering && !state.selecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x2),
                child: TextField(
                  controller: _filter,
                  autofocus: true,
                  onChanged: notifier.setFilter,
                  decoration: InputDecoration(
                    hintText: 'Saring nama di folder ini',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _filtering = false);
                        _filter.clear();
                        notifier.setFilter('');
                      },
                      icon: const FaIcon(FontAwesomeIcons.xmark, size: 14),
                    ),
                  ),
                ),
              ),
            _RootsStrip(state: state, onPick: (root) {
              ref.read(settingsProvider.notifier).update((s) => s.copyWith(lastRoot: root.id));
              notifier.open(root.path);
            }),
            if (state.op != null || state.opLabel != null) _OpBanner(state: state),
            Expanded(child: _body(context, state, settings)),
            if (state.clipboard.isNotEmpty) _PasteBar(state: state),
          ],
        ),
      ),
      floatingActionButton: state.selecting || state.path.isEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Baru',
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: Rd.d),
              onPressed: () => _newSheet(context),
              child: const FaIcon(FontAwesomeIcons.plus, size: 18),
            ),
    );
  }

  Widget _body(BuildContext context, FilesState state, Settings settings) {
    final notifier = ref.read(filesProvider.notifier);
    if (state.loading && state.entries.isEmpty) return const Loading();
    if (state.error != null && state.entries.isEmpty) {
      return ErrorState(message: state.error!, onRetry: notifier.refresh);
    }
    final items = state.visible;
    if (items.isEmpty) {
      return EmptyState(
        icon: state.filter.isNotEmpty ? FontAwesomeIcons.magnifyingGlass : FontAwesomeIcons.folderOpen,
        title: state.filter.isNotEmpty ? 'Tidak ada yang cocok' : 'Folder ini kosong',
        message: state.filter.isNotEmpty
            ? 'Tidak ada nama yang memuat "${state.filter}".'
            : (state.hiddenCount > 0 ? '${state.hiddenCount} item tersembunyi. Aktifkan "Tampilkan berkas tersembunyi" di menu.' : 'Tekan tombol + untuk membuat folder atau berkas.'),
      );
    }
    final list = _grid ? _gridView(context, state, items) : _listView(context, state, items);
    return RefreshIndicator(onRefresh: notifier.refresh, child: list);
  }

  Widget _listView(BuildContext context, FilesState state, List<FileEntry> items) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        return FileTile(
          entry: e,
          selected: state.selection.contains(e.path),
          selecting: state.selecting,
          onTap: () => _tap(e, state),
          onLong: () => ref.read(filesProvider.notifier).toggle(e.path),
          onMore: () => showFileActions(context, ref, e),
        );
      },
    );
  }

  Widget _gridView(BuildContext context, FilesState state, List<FileEntry> items) {
    final width = MediaQuery.sizeOf(context).width;
    final cross = (width / 120).floor().clamp(3, 8);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cross, mainAxisSpacing: Sp.x2, crossAxisSpacing: Sp.x2, childAspectRatio: 0.92),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        final selected = state.selection.contains(e.path);
        final p = context.palette;
        final kind = kindOf(isDir: e.isDir, ext: e.extension, mime: e.mime, isLink: e.isLink, name: e.name);
        return OnyxCard(
          selected: selected,
          padding: const EdgeInsets.all(Sp.x2),
          onTap: () => _tap(e, state),
          onLongPress: () => ref.read(filesProvider.notifier).toggle(e.path),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(iconFor(kind), size: 28, color: colorFor(kind, p)),
              const SizedBox(height: Sp.x2),
              Text(e.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: p.text)),
              if (!e.isDir) Text(formatBytes(e.size), style: context.text.labelSmall),
            ],
          ),
        );
      },
    );
  }

  void _tap(FileEntry e, FilesState state) {
    final notifier = ref.read(filesProvider.notifier);
    if (state.selecting) {
      notifier.toggle(e.path);
      return;
    }
    if (e.isDir) {
      notifier.open(e.path);
    } else {
      openLocalFile(context, ref, e, siblings: state.entries.where((x) => !x.isDir).toList());
    }
  }

  void _newSheet(BuildContext context) {
    final notifier = ref.read(filesProvider.notifier);
    showActionSheet(
      context,
      title: 'Buat baru',
      actions: [
        SheetAction('Folder', FontAwesomeIcons.folderPlus, () async {
          final name = await promptText(context, title: 'Folder baru', hint: 'Nama folder', validator: validateName);
          if (name != null && context.mounted) await runGuarded(context, () => notifier.newFolder(name));
        }),
        SheetAction('Berkas kosong', FontAwesomeIcons.fileCirclePlus, () async {
          final name = await promptText(context, title: 'Berkas baru', hint: 'contoh.txt', validator: validateName);
          if (name != null && context.mounted) await runGuarded(context, () => notifier.newFile(name));
        }),
      ],
    );
  }
}

String? validateName(String value) {
  if (value.isEmpty) return 'Nama tidak boleh kosong';
  if (value.contains('/')) return 'Nama tidak boleh memuat garis miring';
  if (value == '.' || value == '..') return 'Nama tidak valid';
  if (value.length > 255) return 'Nama terlalu panjang';
  return null;
}

class FileTile extends StatelessWidget {
  const FileTile({super.key, required this.entry, required this.selected, required this.selecting, required this.onTap, required this.onLong, required this.onMore});

  final FileEntry entry;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLong;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kind = kindOf(isDir: entry.isDir, ext: entry.extension, mime: entry.mime, isLink: entry.isLink, name: entry.name);
    final sub = entry.isDir ? formatDate(entry.modified) : '${formatBytes(entry.size)}  ${formatDate(entry.modified)}';
    return Semantics(
      label: '${entry.isDir ? 'Folder' : 'Berkas'} ${entry.name}',
      selected: selected,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLong,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
          color: selected ? p.accentMuted.withValues(alpha: p.isDark ? 0.45 : 0.6) : null,
          child: Row(
            children: [
              if (selected)
                Container(width: 2, height: 28, margin: const EdgeInsets.only(right: Sp.x2), color: p.accent)
              else
                const SizedBox(width: 0),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.surface, borderRadius: Rd.c, border: Border.all(color: p.border)),
                child: Center(child: FaIcon(iconFor(kind), size: 17, color: colorFor(kind, p))),
              ),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: entry.hidden ? p.textSecondary : p.text)),
                    const SizedBox(height: 2),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              if (selecting)
                Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 22, color: selected ? p.accent : p.textMuted)
              else
                IconButton(
                  tooltip: 'Opsi ${entry.name}',
                  onPressed: onMore,
                  icon: FaIcon(FontAwesomeIcons.ellipsisVertical, size: 15, color: p.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RootsStrip extends StatelessWidget {
  const _RootsStrip({required this.state, required this.onPick});

  final FilesState state;
  final ValueChanged<StorageRoot> onPick;

  @override
  Widget build(BuildContext context) {
    if (state.roots.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
        children: [
          for (final root in state.roots)
            Builder(builder: (context) {
              final active = state.path == root.path || state.path.startsWith('${root.path}/') && root.path != '/' ;
              return GestureDetector(
                onTap: () => onPick(root),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      Text(root.title, maxLines: 1, style: context.text.labelMedium?.copyWith(color: active ? p.text : p.textSecondary, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
                      const SizedBox(height: 6),
                      CaretMark(active: active, width: 16),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AccessBanner extends StatelessWidget {
  const _AccessBanner({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x2),
      padding: const EdgeInsets.all(Sp.x3),
      decoration: BoxDecoration(color: p.warning.withValues(alpha: 0.12), borderRadius: Rd.c, border: Border.all(color: p.warning.withValues(alpha: 0.5))),
      child: Row(
        children: [
          Expanded(
            child: Text('Onyx belum boleh membaca semua berkas. Beri izin "Akses semua berkas" agar penyimpanan internal terbuka.', style: context.text.bodySmall?.copyWith(color: p.text)),
          ),
          const SizedBox(width: Sp.x2),
          OnyxButton(label: 'Buka', compact: true, kind: OnyxButtonKind.secondary, onPressed: onOpen),
        ],
      ),
    );
  }
}

class _OpBanner extends ConsumerWidget {
  const _OpBanner({required this.state});

  final FilesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final op = state.op;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x4, Sp.x2),
      padding: const EdgeInsets.all(Sp.x3),
      decoration: BoxDecoration(color: p.surface, borderRadius: Rd.c, border: Border.all(color: p.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${state.opLabel ?? 'Memproses'}${op == null || op.current.isEmpty ? '' : ' ${op.current}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: p.text))),
              if (op != null) TextButton(onPressed: () => ref.read(apiProvider).fs.cancelOp(op.id), child: const Text('Batal')),
            ],
          ),
          RatioBar(value: op?.ratio ?? 0),
        ],
      ),
    );
  }
}

class _PasteBar extends ConsumerWidget {
  const _PasteBar({required this.state});

  final FilesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final notifier = ref.read(filesProvider.notifier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: Row(
        children: [
          FaIcon(state.cut ? FontAwesomeIcons.scissors : FontAwesomeIcons.copy, size: 14, color: p.textSecondary),
          const SizedBox(width: Sp.x3),
          Expanded(child: Text('${state.clipboard.length} item ${state.cut ? 'dipotong' : 'disalin'}', style: context.text.bodySmall?.copyWith(color: p.text))),
          TextButton(onPressed: notifier.clearClipboard, child: const Text('Batal')),
          const SizedBox(width: Sp.x1),
          OnyxButton(
            label: 'Tempel di sini',
            compact: true,
            icon: FontAwesomeIcons.paste,
            onPressed: state.op != null || state.opLabel != null ? null : () => runGuarded(context, () => notifier.paste()),
          ),
        ],
      ),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.state, required this.onFilter});

  final FilesState state;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(filesProvider.notifier);
    Future<void> change(Settings Function(Settings s) fn) async {
      await ref.read(settingsProvider.notifier).update(fn);
      await notifier.applySettingsChange();
    }

    return PopupMenuButton<String>(
      tooltip: 'Menu berkas',
      icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 17),
      onSelected: (value) async {
        switch (value) {
          case 'filter':
            onFilter();
          case 'hidden':
            await change((s) => s.copyWith(showHidden: !s.showHidden));
          case 'name':
          case 'size':
          case 'date':
          case 'type':
            await change((s) => s.copyWith(sort: value, ascending: s.sort == value ? !s.ascending : true));
          case 'selectAll':
            notifier.selectAll();
          case 'terminal':
            ref.read(pendingTerminalCwdProvider.notifier).state = state.path;
            ref.read(tabProvider.notifier).state = AppTab.terminal;
          case 'bookmark':
            await runGuarded(context, () async {
              await ref.read(apiProvider).fs.addBookmark('path', state.path);
            }, success: 'Folder ditambahkan ke favorit');
          case 'bookmarks':
            await showBookmarks(context, ref);
          case 'trash':
            if (context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TrashScreen()));
            await notifier.refresh(silent: true);
          case 'duplicates':
            if (context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DuplicatesScreen(root: state.path)));
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'filter', child: Text('Saring nama')),
        PopupMenuItem(value: 'hidden', child: Text(settings.showHidden ? 'Sembunyikan berkas tersembunyi' : 'Tampilkan berkas tersembunyi')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'name', child: Text('Urut nama${settings.sort == 'name' ? (settings.ascending ? ' (naik)' : ' (turun)') : ''}')),
        PopupMenuItem(value: 'size', child: Text('Urut ukuran${settings.sort == 'size' ? (settings.ascending ? ' (naik)' : ' (turun)') : ''}')),
        PopupMenuItem(value: 'date', child: Text('Urut tanggal${settings.sort == 'date' ? (settings.ascending ? ' (naik)' : ' (turun)') : ''}')),
        PopupMenuItem(value: 'type', child: Text('Urut jenis${settings.sort == 'type' ? (settings.ascending ? ' (naik)' : ' (turun)') : ''}')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'selectAll', child: Text('Pilih semua')),
        const PopupMenuItem(value: 'terminal', child: Text('Buka terminal di sini')),
        const PopupMenuItem(value: 'bookmark', child: Text('Tambah ke favorit')),
        const PopupMenuItem(value: 'bookmarks', child: Text('Favorit')),
        const PopupMenuItem(value: 'duplicates', child: Text('Cari berkas ganda')),
        const PopupMenuItem(value: 'trash', child: Text('Sampah')),
      ],
    );
  }
}

class _SelectionBar extends ConsumerWidget implements PreferredSizeWidget {
  const _SelectionBar({required this.state});

  final FilesState state;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(filesProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final selected = state.selected;
    return OnyxAppBar(
      automaticLeading: false,
      leading: IconButton(tooltip: 'Batal pilih', onPressed: notifier.clearSelection, icon: const FaIcon(FontAwesomeIcons.xmark, size: 18)),
      title: '${state.selection.length} dipilih',
      actions: [
        IconButton(tooltip: 'Salin', onPressed: () => notifier.copySelection(cut: false), icon: const FaIcon(FontAwesomeIcons.copy, size: 17)),
        IconButton(tooltip: 'Potong', onPressed: () => notifier.copySelection(cut: true), icon: const FaIcon(FontAwesomeIcons.scissors, size: 17)),
        IconButton(
          tooltip: 'Hapus',
          onPressed: () async {
            final ok = !settings.confirmDelete ||
                await confirm(
                  context,
                  title: settings.useTrash ? 'Pindahkan ke sampah?' : 'Hapus permanen?',
                  message: '${selected.length} item akan ${settings.useTrash ? 'dipindahkan ke sampah' : 'dihapus dan tidak bisa dipulihkan'}.',
                  confirmLabel: settings.useTrash ? 'Pindahkan' : 'Hapus',
                  danger: true,
                );
            if (ok && context.mounted) await runGuarded(context, () => notifier.delete(state.selection.toList()));
          },
          icon: const FaIcon(FontAwesomeIcons.trashCan, size: 17),
        ),
        PopupMenuButton<String>(
          icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 17),
          onSelected: (value) async {
            switch (value) {
              case 'all':
                notifier.selectAll();
              case 'compress':
                await compressDialog(context, ref, selected.map((e) => e.path).toList());
              case 'rename':
                if (selected.length == 1) await renameDialog(context, ref, selected.first);
              case 'props':
                if (selected.length == 1) await showProperties(context, ref, selected.first.path);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'all', child: Text('Pilih semua')),
            const PopupMenuItem(value: 'compress', child: Text('Kompres')),
            if (selected.length == 1) const PopupMenuItem(value: 'rename', child: Text('Ganti nama')),
            if (selected.length == 1) const PopupMenuItem(value: 'props', child: Text('Properti')),
          ],
        ),
      ],
    );
  }
}

void copyText(BuildContext context, String text, {String message = 'Disalin'}) {
  Clipboard.setData(ClipboardData(text: text));
  toast(context, message);
}
