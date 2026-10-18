import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/file_icons.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/files_state.dart';
import '../../state/nav.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';
import '../viewers/viewer_router.dart';
import 'files_screen.dart';

Future<void> showFileActions(BuildContext context, WidgetRef ref, FileEntry e) async {
  final notifier = ref.read(filesProvider.notifier);
  final api = ref.read(apiProvider);
  final kind = kindOf(isDir: e.isDir, ext: e.extension, mime: e.mime, isLink: e.isLink, name: e.name);
  await showActionSheet(
    context,
    title: e.name,
    subtitle: e.isDir ? e.path : '${formatBytes(e.size)}  ${e.mode}',
    actions: [
      if (!e.isDir) SheetAction('Buka', FontAwesomeIcons.arrowUpRightFromSquare, () => openLocalFile(context, ref, e)),
      if (!e.isDir && kind != FileKind.text && kind != FileKind.code)
        SheetAction('Buka sebagai teks', FontAwesomeIcons.fileLines, () => openAsText(context, ref, e)),
      if (!e.isDir) SheetAction('Penampil hex', FontAwesomeIcons.microchip, () => openAsHex(context, e)),
      if (!e.isDir) SheetAction('Buka dengan aplikasi lain', FontAwesomeIcons.upRightFromSquare, () => runGuarded(context, () => api.fs.open(e.path, chooser: true))),
      if (!e.isDir) SheetAction('Bagikan', FontAwesomeIcons.shareNodes, () => runGuarded(context, () => api.fs.share(e.path))),
      if (kind == FileKind.archive) SheetAction('Ekstrak di sini', FontAwesomeIcons.boxOpen, () => extractDialog(context, ref, e)),
      if (e.isDir)
        SheetAction('Buka terminal di sini', FontAwesomeIcons.terminal, () {
          ref.read(pendingTerminalCwdProvider.notifier).state = e.path;
          ref.read(tabProvider.notifier).state = AppTab.terminal;
        }),
      SheetAction('Salin', FontAwesomeIcons.copy, () => notifier.copyPaths([e.path], cut: false)),
      SheetAction('Potong', FontAwesomeIcons.scissors, () => notifier.copyPaths([e.path], cut: true)),
      SheetAction('Ganti nama', FontAwesomeIcons.pen, () => renameDialog(context, ref, e)),
      SheetAction('Kompres', FontAwesomeIcons.boxArchive, () => compressDialog(context, ref, [e.path])),
      SheetAction('Salin jalur', FontAwesomeIcons.link, () => copyText(context, e.path, message: 'Jalur disalin')),
      if (e.isDir) SheetAction('Tambah ke favorit', FontAwesomeIcons.star, () => runGuarded(context, () async => api.fs.addBookmark('path', e.path), success: 'Ditambahkan ke favorit')),
      SheetAction('Properti', FontAwesomeIcons.circleInfo, () => showProperties(context, ref, e.path)),
      SheetAction('Hapus', FontAwesomeIcons.trashCan, () async {
        final settings = ref.read(settingsProvider);
        final ok = !settings.confirmDelete ||
            await confirm(
              context,
              title: settings.useTrash ? 'Pindahkan ke sampah?' : 'Hapus permanen?',
              message: '"${e.name}" akan ${settings.useTrash ? 'dipindahkan ke sampah' : 'dihapus dan tidak bisa dipulihkan'}.',
              confirmLabel: settings.useTrash ? 'Pindahkan' : 'Hapus',
              danger: true,
            );
        if (ok && context.mounted) await runGuarded(context, () => notifier.delete([e.path]));
      }, danger: true),
    ],
  );
}

Future<void> renameDialog(BuildContext context, WidgetRef ref, FileEntry e) async {
  final name = await promptText(context, title: 'Ganti nama', initial: e.name, confirmLabel: 'Ganti', validator: validateName);
  if (name == null || name == e.name || !context.mounted) return;
  await runGuarded(context, () => ref.read(filesProvider.notifier).rename(e, name));
}

