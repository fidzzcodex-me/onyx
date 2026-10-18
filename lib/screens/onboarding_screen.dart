import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/tokens.dart';
import '../state/auth_state.dart';
import '../widgets/common.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const _pages = [
    _Page(
      FontAwesomeIcons.terminal,
      'Terminal yang benar-benar jalan di ponsel',
      'Shell lokal dengan PTY nyata, beberapa tab sesi, dan tombol Ctrl, Alt, Tab, serta panah di atas keyboard.',
    ),
    _Page(
      FontAwesomeIcons.folderOpen,
      'Berkas lokal dan server dalam satu tempat',
      'Jelajahi penyimpanan, salin, kompres, cari, lalu sambung ke server lewat SFTP, SCP, FTP, atau WebDAV tanpa pindah aplikasi.',
    ),
    _Page(
      FontAwesomeIcons.shieldHalved,
      'Kunci tersimpan di perangkat',
      'Password server dan kunci SSH dienkripsi dengan Android Keystore. Tidak ada akun cloud dan tidak ada pelacakan.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_index < _pages.length - 1) {
      await _controller.nextPage(duration: Motion.screen, curve: Motion.standard);
    } else {
      await ref.read(authProvider.notifier).finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(Sp.x2),
                child: TextButton(
                  onPressed: () => ref.read(authProvider.notifier).finishOnboarding(),
                  child: const Text('Lewati'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: Sp.x8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (i == 0) const OnyxLogo(size: 88) else Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(color: p.surface, borderRadius: Rd.d, border: Border.all(color: p.border)),
                              child: Center(child: FaIcon(page.icon, size: 32, color: p.accent)),
                            ),
                            const SizedBox(height: Sp.x8),
                            Text(page.title, style: context.text.headlineMedium),
                            const SizedBox(height: Sp.x3),
                            Text(page.body, style: context.text.bodyMedium?.copyWith(color: p.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x4, Sp.x6, Sp.x6),
              child: Row(
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: AnimatedContainer(
                        duration: Motion.screen,
                        curve: Motion.standard,
                        width: i == _index ? 22 : 8,
                        height: 3,
                        decoration: BoxDecoration(color: i == _index ? p.accent : p.border, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  const Spacer(),
                  OnyxButton(label: last ? 'Mulai' : 'Lanjut', icon: last ? FontAwesomeIcons.check : FontAwesomeIcons.arrowRight, onPressed: _next),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
