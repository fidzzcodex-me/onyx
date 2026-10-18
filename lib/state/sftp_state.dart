import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import 'providers.dart';

@immutable
class TransfersState {
  const TransfersState({this.items = const [], this.error});

  final List<TransferItem> items;
  final String? error;

  int get activeCount => items.where((e) => e.active).length;
  int get finishedCount => items.where((e) => e.finished).length;
  double get speed => items.where((e) => e.state == 'running').fold(0.0, (a, b) => a + b.speed);
}

class TransfersNotifier extends StateNotifier<TransfersState> {
  TransfersNotifier(this._ref) : super(const TransfersState()) {
    _start();
  }

  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _debounce;
  bool _pending = false;

  void _start() {
    final api = _ref.read(apiProvider);
    _sub = api.sftp.events.listen(
      (event) {
        final type = event['type'];
        if (type == 'transfer') {
          _merge(TransferItem.fromMap(event));
        } else if (type == 'queue') {
          _schedule();
        }
      },
      onError: (Object e) => state = TransfersState(items: state.items, error: e.toString()),
    );
    refresh();
  }

  void _merge(TransferItem item) {
    final list = [...state.items];
    final index = list.indexWhere((e) => e.id == item.id);
    if (index < 0) {
      list.add(item);
    } else {
      list[index] = item;
    }
    state = TransfersState(items: list);
  }

  void _schedule() {
    if (_pending) return;
    _pending = true;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _pending = false;
      refresh();
    });
  }

  Future<void> refresh() async {
    try {
      final items = await _ref.read(apiProvider).sftp.queue();
      if (mounted) state = TransfersState(items: items);
    } catch (error) {
      if (mounted) state = TransfersState(items: state.items, error: error.toString());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

final transfersProvider = StateNotifierProvider<TransfersNotifier, TransfersState>((ref) => TransfersNotifier(ref));
