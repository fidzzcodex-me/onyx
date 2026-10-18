import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  final container = ProviderContainer();
  await container.read(settingsProvider.notifier).load();
  runApp(UncontrolledProviderScope(container: container, child: const OnyxApp()));
}
