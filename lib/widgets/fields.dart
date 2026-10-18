import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/tokens.dart';

class OnyxField extends StatefulWidget {
  const OnyxField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.error,
    this.obscure = false,
    this.keyboard,
    this.action,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.maxLines = 1,
    this.mono = false,
    this.formatters,
    this.autofillHints,
    this.enabled = true,
    this.prefix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? error;
  final bool obscure;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int maxLines;
  final bool mono;
  final List<TextInputFormatter>? formatters;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final Widget? prefix;

  @override
  State<OnyxField> createState() => _OnyxFieldState();
}

class _OnyxFieldState extends State<OnyxField> {
  late bool _hidden = widget.obscure;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = widget.mono ? Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 14) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: Motion.screen,
              curve: Motion.standard,
              width: _focus.hasFocus ? 10 : 0,
              height: 2,
              margin: EdgeInsets.only(right: _focus.hasFocus ? 6 : 0),
              color: p.accent,
            ),
            Text(widget.label, style: context.text.labelMedium?.copyWith(color: _focus.hasFocus ? p.accent : p.textSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          obscureText: _hidden,
          keyboardType: widget.keyboard,
          textInputAction: widget.action,
          autofocus: widget.autofocus,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          minLines: 1,
          inputFormatters: widget.formatters,
          autofillHints: widget.autofillHints,
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          autocorrect: !widget.obscure && !widget.mono,
          enableSuggestions: !widget.obscure && !widget.mono,
          style: style,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.error,
            helperText: widget.helper,
            helperMaxLines: 3,
            errorMaxLines: 3,
            prefixIcon: widget.prefix,
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Tampilkan' : 'Sembunyikan',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: FaIcon(_hidden ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash, size: 16, color: p.textMuted),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle, this.icon});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
          child: Row(
            children: [
              if (icon != null) ...[SizedBox(width: 24, child: FaIcon(icon, size: 16, color: p.textSecondary)), const SizedBox(width: Sp.x3)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.bodyMedium),
                    if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.title, this.subtitle, this.icon, this.onTap, this.trailing, this.danger = false});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x2),
          child: Row(
            children: [
              if (icon != null) ...[SizedBox(width: 24, child: FaIcon(icon, size: 16, color: danger ? p.error : p.textSecondary)), const SizedBox(width: Sp.x3)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.bodyMedium?.copyWith(color: danger ? p.error : p.text)),
                    if (subtitle != null) Text(subtitle!, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              trailing ?? (onTap != null ? FaIcon(FontAwesomeIcons.chevronRight, size: 12, color: p.textMuted) : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: Rd.c, border: Border.all(color: p.border)),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(entry.key),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: Motion.dialog,
                  constraints: const BoxConstraints(minHeight: 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x2),
                  decoration: BoxDecoration(
                    color: entry.key == value ? p.elevated : Colors.transparent,
                    borderRadius: BorderRadius.circular(Rd.control - 3),
                    border: entry.key == value ? Border.all(color: p.accent.withValues(alpha: 0.6)) : null,
                  ),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelMedium?.copyWith(color: entry.key == value ? p.text : p.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