Future<void> compressDialog(BuildContext context, WidgetRef ref, List<String> sources) async {
  final base = sources.length == 1 ? baseName(sources.first) : 'arsip';
  final controller = TextEditingController(text: base);
  String format = 'zip';
  const labels = {'zip': 'ZIP', 'tgz': 'TAR.GZ', 'txz': 'TAR.XZ', 'tar': 'TAR'};
  const ext = {'zip': 'zip', 'tgz': 'tar.gz', 'txz': 'tar.xz', 'tar': 'tar'};
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Kompres'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OnyxField(controller: controller, label: 'Nama arsip', helper: 'Ekstensi .${ext[format]} ditambahkan otomatis.'),
            const SizedBox(height: Sp.x4),
            Segmented<String>(options: labels, value: format, onChanged: (v) => setState(() => format = v)),
          ],
        ),
        actions: [
          OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx, false)),
          OnyxButton(label: 'Kompres', compact: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    ),
  );
  final name = controller.text.trim();
  controller.dispose();
  if (go != true || name.isEmpty || !context.mounted) return;
  final state = ref.read(filesProvider);
  final output = joinPath(state.path, '$name.${ext[format]}');
  await runGuarded(context, () => ref.read(filesProvider.notifier).compress(sources, output, format), success: 'Arsip dibuat: $name.${ext[format]}');
}

Future<void> extractDialog(BuildContext context, WidgetRef ref, FileEntry e) async {
  final suggested = e.name.contains('.') ? e.name.substring(0, e.name.indexOf('.')) : '${e.name}_isi';
  final name = await promptText(context, title: 'Ekstrak ke folder', initial: suggested, confirmLabel: 'Ekstrak', validator: validateName);
  if (name == null || !context.mounted) return;
  final dest = joinPath(parentOf(e.path), name);
  await runGuarded(context, () => ref.read(filesProvider.notifier).extract(e.path, dest), success: 'Diekstrak ke $name');
}

Future<void> showProperties(BuildContext context, WidgetRef ref, String path) async {
  final api = ref.read(apiProvider);
  await showSheet<void>(
    context,
    builder: (ctx) => SheetFrame(
      title: 'Properti',
      child: FutureBuilder<Map<String, dynamic>>(
        future: api.fs.properties(path),
        builder: (ctx, snap) {
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(Sp.x6), child: ErrorState(message: snap.error.toString()));
          if (!snap.hasData) return const SizedBox(height: 180, child: Loading());
          return _PropertiesBody(data: snap.data!, ref: ref);
        },
      ),
    ),
  );
}

class _PropertiesBody extends StatefulWidget {
  const _PropertiesBody({required this.data, required this.ref});

  final Map<String, dynamic> data;
  final WidgetRef ref;

  @override
  State<_PropertiesBody> createState() => _PropertiesBodyState();
}

class _PropertiesBodyState extends State<_PropertiesBody> {
  final Map<String, String> _sums = {};
  String? _busy;

  Future<void> _sum(String algo) async {
    setState(() => _busy = algo);
    try {
      final value = await widget.ref.read(apiProvider).fs.checksum(widget.data['path'] as String, algo);
      setState(() => _sums[algo] = value);
    } catch (error) {
      if (mounted) toastError(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = widget.data;
    final isDir = d['isDir'] == true;
    Widget row(String k, String v, {bool mono = false, bool copy = false}) => InkWell(
          onTap: copy ? () => copyText(context, v) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 104, child: Text(k, style: context.text.bodySmall)),
                Expanded(child: Text(v, style: mono ? OnyxFonts.mono(size: 12, color: p.text) : context.text.bodyMedium)),
              ],
            ),
          ),
        );
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: Sp.x6),
      children: [
        row('Nama', d['name'] as String),
        row('Jalur', d['path'] as String, mono: true, copy: true),
        if (d['canonical'] != null && d['canonical'] != d['path']) row('Jalur asli', d['canonical'] as String, mono: true, copy: true),
        if (d['linkTarget'] != null) row('Tautan ke', d['linkTarget'] as String, mono: true),
        row('Jenis', isDir ? 'Folder' : (d['mime'] as String)),
        row('Ukuran', '${formatBytes((d['size'] as num).toInt())} (${(d['size'] as num).toInt()} bita)'),
        if (isDir) row('Isi', '${d['files']} berkas, ${d['folders']} folder'),
        row('Diubah', formatDateFull((d['modified'] as num).toInt())),
        row('Izin', '${d['mode']}  (${d['octal']})', mono: true),
        row('Pemilik (UID)', '${d['owner']}', mono: true),
        row('Dapat ditulis', d['writable'] == true ? 'Ya' : 'Tidak'),
        if (!isDir) ...[
          const SectionHeader('Checksum'),
          for (final algo in const ['md5', 'sha1', 'sha256'])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x1),
              child: Row(
                children: [
                  SizedBox(width: 64, child: Text(algo.toUpperCase(), style: context.text.labelMedium)),
                  Expanded(
                    child: _sums[algo] == null
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: OnyxButton(label: 'Hitung', compact: true, kind: OnyxButtonKind.secondary, loading: _busy == algo, onPressed: _busy == null ? () => _sum(algo) : null),
                          )
                        : GestureDetector(
                            onTap: () => copyText(context, _sums[algo]!),
                            child: Text(_sums[algo]!, style: OnyxFonts.mono(size: 11, color: p.text)),
                          ),
                  ),
                ],
              ),
            ),
        ],
        if (d['writable'] == true) ...[
          const SectionHeader('Ubah izin'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
            child: _ChmodEditor(path: d['path'] as String, octal: (d['octal'] ?? '644') as String, isDir: isDir, ref: widget.ref),
          ),
        ],
      ],
    );
  }
}

