import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppTab { dashboard, terminal, files, servers, tools }

final tabProvider = StateProvider<AppTab>((ref) => AppTab.dashboard);

final pendingFilesPathProvider = StateProvider<String?>((ref) => null);
final pendingTerminalCwdProvider = StateProvider<String?>((ref) => null);

final tabBackProvider = Provider<Map<AppTab, bool Function()>>((ref) => <AppTab, bool Function()>{});
