import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).fs.trashList();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiProvider);
    final p = context.palette;
    final items = _items;
    return Scaffold(
      appBar: OnyxAppBar(
        title: 'Sampah',
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await confirm(context, title: 'Kosongkan sampah?', message: '${items.length} item akan dihapus permanen.', confirmLabel: 'Kosongkan', danger: true);
                if (!ok || !context.mounted) return;
                await runGuarded(context, () async {
                  await api.fs.trashEmpty();
                  await _load();
                });
              },
              child: const Text('Kosongkan'),
            ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? ErrorState(message: _error!, onRetry: _load)
            : items == null
                ? const Loading()
                : items.isEmpty
                    ? const EmptyState(icon: FontAwesomeIcons.trashCan, title: 'Sampah kosong', message: 'Berkas yang dihapus muncul di sini sampai Anda mengosongkannya.')
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                            child: Row(
                              children: [
                                FaIcon(item['isDir'] == true ? FontAwesomeIcons.folder : FontAwesomeIcons.file, size: 18, color: p.textSecondary),
                                const SizedBox(width: Sp.x3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text('${formatBytes((item['size'] as num).toInt())}  ${formatDate((item['deletedAt'] as num).toInt())}', style: context.text.bodySmall),
                                      Text(item['originalPath'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: OnyxFonts.mono(size: 11, color: p.textMuted)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Pulihkan',
                                  onPressed: () => runGuarded(context, () async {
                                    await api.fs.trashRestore(item['id'] as String);
                                    await _load();
                                  }, success: 'Dipulihkan'),
                                  icon: FaIcon(FontAwesomeIcons.rotateLeft, size: 16, color: p.accent),
                                ),
                                IconButton(
                                  tooltip: 'Hapus permanen',
                                  onPressed: () => runGuarded(context, () async {
                                    await api.fs.trashEmpty(id: item['id'] as String);
                                    await _load();
                                  }),
                                  icon: FaIcon(FontAwesomeIcons.trashCan, size: 16, color: p.error),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
