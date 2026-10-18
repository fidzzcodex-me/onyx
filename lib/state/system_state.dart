import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import 'providers.dart';

@immutable
class SystemState {
  const SystemState({
    this.device = const {},
    this.snapshot = const {},
    this.cpu = const [],
    this.ram = const [],
    this.rx = const [],
    this.tx = const [],
    this.error,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic> snapshot;
  final List<double> cpu;
  final List<double> ram;
  final List<double> rx;
  final List<double> tx;
  final String? error;

  Map<String, dynamic> section(String key) => asMap(snapshot[key]);

  SystemState copyWith({
    Map<String, dynamic>? device,
    Map<String, dynamic>? snapshot,
    List<double>? cpu,
    List<double>? ram,
    List<double>? rx,
    List<double>? tx,
    String? error,
    bool clearError = false,
  }) {
    return SystemState(
      device: device ?? this.device,
      snapshot: snapshot ?? this.snapshot,
      cpu: cpu ?? this.cpu,
      ram: ram ?? this.ram,
      rx: rx ?? this.rx,
      tx: tx ?? this.tx,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SystemNotifier extends StateNotifier<SystemState> {
  SystemNotifier(this._ref) : super(const SystemState());

  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _active = false;
  static const int _window = 60;

  Future<void> loadDevice() async {
    try {
      final device = await _ref.read(apiProvider).system.device();
      final snapshot = await _ref.read(apiProvider).system.snapshot();
      state = state.copyWith(device: device, clearError: true);
      _ingest(snapshot);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void setActive(bool active) {
    if (active == _active) return;
    _active = active;
    if (active) {
      _sub = _ref.read(apiProvider).system.events.where((e) => e['type'] == 'snapshot').listen(_ingest, onError: (Object e) {
        state = state.copyWith(error: e.toString());
      });
    } else {
      _sub?.cancel();
      _sub = null;
    }
  }

  List<double> _push(List<double> list, double value) {
    final next = [...list, value];
    return next.length > _window ? next.sublist(next.length - _window) : next;
  }

  void _ingest(Map<String, dynamic> snapshot) {
    final cpu = asMap(snapshot['cpu']);
    final mem = asMap(snapshot['memory']);
    final net = asMap(snapshot['network']);
    final cpuValue = ((cpu['percent'] ?? -1) as num).toDouble();
    final total = ((mem['total'] ?? 0) as num).toDouble();
    final used = ((mem['used'] ?? 0) as num).toDouble();
    state = state.copyWith(
      snapshot: snapshot,
      cpu: cpuValue >= 0 ? _push(state.cpu, cpuValue) : state.cpu,
      ram: total > 0 ? _push(state.ram, used * 100 / total) : state.ram,
      rx: _push(state.rx, ((net['rxRate'] ?? 0) as num).toDouble()),
      tx: _push(state.tx, ((net['txRate'] ?? 0) as num).toDouble()),
      clearError: true,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final systemProvider = StateNotifierProvider<SystemNotifier, SystemState>((ref) => SystemNotifier(ref));
