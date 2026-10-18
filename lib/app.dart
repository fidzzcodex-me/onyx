import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/tokens.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/pin_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/splash_screen.dart';
import 'state/auth_state.dart';
import 'state/providers.dart';

class OnyxApp extends ConsumerStatefulWidget {
  const OnyxApp({super.key});

  @override
  ConsumerState<OnyxApp> createState() => _OnyxAppState();
}

class _OnyxAppState extends ConsumerState<OnyxApp> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(Motion.splash);
      await ref.read(authProvider.notifier).boot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final stage = ref.watch(authProvider.select((s) => s.stage));
    ref.listen<Stage>(authProvider.select((s) => s.stage), (previous, next) {
      if (next == Stage.locked || next == Stage.signedOut) {
        _navigator.currentState?.popUntil((route) => route.isFirst);
      }
    });
    return MaterialApp(
      title: 'Onyx',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      themeMode: settings.mode,
      theme: OnyxTheme.build(OnyxPalette.light),
      darkTheme: OnyxTheme.build(OnyxPalette.dark),
      builder: (context, child) {
        final p = Theme.of(context).extension<OnyxPalette>() ?? OnyxPalette.dark;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: p.bg,
            statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
          ),
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.of(context).textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AnimatedSwitcher(
        duration: Motion.screen,
        switchInCurve: Motion.standard,
        child: KeyedSubtree(key: ValueKey<Stage>(stage), child: _screenFor(stage)),
      ),
    );
  }

  Widget _screenFor(Stage stage) {
    switch (stage) {
      case Stage.booting:
        return const SplashScreen();
      case Stage.onboarding:
        return const OnboardingScreen();
      case Stage.signedOut:
        return const LoginScreen();
      case Stage.locked:
        return const PinScreen();
      case Stage.ready:
        return const ShellScreen();
    }
  }
}
