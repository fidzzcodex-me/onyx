import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/models.dart';
import 'providers.dart';

enum Stage { booting, onboarding, signedOut, locked, ready }

@immutable
class AuthState {
  const AuthState({
    this.stage = Stage.booting,
    this.user,
    this.hasPin = false,
    this.biometricEnabled = false,
    this.biometricAvailable = false,
    this.hasAccounts = false,
    this.backgroundedAt,
  });

  final Stage stage;
  final AppUser? user;
  final bool hasPin;
  final bool biometricEnabled;
  final bool biometricAvailable;
  final bool hasAccounts;
  final DateTime? backgroundedAt;

  AuthState copyWith({
    Stage? stage,
    AppUser? user,
    bool clearUser = false,
    bool? hasPin,
    bool? biometricEnabled,
    bool? biometricAvailable,
    bool? hasAccounts,
    DateTime? backgroundedAt,
    bool clearBackgrounded = false,
  }) {
    return AuthState(
      stage: stage ?? this.stage,
      user: clearUser ? null : (user ?? this.user),
      hasPin: hasPin ?? this.hasPin,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      hasAccounts: hasAccounts ?? this.hasAccounts,
      backgroundedAt: clearBackgrounded ? null : (backgroundedAt ?? this.backgroundedAt),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> with WidgetsBindingObserver {
  AuthNotifier(this._ref) : super(const AuthState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> boot() async {
    final api = _ref.read(apiProvider).auth;
    final settings = _ref.read(settingsProvider);
    AppUser? user;
    var pin = false;
    var bioEnabled = false;
    var bioAvailable = false;
    var accounts = false;
    try {
      user = await api.currentUser();
      pin = await api.hasPin();
      bioEnabled = await api.isBiometricEnabled();
      bioAvailable = (await api.biometricAvailability()) == 'available';
      accounts = await api.hasAccounts();
    } catch (_) {}
    Stage stage;
    if (!settings.onboarded) {
      stage = Stage.onboarding;
    } else if (user == null) {
      stage = Stage.signedOut;
    } else if (pin) {
      stage = Stage.locked;
    } else {
      stage = Stage.ready;
    }
    state = state.copyWith(
      stage: stage,
      user: user,
      hasPin: pin,
      biometricEnabled: bioEnabled && bioAvailable,
      biometricAvailable: bioAvailable,
      hasAccounts: accounts,
    );
  }

  Future<void> finishOnboarding() async {
    await _ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboarded: true));
    state = state.copyWith(stage: state.user == null ? Stage.signedOut : Stage.ready);
  }

  Future<void> login(String email, String password, bool remember) async {
    final user = await _ref.read(apiProvider).auth.login(email, password, remember);
    _enter(user);
  }

  Future<void> register(String name, String email, String password) async {
    final user = await _ref.read(apiProvider).auth.register(name, email, password);
    state = state.copyWith(hasAccounts: true);
    _enter(user);
  }

  Future<void> guest() async {
    final user = await _ref.read(apiProvider).auth.loginGuest();
    _enter(user);
  }

  void _enter(AppUser user) {
    state = state.copyWith(
      user: user,
      stage: state.hasPin ? Stage.locked : Stage.ready,
      clearBackgrounded: true,
    );
  }

  Future<void> logout() async {
    await _ref.read(apiProvider).terminal.killAll().catchError((_) {});
    await _ref.read(apiProvider).auth.logout();
    state = state.copyWith(clearUser: true, stage: Stage.signedOut);
  }

  Future<void> refreshUser() async {
    final user = await _ref.read(apiProvider).auth.currentUser();
    if (user != null) state = state.copyWith(user: user);
  }

  Future<void> updateProfile(String name, String email) async {
    final user = await _ref.read(apiProvider).auth.updateProfile(name, email);
    state = state.copyWith(user: user);
  }

  Future<void> deleteAccount() async {
    await _ref.read(apiProvider).auth.deleteAccount();
    state = state.copyWith(clearUser: true, stage: Stage.signedOut, hasAccounts: false, hasPin: false);
  }

  Future<void> setPin(String pin) async {
    await _ref.read(apiProvider).auth.setPin(pin);
    state = state.copyWith(hasPin: true);
  }

  Future<void> clearPin() async {
    await _ref.read(apiProvider).auth.clearPin();
    await _ref.read(apiProvider).auth.setBiometricEnabled(false);
    state = state.copyWith(hasPin: false, biometricEnabled: false);
  }

  Future<void> setBiometric(bool enabled) async {
    await _ref.read(apiProvider).auth.setBiometricEnabled(enabled);
    state = state.copyWith(biometricEnabled: enabled);
  }

  Future<PinOutcome> unlockWithPin(String pin) async {
    try {
      final result = await _ref.read(apiProvider).auth.verifyPin(pin);
      if (result.ok) {
        state = state.copyWith(stage: Stage.ready, clearBackgrounded: true);
      }
      return PinOutcome(result.ok, result.lockedMs, result.attemptsLeft, null);
    } catch (error) {
      return PinOutcome(false, 0, 0, describeError(error));
    }
  }

  Future<bool> unlockWithBiometric() async {
    try {
      final ok = await _ref.read(apiProvider).auth.biometricAuthenticate(
            title: 'Buka Onyx',
            subtitle: 'Gunakan biometrik perangkat',
          );
      if (ok) state = state.copyWith(stage: Stage.ready, clearBackgrounded: true);
      return ok;
    } catch (_) {
      return false;
    }
  }

  void lockNow() {
    if (state.hasPin && state.stage == Stage.ready) state = state.copyWith(stage: Stage.locked);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!state.hasPin) return;
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      state = state.copyWith(backgroundedAt: DateTime.now());
    } else if (lifecycle == AppLifecycleState.resumed) {
      final since = state.backgroundedAt;
      if (since != null && state.stage == Stage.ready) {
        final timeout = _ref.read(settingsProvider).lockTimeoutSec;
        if (DateTime.now().difference(since).inSeconds >= timeout) {
          state = state.copyWith(stage: Stage.locked, clearBackgrounded: true);
          return;
        }
      }
      state = state.copyWith(clearBackgrounded: true);
    }
  }
}

class PinOutcome {
  const PinOutcome(this.ok, this.lockedMs, this.attemptsLeft, this.error);

  final bool ok;
  final int lockedMs;
  final int attemptsLeft;
  final String? error;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));
