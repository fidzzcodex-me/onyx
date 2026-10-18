import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/errors.dart';
import '../core/tokens.dart';
import 'common.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  final p = context.palette;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: error ? 5 : 3),
        margin: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
        content: Row(
          children: [
            FaIcon(error ? FontAwesomeIcons.circleExclamation : FontAwesomeIcons.circleCheck, size: 16, color: error ? p.error : p.success),
            const SizedBox(width: Sp.x3),
            Expanded(child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
}

void toastError(BuildContext context, Object error) => toast(context, describeError(error), error: true);

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Lanjutkan',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
      actions: [
        OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx, false)),
        OnyxButton(
          label: confirmLabel,
          kind: danger ? OnyxButtonKind.danger : OnyxButtonKind.primary,
          compact: true,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  String confirmLabel = 'Simpan',
  String? Function(String value)? validator,
  bool obscure = false,
  TextInputType keyboard = TextInputType.text,
}) {
  final controller = TextEditingController(text: initial);
  controller.selection = TextSelection(baseOffset: 0, extentOffset: initial.contains('.') && initial.lastIndexOf('.') > 0 ? initial.lastIndexOf('.') : initial.length);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final value = controller.text.trim();
          final problem = validator?.call(value) ?? (value.isEmpty ? 'Isian tidak boleh kosong' : null);
          if (problem != null) {
            setState(() => error = problem);
            return;
          }
          Navigator.pop(ctx, value);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: obscure,
            keyboardType: keyboard,
            decoration: InputDecoration(hintText: hint, errorText: error),
            onSubmitted: (_) => submit(),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
          actions: [
            OnyxButton(label: 'Batal', kind: OnyxButtonKind.ghost, compact: true, onPressed: () => Navigator.pop(ctx)),
            OnyxButton(label: confirmLabel, compact: true, onPressed: submit),
          ],
        );
      },
    ),
  );
}

class SheetAction {
  const SheetAction(this.label, this.icon, this.onTap, {this.danger = false, this.subtitle});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final String? subtitle;
}

Future<T?> showSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scroll = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * 0.92),
    transitionAnimationController: null,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: builder(ctx),
      ),
    ),
  );
}

Future<void> showActionSheet(BuildContext context, {String? title, String? subtitle, required List<SheetAction> actions}) {
  return showSheet<void>(
    context,
    builder: (ctx) {
      final p = ctx.palette;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Grabber(),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x4, Sp.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ctx.text.titleMedium),
                  if (subtitle != null) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ctx.text.bodySmall),
                ],
              ),
            ),
          Divider(color: p.divider),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: Sp.x2),
              children: [
                for (final a in actions)
                  InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      a.onTap();
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: Sp.tap),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
                        child: Row(
                          children: [
                            SizedBox(width: 24, child: FaIcon(a.icon, size: 16, color: a.danger ? p.error : p.textSecondary)),
                            const SizedBox(width: Sp.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.label, style: ctx.text.bodyMedium?.copyWith(color: a.danger ? p.error : p.text)),
                                  if (a.subtitle != null) Text(a.subtitle!, style: ctx.text.bodySmall),
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
        ],
      );
    },
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: Sp.x3),
        width: 36,
        height: 4,
        decoration: BoxDecoration(color: context.palette.border, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.child, this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x2, Sp.x2),
          child: Row(
            children: [
              Expanded(child: Text(title, style: context.text.titleLarge)),
              ...actions,
              IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.pop(context),
                icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
              ),
            ],
          ),
        ),
        Divider(color: context.palette.divider),
        Flexible(child: child),
      ],
    );
  }
}

Future<void> runGuarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) toast(context, success);
  } catch (error) {
    if (context.mounted) toastError(context, error);
  }
}
