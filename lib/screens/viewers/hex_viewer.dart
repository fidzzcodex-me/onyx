import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import 'viewer_common.dart';

class HexViewerScreen extends ConsumerStatefulWidget {
  const HexViewerScreen({super.key, required this.entry});

  final FileEntry entry;

  @override
  ConsumerState<HexViewerScreen> createState() => _HexViewerScreenState();
}

class _HexViewerScreenState extends ConsumerState<HexViewerScreen> {
  static const int _chunk = 4096;
  static const double _rowHeight = 22;

  final ScrollController _scroll = ScrollController();
  final Map<int, Uint8List> _chunks = {};
  final Set<int> _loading = {};
  int _size = -1;
  String? _error;
  int _highlight = -1;
  int _highlightLength = 0;
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    _fetch(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch(int index) async {
    if (_chunks.containsKey(index) || _loading.contains(index)) return;
    _loading.add(index);
    try {
      final result = await ref.read(apiProvider).viewer.hexRead(widget.entry.path, index * _chunk, _chunk);
      final bytes = result['bytes'];
      if (!mounted) return;
      setState(() {
        _size = ((result['size'] ?? 0) as num).toInt();
        _chunks[index] = bytes is Uint8List ? bytes : Uint8List(0);
        if (_chunks.length > 48) {
          final far = _chunks.keys.reduce((a, b) => (a - index).abs() > (b - index).abs() ? a : b);
          if (far != index) _chunks.remove(far);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = OnyxError.from(error).message);
    } finally {
      _loading.remove(index);
    }
  }

  int _perRow(double width) => width >= 680 ? 16 : 8;

  void _jumpTo(int offset, double width) {
    final row = offset ~/ _perRow(width);
    final target = (row * _rowHeight - _rowHeight * 3).clamp(0.0, _scroll.hasClients ? _scroll.position.maxScrollExtent : double.infinity);
    _scroll.animateTo(target, duration: Motion.screen, curve: Motion.standard);
  }

  Future<void> _goto(double width) async {
    final value = await promptText(
      context,
      title: 'Ke offset',
      hint: 'Heksadesimal, contoh 1F40',
      confirmLabel: 'Pergi',
      validator: (v) {
        final n = int.tryParse(v.replaceFirst(RegExp(r'^0[xX]'), ''), radix: 16);
        if (n == null || n < 0 || n >= _size) return 'Offset harus antara 0 dan ${(_size - 1).toRadixString(16).toUpperCase()}';
        return null;
      },
    );
    if (value == null || !mounted) return;
    final offset = int.parse(value.replaceFirst(RegExp(r'^0[xX]'), ''), radix: 16);
    setState(() {
      _highlight = offset;
      _highlightLength = 1;
      _cursor = offset;
    });
    _jumpTo(offset, width);
  }

  Future<void> _find(double width) async {
    final controller = TextEditingController();
    bool asHex = false;
    final query = await showDialog<(String, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Cari byte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ChoiceChip(label: const Text('Teks'), selected: !asHex, onSelected: (_) => setLocal(() => asHex = false)),
                  const SizedBox(width: Sp.x2),
                  ChoiceChip(label: const Text('Hex'), selected: asHex, onSelected: (_) => setLocal(() => asHex = true)),
                ],
              ),
              const SizedBox(height: Sp.x3),
              TextField(
                controller: controller,
                autofocus: true,
                style: OnyxFonts.mono(size: 14),
                decoration: InputDecoration(hintText: asHex ? '4F 6E 79 78' : 'teks yang dicari'),
                onSubmitted: (v) => Navigator.pop(ctx, (v, asHex)),
              ),
            ],
          ),
          actions: [
            OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx)),
            OnyxButton(label: 'Cari', compact: true, onPressed: () => Navigator.pop(ctx, (controller.text, asHex))),
          ],
        ),
      ),
    );
    if (query == null || query.$1.trim().isEmpty || !mounted) return;
    await _runFind(query.$1.trim(), query.$2, _cursor, width);
  }

  Future<void> _runFind(String text, bool asHex, int from, double width) async {
    final api = ref.read(apiProvider);
    try {
      final hex = asHex ? text.replaceAll(RegExp(r'\s+'), '') : '';
      if (asHex && (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex))) {
        toast(context, 'Hex harus berpasangan, contoh 4F6E', error: true);
        return;
      }
      final found = asHex ? await api.viewer.hexFind(widget.entry.path, hex, from) : await api.viewer.textFind(widget.entry.path, text, from);
      if (!mounted) return;
      if (found < 0) {
        toast(context, from > 0 ? 'Tidak ada kecocokan lagi setelah offset ini' : 'Tidak ditemukan');
        return;
      }
      final length = asHex ? hex.length ~/ 2 : text.codeUnits.length;
      setState(() {
        _highlight = found;
        _highlightLength = length;
        _cursor = found + 1;
      });
      _jumpTo(found, width);
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ViewerScaffold(
      path: widget.entry.path,
      actions: [
        LayoutBuilder(
          builder: (context, _) {
            final width = MediaQuery.sizeOf(context).width;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Cari',
                  onPressed: _size <= 0 ? null : () => _find(width),
                  icon: const FaIcon(FontAwesomeIcons.magnifyingGlass, size: 16),
                ),
                IconButton(
                  tooltip: 'Ke offset',
                  onPressed: _size <= 0 ? null : () => _goto(width),
                  icon: const FaIcon(FontAwesomeIcons.locationCrosshairs, size: 16),
                ),
              ],
            );
          },
        ),
      ],
      body: _error != null
          ? ErrorState(title: 'Berkas tidak dapat dibaca', message: _error!, onRetry: () {
              setState(() => _error = null);
              _fetch(0);
            })
          : _size < 0
              ? const Loading(label: 'Membaca byte')
              : _size == 0
                  ? const EmptyState(icon: FontAwesomeIcons.microchip, title: 'Berkas kosong', message: 'Tidak ada byte untuk ditampilkan.')
                  : LayoutBuilder(
                      builder: (context, box) {
                        final perRow = _perRow(box.maxWidth);
                        final rows = (_size + perRow - 1) ~/ perRow;
                        final mono = OnyxFonts.mono(size: 12, color: p.text, height: 1.0);
                        final dim = OnyxFonts.mono(size: 12, color: p.textMuted, height: 1.0);
                        return Column(
                          children: [
                            Expanded(
                              child: Scrollbar(
                                controller: _scroll,
                                child: ListView.builder(
                                  controller: _scroll,
                                  itemCount: rows,
                                  itemExtent: _rowHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                                  itemBuilder: (context, row) {
                                    final offset = row * perRow;
                                    final chunkIndex = offset ~/ _chunk;
                                    final data = _chunks[chunkIndex];
                                    if (data == null) {
                                      _fetch(chunkIndex);
                                      return Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(offset.toRadixString(16).padLeft(8, '0').toUpperCase(), style: dim),
                                      );
                                    }
                                    final start = offset - chunkIndex * _chunk;
                                    final end = (start + perRow).clamp(0, data.length);
                                    return _HexRow(
                                      offset: offset,
                                      bytes: start >= data.length ? Uint8List(0) : Uint8List.sublistView(data, start, end),
                                      perRow: perRow,
                                      mono: mono,
                                      dim: dim,
                                      highlight: _highlight,
                                      highlightLength: _highlightLength,
                                      accent: p.accent,
                                      onTapByte: (o) => setState(() {
                                        _cursor = o;
                                        _highlight = o;
                                        _highlightLength = 1;
                                      }),
                                    );
                                  },
                                ),
                              ),
                            ),
                            _Inspector(
                              offset: _highlight < 0 ? 0 : _highlight,
                              size: _size,
                              data: _chunks[(_highlight < 0 ? 0 : _highlight) ~/ _chunk],
                              base: (_highlight < 0 ? 0 : _highlight) ~/ _chunk * _chunk,
                              palette: p,
                            ),
                          ],
                        );
                      },
                    ),
    );
  }
}

