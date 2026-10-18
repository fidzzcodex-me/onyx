import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import 'settings.dart';

final apiProvider = Provider<Api>((ref) {
  final api = Api();
  ref.onDispose(api.fs.dispose);
  return api;
});

final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings>((ref) => SettingsNotifier(ref));
