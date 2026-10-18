import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:photo_view/photo_view.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import 'viewer_common.dart';

class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({super.key, required this.images, required this.index});

  final List<FileEntry> images;
  final int index;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _current = widget.index;
  bool _chrome = true;
  bool _zoomed = false;

  FileEntry get _entry => widget.images[_current];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _info() async {
    final api = ref.read(apiProvider);
    try {
      final info = await api.viewer.imageInfo(_entry.path);
      if (!mounted) return;
      await showInfoSheet(context, 'Info gambar', [
        MapEntry('Nama', _entry.name),
        MapEntry('Dimensi', '${info['width']} x ${info['height']} piksel'),
        MapEntry('Tipe', (info['mime'] ?? _entry.mime).toString()),
        MapEntry('Ukuran', formatBytes(_entry.size)),
        MapEntry('Diubah', formatDateFull(_entry.modified)),
        MapEntry('Lokasi', parentOf(_entry.path)),
      ]);
    } catch (error) {
      if (mounted) toastError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final multiple = widget.images.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 20),
        child: AnimatedOpacity(
          duration: Motion.dialog,
          opacity: _chrome ? 1 : 0,
          child: IgnorePointer(
            ignoring: !_chrome,
            child: OnyxAppBar(
              title: _entry.name,
              ribbon: multiple
                  ? Text('${_current + 1} / ${widget.images.length}', style: OnyxFonts.mono(size: 12, color: p.textSecondary))
                  : PathRibbon(path: _entry.path),
              actions: [
                IconButton(
                  tooltip: 'Info gambar',
                  onPressed: _info,
                  icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 17),
                ),
                ViewerActions(entry: _entry),
              ],
            ),
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.images.length,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        onPageChanged: (i) => setState(() {
          _current = i;
          _zoomed = false;
        }),
        itemBuilder: (context, i) {
          final entry = widget.images[i];
          return GestureDetector(
            onTap: () => setState(() => _chrome = !_chrome),
            child: PhotoView(
              key: ValueKey(entry.path),
              imageProvider: ResizeImage.resizeIfNeeded(null, 2400, FileImage(File(entry.path))),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 6,
              initialScale: PhotoViewComputedScale.contained,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              heroAttributes: PhotoViewHeroAttributes(tag: entry.path),
              scaleStateChangedCallback: (state) {
                final zoomed = state != PhotoViewScaleState.initial && state != PhotoViewScaleState.zoomedOut;
                if (zoomed != _zoomed && i == _current) setState(() => _zoomed = zoomed);
              },
              loadingBuilder: (context, event) => const Loading(),
              errorBuilder: (context, error, stack) => ErrorState(
                title: 'Gambar tidak dapat ditampilkan',
                message: 'Format ${entry.extension.toUpperCase()} mungkin tidak didukung perangkat ini. Coba buka dengan aplikasi lain.',
              ),
            ),
          );
        },
      ),
    );
  }
}
