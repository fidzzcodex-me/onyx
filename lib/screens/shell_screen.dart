import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/tokens.dart';
import '../state/nav.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'dashboard/dashboard_screen.dart';
import 'files/files_screen.dart';
import 'servers/servers_screen.dart';
import 'terminal/terminal_screen.dart';
import 'tools/tools_screen.dart';

class _Dest {
  const _Dest(this.tab, this.label, this.icon);

  final AppTab tab;
  final String label;
  final IconData icon;
}

const _dests = [
  _Dest(AppTab.dashboard, 'Dasbor', FontAwesomeIcons.gaugeHigh),
  _Dest(AppTab.terminal, 'Terminal', FontAwesomeIcons.terminal),
  _Dest(AppTab.files, 'Berkas', FontAwesomeIcons.folderOpen),
  _Dest(AppTab.servers, 'Server', FontAwesomeIcons.server),
  _Dest(AppTab.tools, 'Alat', FontAwesomeIcons.screwdriverWrench),
];

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  final Set<AppTab> _visited = {AppTab.dashboard};

  Widget _page(AppTab tab) {
    switch (tab) {
      case AppTab.dashboard:
        return const DashboardScreen();
      case AppTab.terminal:
        return const TerminalScreen();
      case AppTab.files:
        return const FilesScreen();
      case AppTab.servers:
        return const ServersScreen();
      case AppTab.tools:
        return const ToolsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(tabProvider);
    _visited.add(current);
    final wide = context.isWide;
    final body = IndexedStack(
      index: AppTab.values.indexOf(current),
      children: [
        for (final tab in AppTab.values)
          _visited.contains(tab) ? _page(tab) : const SizedBox.shrink(),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final handler = ref.read(tabBackProvider)[current];
        if (handler != null && handler()) return;
        if (current == AppTab.dashboard) {
          ref.read(apiProvider).window.moveToBack().catchError((Object _) {});
        } else {
          ref.read(tabProvider.notifier).state = AppTab.dashboard;
        }
      },
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  _Rail(current: current, onSelect: (t) => ref.read(tabProvider.notifier).state = t),
                  VerticalDivider(width: 1, color: context.palette.divider),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: wide ? null : _Bar(current: current, onSelect: (t) => ref.read(tabProvider.notifier).state = t),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: Sp.navHeight,
          child: Row(
            children: [
              for (final d in _dests)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: d.tab == current,
                    label: d.label,
                    child: InkWell(
                      onTap: () => onSelect(d.tab),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CaretMark(active: d.tab == current, width: 20, height: 2),
                          const SizedBox(height: 7),
                          FaIcon(d.icon, size: 18, color: d.tab == current ? p.accent : p.textMuted),
                          const SizedBox(height: 4),
                          Text(
                            d.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(color: d.tab == current ? p.text : p.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 88,
      color: p.surface,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: Sp.x4),
            const OnyxLogo(size: 40),
            const SizedBox(height: Sp.x6),
            for (final d in _dests)
              Semantics(
                button: true,
                selected: d.tab == current,
                label: d.label,
                child: InkWell(
                  onTap: () => onSelect(d.tab),
                  child: SizedBox(
                    height: 68,
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: Motion.screen,
                          curve: Motion.standard,
                          width: 3,
                          height: d.tab == current ? 24 : 0,
                          decoration: BoxDecoration(color: p.accent, borderRadius: const BorderRadius.horizontal(right: Radius.circular(2))),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FaIcon(d.icon, size: 18, color: d.tab == current ? p.accent : p.textMuted),
                              const SizedBox(height: 6),
                              Text(d.label, style: context.text.labelSmall?.copyWith(color: d.tab == current ? p.text : p.textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
