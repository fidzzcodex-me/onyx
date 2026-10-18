import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../state/sftp_state.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';

class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transfersProvider);
    final api = ref.read(apiProvider).sftp;
    final items = [...state.items]..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Scaffold(
      appBar: OnyxAppBar(
        title: 'Transfer',
        actions: [
          if (state.activeCount > 0)
            IconButton(
              tooltip: 'Batalkan semua',
              onPressed: () => runGuarded(context, api.cancelAll),
              icon: const FaIcon(FontAwesomeIcons.ban, size: 16),
            ),
          if (state.finishedCount > 0)
            IconButton(
              tooltip: 'Bersihkan yang selesai',
              onPressed: () => runGuarded(context, () async {
                await api.clearFinished();
                await ref.read(transfersProvider.notifier).refresh();
              }),
              icon: const FaIcon(FontAwesomeIcons.broom, size: 16),
            ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: FontAwesomeIcons.arrowRightArrowLeft,
              title: 'Tidak ada transfer',
              message: 'Unggahan dan unduhan dari browser server akan muncul di sini.',
            )
          : Column(
              children: [
                if (state.speed > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                    color: context.palette.surface,
                    child: Text('${state.activeCount} aktif  ·  ${formatSpeed(state.speed)}', style: OnyxFonts.mono(size: 12, color: context.palette.textSecondary)),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(Sp.x4),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Sp.x3),
                    itemBuilder: (context, i) => _TransferTile(item: items[i]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final api = ref.read(apiProvider).sftp;
    final up = item.direction == 'upload';
    Color stateColor;
    String stateLabel;
    switch (item.state) {
      case 'done':
        stateColor = p.success;
        stateLabel = 'Selesai';
      case 'error':
        stateColor = p.error;
        stateLabel = 'Gagal';
      case 'canceled':
        stateColor = p.textMuted;
        stateLabel = 'Dibatalkan';
      case 'paused':
        stateColor = p.warning;
        stateLabel = 'Dijeda';
      case 'running':
        stateColor = p.accent;
        stateLabel = 'Berjalan';
      default:
        stateColor = p.textSecondary;
        stateLabel = 'Antre';
    }
    final actions = <Widget>[];
    if (item.state == 'running' || item.state == 'queued') {
      actions.add(IconButton(tooltip: 'Jeda', onPressed: () => runGuarded(context, () => api.pause(item.id)), icon: const FaIcon(FontAwesomeIcons.pause, size: 14)));
    }
    if (item.state == 'paused') {
      actions.add(IconButton(tooltip: 'Lanjutkan', onPressed: () => runGuarded(context, () => api.resume(item.id)), icon: const FaIcon(FontAwesomeIcons.play, size: 14)));
    }
    if (item.state == 'error' || item.state == 'canceled') {
      actions.add(IconButton(tooltip: 'Coba lagi', onPressed: () => runGuarded(context, () => api.retry(item.id)), icon: const FaIcon(FontAwesomeIcons.rotateRight, size: 14)));
    }
    if (!item.finished) {
      actions.add(IconButton(tooltip: 'Batalkan', onPressed: () => runGuarded(context, () => api.cancel(item.id)), icon: const FaIcon(FontAwesomeIcons.xmark, size: 15)));
    }
    return OnyxCard(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x2, Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(up ? FontAwesomeIcons.arrowUp : FontAwesomeIcons.arrowDown, size: 14, color: p.textSecondary),
              const SizedBox(width: Sp.x3),
              Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
              ...actions,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: Sp.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Sp.x2),
                RatioBar(value: item.ratio, color: stateColor),
                const SizedBox(height: Sp.x2),
                Row(
                  children: [
                    StatusDot(color: stateColor, size: 7),
                    const SizedBox(width: Sp.x2),
                    Text(stateLabel, style: context.text.bodySmall?.copyWith(color: stateColor)),
                    const SizedBox(width: Sp.x2),
                    Expanded(
                      child: Text(
                        [
                          '${formatBytes(item.done)} / ${formatBytes(item.total)}',
                          if (item.state == 'running' && item.speed > 0) formatSpeed(item.speed),
                          if (item.state == 'running' && item.etaSec >= 0) formatEta(item.etaSec),
                        ].join('  ·  '),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OnyxFonts.mono(size: 11, color: p.textSecondary),
                      ),
                    ),
                  ],
                ),
                if (item.error != null && item.state == 'error')
                  Padding(padding: const EdgeInsets.only(top: Sp.x1), child: Text(item.error!, style: context.text.bodySmall?.copyWith(color: p.error))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
