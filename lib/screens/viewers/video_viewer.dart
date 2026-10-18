import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'viewer_common.dart';

class VideoViewerScreen extends ConsumerStatefulWidget {
  const VideoViewerScreen({super.key, required this.entry});

  final FileEntry entry;

  @override
  ConsumerState<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends ConsumerState<VideoViewerScreen> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;
  Map<String, dynamic> _info = const {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final controller = VideoPlayerController.file(File(widget.entry.path));
    _video = controller;
    try {
      await controller.initialize();
      try {
        _info = await ref.read(apiProvider).viewer.videoInfo(widget.entry.path);
      } catch (_) {}
      if (!mounted) return;
      final p = context.palette;
      final aspect = controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9;
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          aspectRatio: aspect,
          allowFullScreen: true,
          allowPlaybackSpeedChanging: true,
          playbackSpeeds: const [0.5, 0.75, 1, 1.25, 1.5, 2],
          materialProgressColors: ChewieProgressColors(
            playedColor: p.accent,
            handleColor: p.accent,
            bufferedColor: p.accent.withValues(alpha: 0.3),
            backgroundColor: Colors.white24,
          ),
          errorBuilder: (context, message) => ErrorState(title: 'Video gagal diputar', message: message),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = OnyxError.from(error).message);
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  void _showInfo() {
    final rotation = (_info['rotation'] ?? 0).toString();
    showInfoSheet(context, 'Info video', [
      MapEntry('Nama', widget.entry.name),
      MapEntry('Durasi', formatMillis(((_info['durationMs'] ?? 0) as num).toInt())),
      MapEntry('Dimensi', '${_info['width'] ?? 0} x ${_info['height'] ?? 0} piksel'),
      MapEntry('Rotasi', '$rotation derajat'),
      MapEntry('Bitrate', '${(((_info['bitrate'] ?? 0) as num) / 1000).round()} kb/s'),
      MapEntry('Tipe', (_info['mime'] ?? widget.entry.mime).toString()),
      MapEntry('Ukuran', formatBytes(widget.entry.size)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null) {
      body = ErrorState(
        title: 'Video tidak dapat dibuka',
        message: '$_error. Codec file ini mungkin tidak didukung perangkat.',
        onRetry: () {
          setState(() => _error = null);
          _start();
        },
      );
    } else if (_chewie == null) {
      body = const Loading(label: 'Menyiapkan video');
    } else {
      body = Center(child: Chewie(controller: _chewie!));
    }
    return ViewerScaffold(
      path: widget.entry.path,
      background: Colors.black,
      actions: [
        IconButton(
          tooltip: 'Info video',
          onPressed: _chewie == null ? null : _showInfo,
          icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 17),
        ),
        ViewerActions(entry: widget.entry),
      ],
      body: body,
    );
  }
}
