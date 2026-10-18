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

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.entry});

  final FileEntry entry;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final ScrollController _scroll = ScrollController();
  final Map<int, Future<Uint8List>> _cache = {};
  int _pages = 0;
  double _ratio = 1.414;
  double _zoom = 1;
  int _visible = 1;
  String? _error;
  bool _loading = true;

  static const double _gap = Sp.x3;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_track);
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await ref.read(apiProvider).viewer.pdfInfo(widget.entry.path);
      final w = ((info['width'] ?? 1) as num).toDouble();
      final h = ((info['height'] ?? 1) as num).toDouble();
      if (!mounted) return;
      setState(() {
        _pages = ((info['pages'] ?? 0) as num).toInt();
        _ratio = w > 0 ? h / w : 1.414;
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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _pageWidth(double viewport) => (viewport - Sp.x4 * 2) * _zoom;

  double _pageExtent(double viewport) => _pageWidth(viewport) * _ratio + _gap;

  void _track() {
    if (!_scroll.hasClients || _pages == 0) return;
    final viewport = MediaQuery.sizeOf(context).width;
    final extent = _pageExtent(viewport);
    final page = ((_scroll.offset + extent / 2) / extent).floor() + 1;
    final clamped = page.clamp(1, _pages);
    if (clamped != _visible) setState(() => _visible = clamped);
  }

  Future<Uint8List> _render(int index, double width, double density) {
    final target = (width * density).round().clamp(320, 2048);
    final key = index * 10000 + target;
    return _cache.putIfAbsent(key, () async {
      if (_cache.length > 24) _cache.remove(_cache.keys.first);
      final result = await ref.read(apiProvider).viewer.pdfPage(widget.entry.path, index, target);
      final png = result['png'];
      return png is Uint8List ? png : Uint8List(0);
    });
  }

  Future<void> _jump() async {
    final value = await promptText(
      context,
      title: 'Ke halaman',
      hint: '1 sampai $_pages',
      initial: '$_visible',
      confirmLabel: 'Pergi',
      keyboard: TextInputType.number,
      validator: (v) {
        final n = int.tryParse(v);
        if (n == null || n < 1 || n > _pages) return 'Masukkan angka 1 sampai $_pages';
        return null;
      },
    );
    if (value == null || !mounted) return;
    final page = int.parse(value);
    final extent = _pageExtent(MediaQuery.sizeOf(context).width);
    _scroll.animateTo((page - 1) * extent, duration: Motion.screen, curve: Motion.standard);
  }

  void _setZoom(double zoom) {
    final anchor = _visible;
    setState(() => _zoom = zoom.clamp(1.0, 3.0));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final extent = _pageExtent(MediaQuery.sizeOf(context).width);
      _scroll.jumpTo(((anchor - 1) * extent).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Widget body;
    if (_loading) {
      body = const Loading(label: 'Membuka PDF');
    } else if (_error != null) {
      body = ErrorState(title: 'PDF tidak dapat dibuka', message: _error!, onRetry: _open);
    } else if (_pages == 0) {
      body = const EmptyState(icon: FontAwesomeIcons.filePdf, title: 'PDF kosong', message: 'Dokumen ini tidak memiliki halaman.');
    } else {
      body = LayoutBuilder(
        builder: (context, box) {
          final width = _pageWidth(box.maxWidth);
          final density = MediaQuery.devicePixelRatioOf(context);
          final list = ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: Sp.x3, horizontal: Sp.x4),
            itemCount: _pages,
            itemExtent: width * _ratio + _gap,
            cacheExtent: width * _ratio,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: Container(
                width: width,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(4)),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<Uint8List>(
                  future: _render(i, width, density),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Halaman ${i + 1} gagal dirender', style: context.text.bodySmall?.copyWith(color: Colors.black54)));
                    }
                    final data = snap.data;
                    if (data == null || data.isEmpty) {
                      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    return Image.memory(data, fit: BoxFit.fill, gaplessPlayback: true, semanticLabel: 'Halaman ${i + 1}');
                  },
                ),
              ),
            ),
          );
          if (_zoom <= 1) return list;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width + Sp.x4 * 2, height: box.maxHeight, child: list),
          );
        },
      );
    }
    return ViewerScaffold(
      path: widget.entry.path,
      actions: [ViewerActions(entry: widget.entry)],
      body: body,
      bottom: _pages == 0
          ? null
          : Material(
              color: p.surface,
              child: SafeArea(
                top: false,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x2),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Perkecil',
                        onPressed: _zoom > 1 ? () => _setZoom(_zoom - 0.5) : null,
                        icon: const FaIcon(FontAwesomeIcons.magnifyingGlassMinus, size: 16),
                      ),
                      Text('${(_zoom * 100).round()}%', style: OnyxFonts.mono(size: 12, color: p.textSecondary)),
                      IconButton(
                        tooltip: 'Perbesar',
                        onPressed: _zoom < 3 ? () => _setZoom(_zoom + 0.5) : null,
                        icon: const FaIcon(FontAwesomeIcons.magnifyingGlassPlus, size: 16),
                      ),
                      Expanded(
                        child: Center(
                          child: InkWell(
                            onTap: _jump,
                            borderRadius: Rd.c,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x2),
                              child: Text('Halaman $_visible dari $_pages', maxLines: 1, overflow: TextOverflow.ellipsis, style: OnyxFonts.mono(size: 12, color: p.text)),
                            ),
                          ),
                        ),
                      ),
                      if (MediaQuery.sizeOf(context).width >= 400) Text(formatBytes(widget.entry.size), style: OnyxFonts.mono(size: 12, color: p.textMuted)),
                      const SizedBox(width: Sp.x2),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