class _HexRow extends StatelessWidget {
  const _HexRow({
    required this.offset,
    required this.bytes,
    required this.perRow,
    required this.mono,
    required this.dim,
    required this.highlight,
    required this.highlightLength,
    required this.accent,
    required this.onTapByte,
  });

  final int offset;
  final Uint8List bytes;
  final int perRow;
  final TextStyle mono;
  final TextStyle dim;
  final int highlight;
  final int highlightLength;
  final Color accent;
  final ValueChanged<int> onTapByte;

  bool _marked(int index) => highlight >= 0 && index >= highlight && index < highlight + highlightLength;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 0; i < perRow; i++) {
      final has = i < bytes.length;
      final marked = has && _marked(offset + i);
      cells.add(
        GestureDetector(
          onTap: has ? () => onTapByte(offset + i) : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 22,
            height: 20,
            margin: const EdgeInsets.only(right: 2),
            alignment: Alignment.center,
            decoration: marked ? BoxDecoration(color: accent.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(3)) : null,
            child: Text(has ? bytes[i].toRadixString(16).padLeft(2, '0') : '', style: bytes.isNotEmpty && has && bytes[i] == 0 ? dim : mono),
          ),
        ),
      );
    }
    final ascii = StringBuffer();
    for (final b in bytes) {
      ascii.writeCharCode(b >= 32 && b < 127 ? b : 46);
    }
    return Row(
      children: [
        SizedBox(width: 66, child: Text(offset.toRadixString(16).padLeft(8, '0').toUpperCase(), style: dim)),
        ...cells,
        const SizedBox(width: Sp.x2),
        Expanded(child: Text(ascii.toString(), maxLines: 1, overflow: TextOverflow.clip, style: dim.copyWith(color: mono.color))),
      ],
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({required this.offset, required this.size, required this.data, required this.base, required this.palette});

  final int offset;
  final int size;
  final Uint8List? data;
  final int base;
  final OnyxPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final local = offset - base;
    final bytes = data;
    String info = 'Offset 0x${offset.toRadixString(16).toUpperCase()}  ·  ${formatBytes(size)}';
    if (bytes != null && local >= 0 && local < bytes.length) {
      final view = ByteData.sublistView(bytes);
      final u8 = bytes[local];
      info += '  ·  u8 $u8';
      if (local + 2 <= bytes.length) info += '  u16 ${view.getUint16(local, Endian.little)}';
      if (local + 4 <= bytes.length) info += '  u32 ${view.getUint32(local, Endian.little)}';
    }
    return Material(
      color: p.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 44,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(info, style: OnyxFonts.mono(size: 12, color: p.textSecondary)),
          ),
        ),
      ),
    );
  }
}
