import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'viewer_common.dart';

class AudioViewerScreen extends ConsumerStatefulWidget {
  const AudioViewerScreen({super.key, required this.tracks, required this.index});

  final List<FileEntry> tracks;
  final int index;

  @override
  ConsumerState<AudioViewerScreen> createState() => _AudioViewerScreenState();
}

class _AudioViewerScreenState extends ConsumerState<AudioViewerScreen> {
  final AudioPlayer _player = AudioPlayer();
  late int _index = widget.index;
  Map<String, dynamic> _info = const {};
  String? _error;
  bool _loading = true;
  bool _repeat = false;

  FileEntry get _entry => widget.tracks[_index];

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) _onCompleted();
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await ref.read(apiProvider).viewer.audioInfo(_entry.path).catchError((_) => <String, dynamic>{});
      await _player.setFilePath(_entry.path);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
      _player.play();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = OnyxError.from(error).message;
          _loading = false;
        });
      }
    }
  }

  void _onCompleted() {
    if (_repeat) {
      _player.seek(Duration.zero);
      _player.play();
    } else if (_index < widget.tracks.length - 1) {
      _go(_index + 1);
    }
  }

  void _go(int next) {
    if (next < 0 || next >= widget.tracks.length) return;
    setState(() => _index = next);
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cover = _info['cover'];
    final title = (_info['title'] as String?)?.trim();
    final artist = (_info['artist'] as String?)?.trim();
    final album = (_info['album'] as String?)?.trim();
    return ViewerScaffold(
      path: _entry.path,
      actions: [ViewerActions(entry: _entry)],
      body: LayoutBuilder(
        builder: (context, box) {
          final art = (box.maxWidth - Sp.x8 * 2).clamp(160.0, 320.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.x6),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - Sp.x6 * 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: art,
                    height: art,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: Rd.k,
                      border: Border.all(color: p.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: cover is Uint8List && cover.isNotEmpty
                        ? Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true)
                        : Center(child: FaIcon(FontAwesomeIcons.music, size: 56, color: p.textMuted)),
                  ),
                  const SizedBox(height: Sp.x6),
                  Text(
                    (title == null || title.isEmpty) ? baseName(_entry.path) : title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleLarge,
                  ),
                  if (artist != null && artist.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.x1),
                      child: Text(artist, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: p.textSecondary)),
                    ),
                  if (album != null && album.isNotEmpty) Text(album, textAlign: TextAlign.center, style: context.text.bodySmall),
                  const SizedBox(height: Sp.x6),
                  if (_error != null)
                    ErrorState(title: 'Audio gagal diputar', message: _error!, onRetry: _load)
                  else ...[
                    _Seek(player: _player, enabled: !_loading),
                    const SizedBox(height: Sp.x2),
                    _Controls(
                      player: _player,
                      loading: _loading,
                      repeat: _repeat,
                      onRepeat: () => setState(() => _repeat = !_repeat),
                      onPrev: _index > 0 ? () => _go(_index - 1) : null,
                      onNext: _index < widget.tracks.length - 1 ? () => _go(_index + 1) : null,
                    ),
                  ],
                  if (widget.tracks.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.x4),
                      child: Text('${_index + 1} dari ${widget.tracks.length} lagu', style: context.text.bodySmall),
                    ),
                  const SizedBox(height: Sp.x2),
                  Text(
                    [
                      formatBytes(_entry.size),
                      if (((_info['bitrate'] ?? 0) as num) > 0) '${(((_info['bitrate'] ?? 0) as num) / 1000).round()} kb/s',
                    ].join('  ·  '),
                    style: OnyxFonts.mono(size: 12, color: p.textMuted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Seek extends StatefulWidget {
  const _Seek({required this.player, required this.enabled});

  final AudioPlayer player;
  final bool enabled;

  @override
  State<_Seek> createState() => _SeekState();
}

class _SeekState extends State<_Seek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return StreamBuilder<Duration?>(
      stream: widget.player.durationStream,
      builder: (context, durationSnap) {
        final total = (durationSnap.data ?? Duration.zero).inMilliseconds.toDouble();
        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          builder: (context, positionSnap) {
            final position = (positionSnap.data ?? Duration.zero).inMilliseconds.toDouble();
            final value = (_drag ?? position).clamp(0.0, total <= 0 ? 1.0 : total);
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: p.accent,
                    inactiveTrackColor: p.surfaceAlt,
                    thumbColor: p.accent,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    min: 0,
                    max: total <= 0 ? 1.0 : total,
                    value: value,
                    onChanged: widget.enabled && total > 0 ? (v) => setState(() => _drag = v) : null,
                    onChangeEnd: (v) {
                      widget.player.seek(Duration(milliseconds: v.round()));
                      setState(() => _drag = null);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatMillis(value.round()), style: OnyxFonts.mono(size: 12, color: p.textSecondary)),
                      Text(formatMillis(total.round()), style: OnyxFonts.mono(size: 12, color: p.textSecondary)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.player,
    required this.loading,
    required this.repeat,
    required this.onRepeat,
    required this.onPrev,
    required this.onNext,
  });

  final AudioPlayer player;
  final bool loading;
  final bool repeat;
  final VoidCallback onRepeat;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: repeat ? 'Ulangi: hidup' : 'Ulangi: mati',
          onPressed: onRepeat,
          icon: FaIcon(FontAwesomeIcons.repeat, size: 17, color: repeat ? p.accent : p.textMuted),
        ),
        IconButton(
          tooltip: 'Sebelumnya',
          onPressed: onPrev,
          icon: const FaIcon(FontAwesomeIcons.backwardStep, size: 20),
        ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snap) {
            final playing = snap.data?.playing ?? false;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: Sp.x2),
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
              child: loading
                  ? Padding(padding: const EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
                  : IconButton(
                      tooltip: playing ? 'Jeda' : 'Putar',
                      onPressed: () => playing ? player.pause() : player.play(),
                      icon: FaIcon(playing ? FontAwesomeIcons.pause : FontAwesomeIcons.play, size: 22, color: p.onAccent),
                    ),
            );
          },
        ),
        IconButton(
          tooltip: 'Berikutnya',
          onPressed: onNext,
          icon: const FaIcon(FontAwesomeIcons.forwardStep, size: 20),
        ),
        IconButton(
          tooltip: 'Mundur 10 detik',
          onPressed: () => player.seek((player.position - const Duration(seconds: 10)).isNegative ? Duration.zero : player.position - const Duration(seconds: 10)),
          icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 17),
        ),
      ],
    );
  }
}