class _ChmodEditor extends StatefulWidget {
  const _ChmodEditor({required this.path, required this.octal, required this.isDir, required this.ref});

  final String path;
  final String octal;
  final bool isDir;
  final WidgetRef ref;

  @override
  State<_ChmodEditor> createState() => _ChmodEditorState();
}

class _ChmodEditorState extends State<_ChmodEditor> {
  late int _mode = int.tryParse(widget.octal, radix: 8) ?? 420;
  bool _recursive = false;

  bool _bit(int mask) => _mode & mask != 0;

  void _flip(int mask) => setState(() => _mode ^= mask);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget cell(String label, int mask) => Expanded(
          child: GestureDetector(
            onTap: () => _flip(mask),
            child: Container(
              height: 40,
              margin: const EdgeInsets.all(2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _bit(mask) ? p.accentMuted : p.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _bit(mask) ? p.accent : p.border),
              ),
              child: Text(label, style: OnyxFonts.mono(size: 13, weight: FontWeight.w600, color: _bit(mask) ? p.accent : p.textSecondary)),
            ),
          ),
        );
    Widget group(String title, int r, int w, int x) => Row(
          children: [
            SizedBox(width: 64, child: Text(title, style: context.text.bodySmall)),
            cell('r', r),
            cell('w', w),
            cell('x', x),
          ],
        );
    return Column(
      children: [
        group('Pemilik', 0x100, 0x80, 0x40),
        group('Grup', 0x20, 0x10, 0x8),
        group('Lainnya', 0x4, 0x2, 0x1),
        const SizedBox(height: Sp.x2),
        Row(
          children: [
            Text(_mode.toRadixString(8).padLeft(3, '0'), style: OnyxFonts.mono(size: 16, weight: FontWeight.w600, color: p.text)),
            const Spacer(),
            if (widget.isDir) ...[
              Text('Rekursif', style: context.text.bodySmall),
              Switch(value: _recursive, onChanged: (v) => setState(() => _recursive = v)),
            ],
            OnyxButton(
              label: 'Terapkan',
              compact: true,
              onPressed: () => runGuarded(context, () => widget.ref.read(apiProvider).fs.chmod(widget.path, _mode, recursive: _recursive), success: 'Izin diperbarui'),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showBookmarks(BuildContext context, WidgetRef ref) async {
  final api = ref.read(apiProvider);
  final notifier = ref.read(filesProvider.notifier);
  await showSheet<void>(
    context,
    builder: (ctx) => SheetFrame(
      title: 'Favorit',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: api.fs.bookmarks(type: 'path'),
        builder: (ctx, snap) {
          if (!snap.hasData) return const SizedBox(height: 160, child: Loading());
          final items = snap.data!;
          if (items.isEmpty) {
            return const SizedBox(height: 240, child: EmptyState(icon: FontAwesomeIcons.star, title: 'Belum ada favorit', message: 'Tambahkan folder dari menu berkas.'));
          }
          return StatefulBuilder(
            builder: (ctx, setState) => ListView(
              shrinkWrap: true,
              children: [
                for (final b in List<Map<String, dynamic>>.of(items))
                  NavRow(
                    icon: FontAwesomeIcons.folder,
                    title: (b['title'] ?? '') as String,
                    subtitle: b['value'] as String,
                    onTap: () {
                      Navigator.pop(ctx);
                      notifier.open(b['value'] as String);
                    },
                    trailing: IconButton(
                      tooltip: 'Hapus favorit',
                      onPressed: () async {
                        await api.fs.removeBookmark(b['id'] as String);
                        setState(() => items.remove(b));
                      },
                      icon: const FaIcon(FontAwesomeIcons.xmark, size: 14),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
