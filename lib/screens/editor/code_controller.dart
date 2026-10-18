import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/highlighter.dart';

class CodeController extends TextEditingController {
  CodeController({super.text});

  String language = 'plaintext';
  SyntaxColors colors = SyntaxColors.dark;
  List<TextRange> matches = const [];
  int current = -1;
  Color matchColor = const Color(0x554A90E2);
  Color currentColor = const Color(0xAA4A90E2);

  String? _cacheText;
  String? _cacheLanguage;
  SyntaxColors? _cacheColors;
  TextStyle? _cacheStyle;
  List<TextSpan> _cacheSpans = const [];

  void setMatches(List<TextRange> value, int currentIndex) {
    matches = value;
    current = currentIndex;
    notifyListeners();
  }

  void refreshStyle() {
    _cacheText = null;
    notifyListeners();
  }

  List<TextSpan> _spans(TextStyle base) {
    final t = text;
    if (_cacheText == t && _cacheLanguage == language && _cacheColors == colors && _cacheStyle == base) return _cacheSpans;
    _cacheSpans = Highlighter.spans(t, language, colors, base);
    _cacheText = t;
    _cacheLanguage = language;
    _cacheColors = colors;
    _cacheStyle = base;
    return _cacheSpans;
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle();
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final spans = text.isEmpty ? const <TextSpan>[] : _spans(base);
    if (matches.isEmpty) return TextSpan(style: base, children: spans);
    return TextSpan(style: base, children: _overlay(spans));
  }

  List<InlineSpan> _overlay(List<TextSpan> spans) {
    final out = <InlineSpan>[];
    var offset = 0;
    var m = 0;
    for (final span in spans) {
      final value = span.text ?? '';
      final spanEnd = offset + value.length;
      var cursor = offset;
      while (m < matches.length && matches[m].end <= cursor) {
        m++;
      }
      var k = m;
      while (cursor < spanEnd) {
        if (k >= matches.length || matches[k].start >= spanEnd) {
          out.add(TextSpan(text: value.substring(cursor - offset), style: span.style));
          cursor = spanEnd;
          break;
        }
        final range = matches[k];
        if (range.start > cursor) {
          out.add(TextSpan(text: value.substring(cursor - offset, range.start - offset), style: span.style));
          cursor = range.start;
        }
        final end = range.end < spanEnd ? range.end : spanEnd;
        out.add(
          TextSpan(
            text: value.substring(cursor - offset, end - offset),
            style: (span.style ?? const TextStyle()).copyWith(backgroundColor: k == current ? currentColor : matchColor),
          ),
        );
        cursor = end;
        if (range.end <= spanEnd) k++;
      }
      offset = spanEnd;
    }
    return out;
  }
}

class AutoIndentFormatter extends TextInputFormatter {
  AutoIndentFormatter(this.unit);

  final String unit;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cursor = newValue.selection.baseOffset;
    if (!newValue.selection.isCollapsed || cursor < 1) return newValue;
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    if (newValue.text[cursor - 1] != '\n') return newValue;
    final text = newValue.text;
    final lineStart = cursor < 2 ? 0 : text.lastIndexOf('\n', cursor - 2) + 1;
    final previous = text.substring(lineStart, cursor - 1);
    var indent = RegExp(r'^[ \t]*').stringMatch(previous) ?? '';
    final trimmed = previous.trimRight();
    final opens = trimmed.endsWith('{') || trimmed.endsWith('(') || trimmed.endsWith('[') || trimmed.endsWith(':');
    if (opens) indent += unit;
    if (indent.isEmpty) return newValue;
    final inserted = text.replaceRange(cursor, cursor, indent);
    return TextEditingValue(text: inserted, selection: TextSelection.collapsed(offset: cursor + indent.length));
  }
}
