import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback.dart';

class ViewerScaffold extends StatelessWidget {
  const ViewerScaffold({
    super.key,
    required this.path,
    required this.body,
    this.actions = const [],
    this.bottom,
    this.overlayBar = false,
    this.background,
  });

  final String path;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;
  final bool overlayBar;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bar = OnyxAppBar(ribbon: PathRibbon(path: path), title: baseName(path), actions: actions);
    return Scaffold(
      backgroundColor: background ?? p.bg,
      extendBodyBehindAppBar: overlayBar,
      appBar: bar,
      body: body,
      bottomNavigationBar: bottom,
    );
  }
}

class ViewerActions extends ConsumerWidget {
  const ViewerActions({super.key, required this.entry, this.extra = const []});

  final FileEntry entry;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...extra,
        IconButton(
          tooltip: 'Bagikan',
          onPressed: () => runGuarded(context, () => api.fs.share(entry.path, mime: entry.mime.isEmpty ? null : entry.mime)),
          icon: const FaIcon(FontAwesomeIcons.shareNodes, size: 17),
        ),
        IconButton(
          tooltip: 'Buka dengan aplikasi lain',
          onPressed: () => runGuarded(context, () => api.fs.open(entry.path, mime: entry.mime.isEmpty ? null : entry.mime, chooser: true)),
          icon: const FaIcon(FontAwesomeIcons.arrowUpRightFromSquare, size: 16),
        ),
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.x1 + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, child: Text(label, style: context.text.bodySmall)),
          Expanded(
            child: SelectableText(
              value,
              style: mono ? OnyxFonts.mono(size: 12, color: p.text) : context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showInfoSheet(BuildContext context, String title, List<MapEntry<String, String>> rows) {
  return showSheet<void>(
    context,
    builder: (ctx) => SheetFrame(
      title: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final r in rows) InfoRow(r.key, r.value)],
        ),
      ),
    ),
  );
}

String formatMillis(int ms) {
  final total = Duration(milliseconds: ms < 0 ? 0 : ms);
  final h = total.inHours;
  final m = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${total.inMinutes}:$s';
}
