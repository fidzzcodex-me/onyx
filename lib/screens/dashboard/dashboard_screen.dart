import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/auth_state.dart';
import '../../state/nav.dart';
import '../../state/providers.dart';
import '../../state/system_state.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<StorageRoot> _roots = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(systemProvider.notifier).loadDevice();
      ref.read(systemProvider.notifier).setActive(true);
      _loadRoots();
    });
  }

  Future<void> _loadRoots() async {
    try {
      final roots = await ref.read(apiProvider).fs.roots();
      if (mounted) setState(() => _roots = roots);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppTab>(tabProvider, (previous, next) {
      ref.read(systemProvider.notifier).setActive(next == AppTab.dashboard);
      if (next == AppTab.dashboard) _loadRoots();
    });
    final sys = ref.watch(systemProvider);
    final user = ref.watch(authProvider.select((s) => s.user));
    final p = context.palette;
    final cpu = sys.section('cpu');
    final mem = sys.section('memory');
    final storage = sys.section('storage');
    final battery = sys.section('battery');
    final net = sys.section('network');
    final cpuPercent = ((cpu['percent'] ?? -1) as num).toDouble();
    final memTotal = ((mem['total'] ?? 0) as num).toDouble();
    final memUsed = ((mem['used'] ?? 0) as num).toDouble();
    final stTotal = ((storage['total'] ?? 0) as num).toDouble();
    final stUsed = ((storage['used'] ?? 0) as num).toDouble();
    final wide = context.isWide;

    final cards = <Widget>[
      _MetricCard(
        icon: FontAwesomeIcons.microchip,
        title: 'CPU',
        value: cpuPercent >= 0 ? percent(cpuPercent) : 'Tidak tersedia',
        detail: cpuPercent >= 0
            ? '${cpu['cores'] ?? '-'} inti${(cpu['source'] ?? '') == 'cpufreq' ? ', estimasi dari frekuensi' : ''}'
            : 'Android membatasi akses statistik CPU di versi ini.',
        history: sys.cpu,
      ),
      _MetricCard(
        icon: FontAwesomeIcons.memory,
        title: 'Memori',
        value: memTotal > 0 ? percent(memUsed * 100 / memTotal) : '-',
        detail: memTotal > 0 ? '${formatBytes(memUsed)} dari ${formatBytes(memTotal)}' : '',
        history: sys.ram,
      ),
      _MetricCard(
        icon: FontAwesomeIcons.arrowsUpDown,
        title: 'Jaringan',
        value: '${formatSpeed(((net['rxRate'] ?? 0) as num))} turun',
        detail: '${formatSpeed(((net['txRate'] ?? 0) as num))} naik, ${net['type'] ?? '-'}',
        history: sys.rx,
        max: 1024 * 64,
      ),
      OnyxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FaIcon(FontAwesomeIcons.hardDrive, size: 14, color: p.textSecondary),
                const SizedBox(width: Sp.x2),
                Text('Penyimpanan', style: context.text.titleSmall),
              ],
            ),
            const SizedBox(height: Sp.x3),
            Text(stTotal > 0 ? percent(stUsed * 100 / stTotal) : '-', style: OnyxFonts.mono(size: 24, weight: FontWeight.w600, color: p.text)),
            const SizedBox(height: Sp.x2),
            RatioBar(value: stTotal > 0 ? stUsed / stTotal : 0),
            const SizedBox(height: Sp.x2),
            Text(stTotal > 0 ? '${formatBytes(stUsed)} dari ${formatBytes(stTotal)}' : '', style: context.text.bodySmall),
          ],
        ),
      ),
    ];

    final sections = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user == null || user.isGuest ? 'Halo' : 'Halo, ${user.name.split(' ').first}', style: context.text.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${sys.device['manufacturer'] ?? ''} ${sys.device['model'] ?? ''}'.trim().isEmpty
                        ? 'Memuat info perangkat'
                        : '${sys.device['manufacturer']} ${sys.device['model']}, Android ${sys.device['androidVersion'] ?? ''}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Pengaturan',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
              icon: const FaIcon(FontAwesomeIcons.gear, size: 18),
            ),
          ],
        ),
      ),
      const SectionHeader('Mulai cepat'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
        child: Row(
          children: [
            Expanded(child: _Quick(icon: FontAwesomeIcons.terminal, label: 'Terminal baru', onTap: () => ref.read(tabProvider.notifier).state = AppTab.terminal)),
            const SizedBox(width: Sp.x3),
            Expanded(child: _Quick(icon: FontAwesomeIcons.folderOpen, label: 'Jelajahi berkas', onTap: () => ref.read(tabProvider.notifier).state = AppTab.files)),
            const SizedBox(width: Sp.x3),
            Expanded(child: _Quick(icon: FontAwesomeIcons.server, label: 'Sambung server', onTap: () => ref.read(tabProvider.notifier).state = AppTab.servers)),
          ],
        ),
      ),
      const SectionHeader('Perangkat saat ini'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
        child: wide
            ? GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Sp.x3,
                crossAxisSpacing: Sp.x3,
                childAspectRatio: 2.0,
                children: cards,
              )
            : Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: Sp.x3), child: c)]),
      ),
      if (battery['available'] == true) ...[
        const SectionHeader('Daya'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
          child: OnyxCard(
            child: Row(
              children: [
                FaIcon(
                  (battery['charging'] == true) ? FontAwesomeIcons.batteryFull : FontAwesomeIcons.batteryHalf,
                  size: 18,
                  color: battery['charging'] == true ? p.success : p.textSecondary,
                ),
                const SizedBox(width: Sp.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${battery['percent']}%', style: context.text.titleMedium),
                      Text(
                        battery['charging'] == true ? 'Mengisi daya, ${battery['plugged']}' : 'Tidak mengisi daya',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text('${battery['temperature']} C', style: OnyxFonts.mono(size: 13, color: p.textSecondary)),
              ],
            ),
          ),
        ),
      ],
      const SectionHeader('Penyimpanan tersambung'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
        child: _roots.isEmpty
            ? Text('Belum ada volume yang dapat dibaca.', style: context.text.bodySmall)
            : Column(
                children: [
                  for (final root in _roots.where((r) => r.kind == 'internal' || r.kind == 'sd' || r.kind == 'home'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.x3),
                      child: OnyxCard(
                        onTap: () {
                          ref.read(pendingFilesPathProvider.notifier).state = root.path;
                          ref.read(tabProvider.notifier).state = AppTab.files;
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(root.title, style: context.text.titleSmall)),
                                Text(root.total > 0 ? '${formatBytes(root.total - root.free)} / ${formatBytes(root.total)}' : '', style: context.text.bodySmall),
                              ],
                            ),
                            const SizedBox(height: Sp.x2),
                            Text(root.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: OnyxFonts.mono(size: 11, color: p.textMuted)),
                            if (root.total > 0) ...[const SizedBox(height: Sp.x3), RatioBar(value: root.usedRatio)],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
      const SectionHeader('Perangkat keras'),
      Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x8),
        child: OnyxCard(
          padding: const EdgeInsets.symmetric(vertical: Sp.x2),
          child: Column(
            children: [
              _Kv('Prosesor', '${sys.device['cpuModel'] ?? '-'}'.isEmpty ? '-' : '${sys.device['cpuModel'] ?? '-'}'),
              _Kv('Arsitektur', ((sys.device['abis'] as List?)?.isNotEmpty ?? false) ? (sys.device['abis'] as List).first.toString() : '-'),
              _Kv('Kernel', '${sys.device['kernel'] ?? '-'}'),
              _Kv('API', '${sys.device['sdk'] ?? '-'}'),
              _Kv('Aktif sejak', sys.snapshot['uptimeMs'] == null ? '-' : formatUptime((sys.snapshot['uptimeMs'] as num).toInt())),
            ],
          ),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(systemProvider.notifier).loadDevice();
            await _loadRoots();
          },
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OnyxCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x4),
      child: Column(
        children: [
          FaIcon(icon, size: 20, color: p.accent),
          const SizedBox(height: Sp.x2),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: context.text.labelMedium?.copyWith(color: p.text)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.title, required this.value, required this.detail, required this.history, this.max = 100});

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final List<double> history;
  final double max;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 14, color: p.textSecondary),
              const SizedBox(width: Sp.x2),
              Text(title, style: context.text.titleSmall),
            ],
          ),
          const SizedBox(height: Sp.x3),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: OnyxFonts.mono(size: 22, weight: FontWeight.w600, color: p.text)),
          const SizedBox(height: 2),
          Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
          const SizedBox(height: Sp.x3),
          Sparkline(values: history, max: max),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(k, style: context.text.bodySmall)),
          Expanded(child: Text(v, style: OnyxFonts.mono(size: 12, color: context.palette.text))),
        ],
      ),
    );
  }
}
