import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme.dart';
import '../core/tokens.dart';

class CaretMark extends StatelessWidget {
  const CaretMark({super.key, this.active = true, this.width = 14, this.height = 2, this.color});

  final bool active;
  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: Motion.screen,
      curve: Motion.standard,
      width: active ? width : 0,
      height: height,
      decoration: BoxDecoration(color: color ?? p.accent, borderRadius: BorderRadius.circular(1)),
    );
  }
}

class PathRibbon extends StatelessWidget {
  const PathRibbon({super.key, required this.path, this.prefix, this.onTap, this.onSegment});

  final String path;
  final String? prefix;
  final VoidCallback? onTap;
  final void Function(String path)? onSegment;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = OnyxFonts.mono(size: 12, color: p.textSecondary);
    final strong = OnyxFonts.mono(size: 12, color: p.text, weight: FontWeight.w600);
    final parts = path.split('/').where((e) => e.isNotEmpty).toList();
    final children = <Widget>[];
    if (prefix != null) {
      children.add(Text('$prefix ', style: OnyxFonts.mono(size: 12, color: p.accent, weight: FontWeight.w600)));
    }
    String acc = '';
    children.add(_segment('/', '/', style, strong, parts.isEmpty, context));
    for (var i = 0; i < parts.length; i++) {
      acc = '$acc/${parts[i]}';
      final last = i == parts.length - 1;
      children.add(_segment(parts[i], acc, style, strong, last, context));
      if (!last) children.add(Text('/', style: style));
    }
    children.add(const SizedBox(width: 2));
    children.add(Container(width: 7, height: 13, color: p.accent));
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 28,
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.04, 0.94, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
          ),
        ),
      ),
    );
  }

  Widget _segment(String label, String target, TextStyle style, TextStyle strong, bool last, BuildContext context) {
    final text = Text(label, style: last ? strong : style);
    if (onSegment == null || last) return text;
    return GestureDetector(
      onTap: () => onSegment!(target),
      behavior: HitTestBehavior.opaque,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: text),
    );
  }
}

class OnyxAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OnyxAppBar({super.key, this.title, this.ribbon, this.actions = const [], this.leading, this.automaticLeading = true, this.bottom});

  final String? title;
  final Widget? ribbon;
  final List<Widget> actions;
  final Widget? leading;
  final bool automaticLeading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (ribbon != null ? 20 : 0) + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: kToolbarHeight + (ribbon != null ? 20 : 0),
              child: Row(
                children: [
                  if (leading != null)
                    leading!
                  else if (automaticLeading && Navigator.of(context).canPop())
                    IconButton(
                      tooltip: 'Kembali',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 18),
                    )
                  else
                    const SizedBox(width: Sp.x4),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleLarge),
                        if (ribbon != null) ribbon!,
                      ],
                    ),
                  ),
                  ...actions,
                  const SizedBox(width: Sp.x1),
                ],
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}

enum OnyxButtonKind { primary, secondary, ghost, danger }

class OnyxButton extends StatefulWidget {
  const OnyxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = OnyxButtonKind.primary,
    this.loading = false,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final OnyxButtonKind kind;
  final bool loading;
  final bool expand;
  final bool compact;

  @override
  State<OnyxButton> createState() => _OnyxButtonState();
}

class _OnyxButtonState extends State<OnyxButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onPressed != null && !widget.loading;
    Color bg;
    Color fg;
    BorderSide side = BorderSide.none;
    switch (widget.kind) {
      case OnyxButtonKind.primary:
        bg = p.accent;
        fg = p.onAccent;
      case OnyxButtonKind.secondary:
        bg = p.surfaceAlt;
        fg = p.text;
        side = BorderSide(color: p.border);
      case OnyxButtonKind.ghost:
        bg = Colors.transparent;
        fg = p.accent;
      case OnyxButtonKind.danger:
        bg = p.error.withValues(alpha: 0.14);
        fg = p.error;
        side = BorderSide(color: p.error.withValues(alpha: 0.5));
    }
    if (!enabled && !widget.loading) {
      bg = widget.kind == OnyxButtonKind.ghost ? Colors.transparent : p.surfaceAlt;
      fg = p.textDisabled;
      side = BorderSide.none;
    }
    final height = widget.compact ? 40.0 : Sp.tap;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (widget.icon != null)
          FaIcon(widget.icon, size: 15, color: fg),
        if (widget.loading || widget.icon != null) const SizedBox(width: Sp.x2),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelLarge?.copyWith(color: fg, fontSize: widget.compact ? 13 : 15),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: Motion.press,
          child: Container(
            constraints: BoxConstraints(minHeight: height, minWidth: widget.compact ? 0 : 88),
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? Sp.x3 : Sp.x4),
            decoration: BoxDecoration(color: bg, borderRadius: Rd.c, border: Border.fromBorderSide(side)),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}

