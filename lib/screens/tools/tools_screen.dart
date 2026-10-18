import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/nav.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';
import '../../widgets/fields.dart';
import 'network_tools.dart';

enum _Section { network, processes, logs }

class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  _Section _section = _Section.network;

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(tabProvider) == AppTab.tools;
    return Scaffold(
      appBar: const OnyxAppBar(title: 'Alat', automaticLeading: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x3),
            child: Segmented<_Section>(
              options: const {_Section.network: 'Jaringan', _Section.processes: 'Proses', _Section.logs: 'Log'},
              value: _section,
              onChanged: (v) => setState(() => _section = v),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.screen,
              switchInCurve: Motion.standard,
              child: switch (_section) {
                _Section.network => const NetworkToolsView(key: ValueKey('net')),
                _Section.processes => ProcessesView(key: const ValueKey('proc'), active: active),
                _Section.logs => LogsView(key: const ValueKey('log'), active: active),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProcessesView extends ConsumerStatefulWidget {
  const ProcessesView({super.key, required this.active});

  final bool active;

  @override
  ConsumerState<ProcessesView> createState() => _ProcessesViewState();
}

class _ProcessesViewState extends ConsumerState<ProcessesView> {
  List<ProcessInfo> _items = const [];
  Timer? _timer;
  bool _loading = true;
  String? _error;
  String _sort = 'mem';
  String _filter = '';
  bool _onlyOwn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (widget.active) _tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final list = await ref.read(apiProvider).process.list();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = OnyxError.from(error).message;
        });
      }
    } finally {
      _busy = false;
    }
  }

  List<ProcessInfo> get _visible {
    var list = _items.where((e) => !_onlyOwn || e.own).toList();
    if (_filter.isNotEmpty) {
      final needle = _filter.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(needle) || e.cmd.toLowerCase().contains(needle) || '${e.pid}' == needle).toList();
    }
    list.sort((a, b) => switch (_sort) {
          'cpu' => b.cpu.compareTo(a.cpu),
          'pid' => a.pid.compareTo(b.pid),
          'name' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          _ => b.rssKb.compareTo(a.rssKb),
        });
    return list;
  }

  Future<void> _signal(ProcessInfo proc, int signal, String label) async {
    final ok = await confirm(
      context,
      title: '$label ${proc.name}?',
      message: 'Sinyal $signal dikirim ke PID ${proc.pid}. Android hanya mengizinkan sinyal ke proses milik aplikasi ini.',
      confirmLabel: label,
      danger: signal == 9 || signal == 15,
    );
    if (!ok || !mounted) return;
    await runGuarded(context, () async {
      await ref.read(apiProvider).process.signal(proc.pid, signal);
      await _tick();
    }, success: 'Sinyal terkirim');
  }

  void _details(ProcessInfo proc) {
    showSheet<void>(
      context,
      builder: (ctx) => SheetFrame(
        title: proc.name,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
          children: [
            _kv(ctx, 'PID', '${proc.pid}'),
            _kv(ctx, 'PPID', '${proc.ppid}'),
            _kv(ctx, 'Status', proc.state),
            _kv(ctx, 'Thread', '${proc.threads}'),
            _kv(ctx, 'Memori', proc.memory),
            _kv(ctx, 'CPU', percent(proc.cpu)),
            _kv(ctx, 'Perintah', proc.cmd.isEmpty ? proc.name : proc.cmd),
            const SizedBox(height: Sp.x3),
            if (!proc.own)
              Text('Proses ini bukan milik Onyx. Android akan menolak sinyal ke proses aplikasi lain.', style: ctx.text.bodySmall),
            const SizedBox(height: Sp.x3),
            Wrap(
              spacing: Sp.x2,
              runSpacing: Sp.x2,
              children: [
                OnyxButton(label: 'Hentikan', kind: OnyxButtonKind.secondary, compact: true, onPressed: () {
                  Navigator.pop(ctx);
                  _signal(proc, 15, 'Hentikan');
                }),
                OnyxButton(label: 'Paksa berhenti', kind: OnyxButtonKind.danger, compact: true, onPressed: () {
                  Navigator.pop(ctx);
                  _signal(proc, 9, 'Paksa berhenti');
                }),
                OnyxButton(label: 'Jeda', kind: OnyxButtonKind.secondary, compact: true, onPressed: () {
                  Navigator.pop(ctx);
                  _signal(proc, 19, 'Jeda');
                }),
                OnyxButton(label: 'Lanjutkan', kind: OnyxButtonKind.secondary, compact: true, onPressed: () {
                  Navigator.pop(ctx);
                  _signal(proc, 18, 'Lanjutkan');
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 84, child: Text(k, style: context.text.bodySmall)),
            Expanded(child: SelectableText(v, style: OnyxFonts.mono(size: 12, color: context.palette.text))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) return const Loading(label: 'Membaca proses');
    if (_error != null) return ErrorState(message: _error!, onRetry: _tick);
    final items = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x2),
          child: TextField(
            onChanged: (v) => setState(() => _filter = v),
            decoration: const InputDecoration(hintText: 'Cari nama, perintah, atau PID', isDense: true),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
            children: [
              for (final entry in const {'mem': 'Memori', 'cpu': 'CPU', 'pid': 'PID', 'name': 'Nama'}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: Sp.x2),
                  child: ChoiceChip(label: Text(entry.value), selected: _sort == entry.key, onSelected: (_) => setState(() => _sort = entry.key)),
                ),
              FilterChip(label: const Text('Hanya milik Onyx'), selected: _onlyOwn, onSelected: (v) => setState(() => _onlyOwn = v)),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(icon: FontAwesomeIcons.microchip, title: 'Tidak ada proses', message: 'Android hanya menampilkan proses yang dapat dibaca aplikasi ini.')
              : ListView.separated(
                  itemCount: items.length + 1,
                  separatorBuilder: (_, __) => Divider(height: 1, color: p.divider),
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return Padding(
                        padding: const EdgeInsets.all(Sp.x4),
                        child: Text('${items.length} proses terlihat. Android 8+ menyembunyikan proses aplikasi lain.', style: context.text.bodySmall),
                      );
                    }
                    final proc = items[i];
                    return InkWell(
                      onTap: () => _details(proc),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                        child: Row(
                          children: [
                            StatusDot(color: proc.own ? p.accent : p.textMuted, size: 7),
                            const SizedBox(width: Sp.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(proc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                                  Text('PID ${proc.pid}  ·  ${proc.state}  ·  ${proc.threads} thread', style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(proc.memory, style: OnyxFonts.mono(size: 12, color: p.text)),
                                Text(percent(proc.cpu), style: OnyxFonts.mono(size: 11, color: p.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class LogsView extends ConsumerStatefulWidget {
  const LogsView({super.key, required this.active});

  final bool active;

  @override
  ConsumerState<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends ConsumerState<LogsView> {
  List<String> _lines = const [];
  bool _loading = true;
  String? _error;
  String _level = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lines = await ref.read(apiProvider).system.logs(lines: 400);
      if (mounted) {
        setState(() {
          _lines = lines;
          _loading = false;
          _error = null;
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

  Color _color(String line, OnyxPalette p) {
    if (line.contains(' E/') || line.contains('ERROR')) return p.error;
    if (line.contains(' W/') || line.contains('WARN')) return p.warning;
    return p.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) return const Loading(label: 'Membaca log');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final shown = _level.isEmpty ? _lines : _lines.where((l) => l.contains(' $_level/') || l.toUpperCase().contains(_level == 'E' ? 'ERROR' : 'WARN')).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(label: const Text('Semua'), selected: _level.isEmpty, onSelected: (_) => setState(() => _level = '')),
                      const SizedBox(width: Sp.x2),
                      ChoiceChip(label: const Text('Peringatan'), selected: _level == 'W', onSelected: (_) => setState(() => _level = 'W')),
                      const SizedBox(width: Sp.x2),
                      ChoiceChip(label: const Text('Galat'), selected: _level == 'E', onSelected: (_) => setState(() => _level = 'E')),
                    ],
                  ),
                ),
              ),
              IconButton(tooltip: 'Segarkan', onPressed: _load, icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 15)),
              IconButton(
                tooltip: 'Salin log',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: shown.join('\n')));
                  toast(context, 'Log disalin');
                },
                icon: const FaIcon(FontAwesomeIcons.copy, size: 15),
              ),
              IconButton(
                tooltip: 'Hapus log',
                onPressed: () async {
                  final ok = await confirm(context, title: 'Hapus log?', message: 'Berkas log aplikasi dikosongkan.', confirmLabel: 'Hapus', danger: true);
                  if (!ok || !context.mounted) return;
                  await runGuarded(context, () async {
                    await ref.read(apiProvider).system.clearLogs();
                    await _load();
                  });
                },
                icon: FaIcon(FontAwesomeIcons.trashCan, size: 15, color: p.error),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(icon: FontAwesomeIcons.scroll, title: 'Log kosong', message: 'Peristiwa aplikasi akan muncul di sini.')
              : Container(
                  margin: const EdgeInsets.all(Sp.x3),
                  decoration: BoxDecoration(color: p.terminalBg, borderRadius: Rd.c, border: Border.all(color: p.border)),
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(Sp.x3),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final line = shown[shown.length - 1 - i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText(line, style: OnyxFonts.mono(size: 11, color: _color(line, p), height: 1.4)),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
