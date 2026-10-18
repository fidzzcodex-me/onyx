import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../widgets/common.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.children, this.showBack = false, this.footer});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBack ? const OnyxAppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Sp.gutter, vertical: Sp.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: OnyxLogo(size: 56)),
                  const SizedBox(height: Sp.x6),
                  Text(title, style: context.text.headlineMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: Sp.x2),
                    Text(subtitle!, style: context.text.bodySmall),
                  ],
                  const SizedBox(height: Sp.x8),
                  ...children,
                  if (footer != null) ...[const SizedBox(height: Sp.x6), footer!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.x4),
      padding: const EdgeInsets.all(Sp.x3),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.12),
        borderRadius: Rd.c,
        border: Border.all(color: p.error.withValues(alpha: 0.4)),
      ),
      child: Text(message!, style: context.text.bodySmall?.copyWith(color: p.text)),
    );
  }
}