class OnyxCard extends StatelessWidget {
  const OnyxCard({super.key, required this.child, this.padding = const EdgeInsets.all(Sp.x4), this.onTap, this.onLongPress, this.selected = false, this.margin});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final box = AnimatedContainer(
      duration: Motion.dialog,
      margin: margin,
      decoration: BoxDecoration(
        color: selected ? p.accentMuted.withValues(alpha: p.isDark ? 0.5 : 0.7) : p.surface,
        borderRadius: Rd.k,
        border: Border.all(color: selected ? p.accent : p.border),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null && onLongPress == null) return box;
    return GestureDetector(onTap: onTap, onLongPress: onLongPress, behavior: HitTestBehavior.opaque, child: box);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(Sp.x4, Sp.x6, Sp.x4, Sp.x2)});

  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title.toUpperCase(), style: context.text.labelSmall?.copyWith(letterSpacing: 0.8))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.x8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: p.surface, borderRadius: Rd.d, border: Border.all(color: p.border)),
                child: Center(child: FaIcon(icon, size: 24, color: p.textMuted)),
              ),
              const SizedBox(height: Sp.x4),
              Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
              if (message != null) ...[
                const SizedBox(height: Sp.x2),
                Text(message!, textAlign: TextAlign.center, style: context.text.bodySmall),
              ],
              if (action != null) ...[const SizedBox(height: Sp.x6), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.title = 'Tidak dapat memuat'});

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: FontAwesomeIcons.triangleExclamation,
      title: title,
      message: message,
      action: onRetry == null ? null : OnyxButton(label: 'Coba lagi', icon: FontAwesomeIcons.rotateRight, kind: OnyxButtonKind.secondary, onPressed: onRetry),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (label != null) ...[const SizedBox(height: Sp.x3), Text(label!, style: context.text.bodySmall)],
        ],
      ),
    );
  }
}

class OnyxLogo extends StatelessWidget {
  const OnyxLogo({super.key, this.size = 96, this.wordmark = false});

  final double size;
  final bool wordmark;

  @override
  Widget build(BuildContext context) {
    final asset = wordmark ? 'assets/logo/logo_horizontal.png' : 'assets/logo/logomark.png';
    return Image.asset(asset, width: wordmark ? size * 2.4 : size, height: size, fit: BoxFit.contain, semanticLabel: 'Onyx');
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x2, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[FaIcon(icon, size: 10, color: c), const SizedBox(width: 4)],
          Text(label, style: context.text.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class RatioBar extends StatelessWidget {
  const RatioBar({super.key, required this.value, this.color, this.height = 6});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: p.surfaceAlt),
          AnimatedFractionallySizedBox(
            duration: Motion.screen,
            curve: Motion.standard,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: height, color: color ?? p.accent),
          ),
        ],
      ),
    );
  }
}

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color, this.max = 100, this.height = 44});

  final List<double> values;
  final Color? color;
  final double max;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color ?? p.accent, p.border, max)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.grid, this.max);

  final List<double> values;
  final Color color;
  final Color grid;
  final double max;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), base);
    if (values.length < 2) return;
    final top = math.max(max, values.reduce(math.max));
    final dx = size.width / (values.length - 1);
    final path = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - (values[i].clamp(0, top) / top) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values || old.color != color;
}

class Staggered extends StatelessWidget {
  const Staggered({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final int delay = (Motion.stagger.inMilliseconds * math.min(index, 8)).toInt();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delay),
      curve: Motion.standard,
      builder: (context, t, child) {
        final eased = ((t * (220 + delay) - delay) / 220).clamp(0.0, 1.0);
        return Opacity(opacity: eased, child: Transform.translate(offset: Offset(0, (1 - eased) * 8), child: child));
      },
      child: child,
    );
  }
}
