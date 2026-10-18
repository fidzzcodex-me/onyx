import 'package:flutter/material.dart';

import 'tokens.dart';

@immutable
class SyntaxColors {
  const SyntaxColors({
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.type,
    required this.key,
    required this.tag,
    required this.added,
    required this.removed,
    required this.heading,
  });

  final Color keyword;
  final Color string;
  final Color comment;
  final Color number;
  final Color type;
  final Color key;
  final Color tag;
  final Color added;
  final Color removed;
  final Color heading;

  static const dark = SyntaxColors(
    keyword: Color(0xFF6CB0F0),
    string: Color(0xFFD9A07E),
    comment: Color(0xFF7FA06E),
    number: Color(0xFFB5CEA8),
    type: Color(0xFF4EC9B0),
    key: Color(0xFF9CDCFE),
    tag: Color(0xFF5BA0F2),
    added: Color(0xFF6CC070),
    removed: Color(0xFFEF7B78),
    heading: Color(0xFF6CB0F0),
  );

  static const light = SyntaxColors(
    keyword: Color(0xFF0B57B0),
    string: Color(0xFFA33B16),
    comment: Color(0xFF4F7A3C),
    number: Color(0xFF0A6B45),
    type: Color(0xFF136F7A),
    key: Color(0xFF1B5FA6),
    tag: Color(0xFF0B57B0),
    added: Color(0xFF1B6E2B),
    removed: Color(0xFFB3261E),
    heading: Color(0xFF0B57B0),
  );

  static SyntaxColors of(OnyxPalette p) => p.isDark ? dark : light;
}

class _Lang {
  const _Lang({
    this.keywords = const {},
    this.types = const {},
    this.line = const [],
    this.blockStart,
    this.blockEnd,
    this.strings = const ['"', "'"],
    this.triple = false,
    this.caseInsensitive = false,
  });

  final Set<String> keywords;
  final Set<String> types;
  final List<String> line;
  final String? blockStart;
  final String? blockEnd;
  final List<String> strings;
  final bool triple;
  final bool caseInsensitive;
}

const _cLike = {
  'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default', 'break', 'continue', 'return', 'goto', 'new', 'delete',
  'try', 'catch', 'finally', 'throw', 'throws', 'class', 'struct', 'enum', 'union', 'interface', 'namespace', 'using',
  'import', 'package', 'public', 'private', 'protected', 'static', 'final', 'const', 'volatile', 'virtual', 'override',
  'abstract', 'extends', 'implements', 'this', 'super', 'null', 'true', 'false', 'void', 'typedef', 'template', 'typename',
  'operator', 'inline', 'extern', 'sizeof', 'async', 'await', 'yield', 'in', 'is', 'as', 'out', 'ref', 'readonly', 'lock',
  'internal', 'sealed', 'partial', 'get', 'set', 'var', 'let',
};

const _cTypes = {
  'int', 'long', 'short', 'byte', 'char', 'float', 'double', 'bool', 'boolean', 'string', 'String', 'unsigned', 'signed',
  'size_t', 'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t', 'int8_t', 'int16_t', 'int32_t', 'int64_t', 'auto', 'object',
  'decimal', 'Object', 'List', 'Map', 'Set',
};

final Map<String, _Lang> _langs = {
  'kotlin': const _Lang(
    keywords: {
      'fun', 'val', 'var', 'class', 'object', 'interface', 'enum', 'data', 'sealed', 'open', 'abstract', 'override', 'private',
      'public', 'protected', 'internal', 'if', 'else', 'when', 'for', 'while', 'do', 'return', 'break', 'continue', 'try',
      'catch', 'finally', 'throw', 'import', 'package', 'in', 'is', 'as', 'null', 'true', 'false', 'this', 'super', 'companion',
      'init', 'constructor', 'suspend', 'inline', 'lateinit', 'by', 'lazy', 'typealias', 'const', 'vararg', 'where', 'out',
    },
    types: {'Int', 'Long', 'Short', 'Byte', 'Float', 'Double', 'Boolean', 'String', 'Char', 'Unit', 'Any', 'Nothing', 'List', 'Map', 'Set', 'Array'},
    line: ['//'],
    blockStart: '/*',
    blockEnd: '*/',
    triple: true,
  ),
  'java': const _Lang(keywords: _cLike, types: _cTypes, line: ['//'], blockStart: '/*', blockEnd: '*/'),
  'c': const _Lang(keywords: _cLike, types: _cTypes, line: ['//'], blockStart: '/*', blockEnd: '*/'),
  'cpp': const _Lang(keywords: _cLike, types: _cTypes, line: ['//'], blockStart: '/*', blockEnd: '*/'),
  'cs': const _Lang(keywords: _cLike, types: _cTypes, line: ['//'], blockStart: '/*', blockEnd: '*/'),
  'swift': const _Lang(
    keywords: {
      'func', 'let', 'var', 'class', 'struct', 'enum', 'protocol', 'extension', 'if', 'else', 'guard', 'switch', 'case',
      'default', 'for', 'while', 'repeat', 'return', 'break', 'continue', 'import', 'init', 'self', 'super', 'nil', 'true',
      'false', 'try', 'catch', 'throw', 'throws', 'public', 'private', 'internal', 'static', 'in', 'is', 'as', 'async', 'await',
    },
    types: {'Int', 'Double', 'Float', 'Bool', 'String', 'Character', 'Array', 'Dictionary', 'Set', 'Optional', 'Any'},
    line: ['//'],
    blockStart: '/*',
    blockEnd: '*/',
  ),
  'dart': const _Lang(
    keywords: {
      'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue', 'covariant',
      'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory', 'false',
      'final', 'finally', 'for', 'get', 'if', 'implements', 'import', 'in', 'is', 'late', 'library', 'mixin', 'new', 'null',
      'on', 'operator', 'part', 'required', 'rethrow', 'return', 'set', 'static', 'super', 'switch', 'sync', 'this', 'throw',
      'true', 'try', 'typedef', 'var', 'void', 'while', 'with', 'yield',
    },
    types: {'int', 'double', 'num', 'bool', 'String', 'List', 'Map', 'Set', 'Future', 'Stream', 'Object', 'Widget'},
    line: ['//'],
    blockStart: '/*',
    blockEnd: '*/',
    triple: true,
  ),
  'javascript': const _Lang(
    keywords: {
      'function', 'const', 'let', 'var', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default', 'break', 'continue',
      'return', 'new', 'delete', 'typeof', 'instanceof', 'in', 'of', 'try', 'catch', 'finally', 'throw', 'class', 'extends',
      'super', 'this', 'import', 'export', 'from', 'as', 'async', 'await', 'yield', 'null', 'undefined', 'true', 'false',
      'void', 'static', 'get', 'set', 'interface', 'type', 'enum', 'implements', 'public', 'private', 'protected', 'readonly',
    },
    types: {'string', 'number', 'boolean', 'any', 'unknown', 'never', 'Promise', 'Array', 'Object', 'Map', 'Set'},
    strings: ['"', "'", '`'],
    line: ['//'],
    blockStart: '/*',
    blockEnd: '*/',
  ),
  'python': const _Lang(
    keywords: {
      'def', 'class', 'if', 'elif', 'else', 'for', 'while', 'break', 'continue', 'return', 'import', 'from', 'as', 'try',
      'except', 'finally', 'raise', 'with', 'pass', 'lambda', 'yield', 'global', 'nonlocal', 'in', 'is', 'not', 'and', 'or',
      'None', 'True', 'False', 'async', 'await', 'del', 'assert', 'self', 'match', 'case',
    },
    types: {'int', 'float', 'str', 'bool', 'list', 'dict', 'set', 'tuple', 'bytes', 'object', 'type'},
    line: ['#'],
    triple: true,
  ),
  'ruby': const _Lang(
    keywords: {
      'def', 'end', 'class', 'module', 'if', 'elsif', 'else', 'unless', 'case', 'when', 'while', 'until', 'for', 'in', 'do',
      'begin', 'rescue', 'ensure', 'return', 'yield', 'require', 'require_relative', 'include', 'extend', 'attr_accessor',
      'attr_reader', 'attr_writer', 'self', 'nil', 'true', 'false', 'and', 'or', 'not', 'then', 'lambda', 'proc', 'puts',
    },
    line: ['#'],
  ),
  'go': const _Lang(
    keywords: {
      'package', 'import', 'func', 'var', 'const', 'type', 'struct', 'interface', 'map', 'chan', 'if', 'else', 'for', 'range',
      'switch', 'case', 'default', 'break', 'continue', 'return', 'go', 'defer', 'select', 'fallthrough', 'goto', 'nil',
      'true', 'false',
    },
    types: {'int', 'int8', 'int16', 'int32', 'int64', 'uint', 'uint8', 'uint16', 'uint32', 'uint64', 'float32', 'float64', 'string', 'bool', 'byte', 'rune', 'error', 'any'},
    strings: ['"', "'", '`'],
    line: ['//'],
    blockStart: '/*',
    blockEnd: '*/',
  ),
  'rust': const _Lang(
    keywords: {
      'fn', 'let', 'mut', 'const', 'static', 'struct', 'enum', 'trait', 'impl', 'type', 'use', 'mod', 'pub', 'crate', 'self',
      'Self', 'super', 'if', 'else', 'match', 'for', 'while', 'loop', 'break', 'continue', 'return', 'in', 'as', 'ref', 'move',
      'async', 'await', 'dyn', 'where', 'unsafe', 'extern', 'true', 'false',
    },
    types: {'i8', 'i16', 'i32', 'i64', 'i128', 'isize', 'u8', 'u16', 'u32', 'u64', 'u128', 'usize', 'f32', 'f64', 'bool', 'char', 'str', 'String', 'Vec', 'Option', 'Result', 'Box'},
    line: ['//'],
    blockStart: '/*',
    blockEnd: '*/',
  ),
  'php': const _Lang(
    keywords: {
      'function', 'class', 'interface', 'trait', 'extends', 'implements', 'public', 'private', 'protected', 'static', 'abstract',
      'final', 'const', 'if', 'elseif', 'else', 'for', 'foreach', 'while', 'do', 'switch', 'case', 'default', 'break', 'continue',
      'return', 'new', 'try', 'catch', 'finally', 'throw', 'use', 'namespace', 'echo', 'print', 'null', 'true', 'false', 'as',
      'array', 'isset', 'empty', 'require', 'require_once', 'include', 'include_once',
    },
    line: ['//', '#'],
    blockStart: '/*',
    blockEnd: '*/',
  ),
  'lua': const _Lang(
    keywords: {
      'function', 'local', 'end', 'if', 'then', 'else', 'elseif', 'for', 'while', 'do', 'repeat', 'until', 'return', 'break',
      'in', 'and', 'or', 'not', 'nil', 'true', 'false',
    },
    line: ['--'],
    blockStart: '--[[',
    blockEnd: ']]',
  ),
  'bash': const _Lang(
    keywords: {
      'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done', 'case', 'esac', 'in', 'function', 'return',
      'exit', 'export', 'local', 'readonly', 'declare', 'source', 'alias', 'unset', 'shift', 'break', 'continue', 'echo',
      'cd', 'set', 'trap', 'eval', 'exec',
    },
    line: ['#'],
    strings: ['"', "'"],
  ),
  'sql': const _Lang(
    keywords: {
      'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create', 'table', 'alter', 'drop',
      'index', 'view', 'join', 'inner', 'left', 'right', 'outer', 'full', 'on', 'group', 'by', 'order', 'having', 'limit',
      'offset', 'union', 'all', 'distinct', 'as', 'and', 'or', 'not', 'null', 'is', 'in', 'like', 'between', 'exists',
      'primary', 'key', 'foreign', 'references', 'default', 'unique', 'check', 'constraint', 'begin', 'commit', 'rollback',
      'case', 'when', 'then', 'else', 'end', 'asc', 'desc', 'count', 'sum', 'avg', 'min', 'max',
    },
    types: {'int', 'integer', 'bigint', 'smallint', 'text', 'varchar', 'char', 'boolean', 'date', 'timestamp', 'real', 'float', 'blob', 'numeric'},
    line: ['--'],
    blockStart: '/*',
    blockEnd: '*/',
    caseInsensitive: true,
  ),
  'gradle': const _Lang(
    keywords: {
      'plugins', 'id', 'apply', 'dependencies', 'implementation', 'api', 'compileOnly', 'testImplementation', 'repositories',
      'android', 'defaultConfig', 'buildTypes', 'release', 'debug', 'task', 'def', 'val', 'var', 'if', 'else', 'for', 'return',
      'true', 'false', 'null', 'ext', 'sourceSets', 'kotlin', 'group', 'version',
    },
    line: ['//'],
    blockStart: '/*',
    blockEnd: '*/',
  ),
  'ini': const _Lang(line: ['#', ';'], keywords: {'true', 'false', 'yes', 'no', 'on', 'off'}),
  'yaml': const _Lang(line: ['#'], keywords: {'true', 'false', 'null', 'yes', 'no', 'on', 'off'}),
  'dockerfile': const _Lang(
    keywords: {'FROM', 'RUN', 'CMD', 'ENTRYPOINT', 'COPY', 'ADD', 'ENV', 'ARG', 'WORKDIR', 'EXPOSE', 'VOLUME', 'USER', 'LABEL', 'AS', 'HEALTHCHECK', 'SHELL'},
    line: ['#'],
  ),
  'makefile': const _Lang(
    keywords: {'ifeq', 'ifneq', 'ifdef', 'ifndef', 'else', 'endif', 'include', 'define', 'endef', 'export', 'override', 'PHONY'},
    line: ['#'],
  ),
  'css': const _Lang(line: [], blockStart: '/*', blockEnd: '*/', keywords: {'important', 'inherit', 'initial', 'none', 'auto'}),
  'json': const _Lang(keywords: {'true', 'false', 'null'}, strings: ['"']),
};

const _aliases = {
  'js': 'javascript',
  'ts': 'javascript',
  'typescript': 'javascript',
  'kt': 'kotlin',
  'py': 'python',
  'rb': 'ruby',
  'rs': 'rust',
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'yml': 'yaml',
  'toml': 'ini',
  'properties': 'ini',
  'conf': 'ini',
  'scss': 'css',
  'csharp': 'cs',
  'c++': 'cpp',
};

const _markupLanguages = {'html', 'xml', 'svg'};

class Highlighter {
  static const int maxChars = 160000;

  static bool supports(String language) {
    final key = _aliases[language] ?? language;
    return _langs.containsKey(key) || _markupLanguages.contains(key) || key == 'diff' || key == 'markdown';
  }

  static List<TextSpan> spans(String text, String language, SyntaxColors c, TextStyle base) {
    if (text.isEmpty) return const [];
    final key = _aliases[language] ?? language;
    if (text.length > maxChars) return [TextSpan(text: text, style: base)];
    if (key == 'diff') return _diff(text, c, base);
    if (key == 'markdown') return _markdown(text, c, base);
    if (_markupLanguages.contains(key)) return _markup(text, c, base);
    final lang = _langs[key];
    if (lang == null) return [TextSpan(text: text, style: base)];
    return _code(text, key, lang, c, base);
  }

  static final Map<String, RegExp> _compiled = {};

  static RegExp _regexFor(String key, _Lang lang) {
    return _compiled.putIfAbsent(key, () {
      final parts = <String>[];
      if (lang.blockStart != null) {
        parts.add('(?<block>${RegExp.escape(lang.blockStart!)}[\\s\\S]*?(?:${RegExp.escape(lang.blockEnd!)}|\$))');
      }
      if (lang.line.isNotEmpty) {
        parts.add('(?<line>(?:${lang.line.map(RegExp.escape).join('|')})[^\\n]*)');
      }
      if (lang.triple) {
        parts.add('(?<triple>"""[\\s\\S]*?(?:"""|\$)|\'\'\'[\\s\\S]*?(?:\'\'\'|\$))');
      }
      final quoted = <String>[];
      for (final q in lang.strings) {
        final e = RegExp.escape(q);
        if (q == '`') {
          quoted.add('$e(?:\\\\[\\s\\S]|[^$e\\\\])*(?:$e|\$)');
        } else {
          quoted.add('$e(?:\\\\.|[^$e\\\\\\n])*(?:$e|(?=\\n)|\$)');
        }
      }
      if (quoted.isNotEmpty) parts.add('(?<string>${quoted.join('|')})');
      parts.add('(?<number>\\b(?:0[xX][0-9a-fA-F_]+|\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?[fFlLuU]*)\\b)');
      if (key == 'bash') parts.add('(?<variable>\\\$(?:\\{[^}]*\\}|[A-Za-z_][A-Za-z0-9_]*|[0-9@#?*!\$-]))');
      parts.add('(?<word>[A-Za-z_\\\$][A-Za-z0-9_\\\$]*)');
      return RegExp(parts.join('|'));
    });
  }

  static List<TextSpan> _code(String text, String key, _Lang lang, SyntaxColors c, TextStyle base) {
    final regex = _regexFor(key, lang);
    final out = <TextSpan>[];
    var cursor = 0;
    void plain(int end) {
      if (end > cursor) out.add(TextSpan(text: text.substring(cursor, end), style: base));
    }

    for (final m in regex.allMatches(text)) {
      if (m.end == m.start) continue;
      Color? color;
      final String? group = m.groupNames.cast<String?>().firstWhere((g) => m.namedGroup(g!) != null, orElse: () => null);
      switch (group) {
        case 'block':
        case 'line':
          color = c.comment;
        case 'string':
        case 'triple':
          color = c.string;
        case 'number':
          color = c.number;
        case 'variable':
          color = c.key;
        case 'word':
          final word = m.group(0)!;
          final probe = lang.caseInsensitive ? word.toLowerCase() : word;
          if (lang.keywords.contains(probe)) {
            color = c.keyword;
          } else if (lang.types.contains(word)) {
            color = c.type;
          } else if (word.isNotEmpty && word.codeUnitAt(0) >= 65 && word.codeUnitAt(0) <= 90 && key != 'bash' && key != 'sql') {
            color = c.type;
          }
        default:
          break;
      }
      if (key == 'json' && group == 'string') {
        var look = m.end;
        while (look < text.length && (text.codeUnitAt(look) == 32 || text.codeUnitAt(look) == 9)) {
          look++;
        }
        if (look < text.length && text.codeUnitAt(look) == 58) color = c.key;
      }
      if ((key == 'yaml' || key == 'ini') && group == 'word') {
        var look = m.end;
        while (look < text.length && (text.codeUnitAt(look) == 32 || text.codeUnitAt(look) == 9)) {
          look++;
        }
        if (look < text.length && (text.codeUnitAt(look) == 58 || text.codeUnitAt(look) == 61)) color = c.key;
      }
      if (color == null) continue;
      plain(m.start);
      out.add(TextSpan(text: m.group(0), style: base.copyWith(color: color)));
      cursor = m.end;
    }
    plain(text.length);
    return out;
  }

  static final RegExp _markupRe = RegExp(
    r'(?<comment><!--[\s\S]*?(?:-->|$))|(?<tag></?[A-Za-z][\w:.-]*)|(?<attr>\s[A-Za-z_:][\w:.-]*(?==))|(?<string>"[^"]*"|' "'[^']*')",
  );

  static List<TextSpan> _markup(String text, SyntaxColors c, TextStyle base) {
    final out = <TextSpan>[];
    var cursor = 0;
    for (final m in _markupRe.allMatches(text)) {
      final Color color;
      if (m.namedGroup('comment') != null) {
        color = c.comment;
      } else if (m.namedGroup('tag') != null) {
        color = c.tag;
      } else if (m.namedGroup('attr') != null) {
        color = c.key;
      } else {
        color = c.string;
      }
      if (m.start > cursor) out.add(TextSpan(text: text.substring(cursor, m.start), style: base));
      out.add(TextSpan(text: m.group(0), style: base.copyWith(color: color)));
      cursor = m.end;
    }
    if (cursor < text.length) out.add(TextSpan(text: text.substring(cursor), style: base));
    return out;
  }

  static List<TextSpan> _diff(String text, SyntaxColors c, TextStyle base) {
    final out = <TextSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      Color? color;
      if (line.startsWith('+++') || line.startsWith('---') || line.startsWith('diff ') || line.startsWith('index ')) {
        color = c.heading;
      } else if (line.startsWith('@@')) {
        color = c.type;
      } else if (line.startsWith('+')) {
        color = c.added;
      } else if (line.startsWith('-')) {
        color = c.removed;
      }
      out.add(TextSpan(text: i == lines.length - 1 ? line : '$line\n', style: color == null ? base : base.copyWith(color: color)));
    }
    return out;
  }

  static List<TextSpan> _markdown(String text, SyntaxColors c, TextStyle base) {
    final out = <TextSpan>[];
    final lines = text.split('\n');
    var fenced = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final tail = i == lines.length - 1 ? line : '$line\n';
      Color? color;
      FontWeight? weight;
      if (line.trimLeft().startsWith('```')) {
        fenced = !fenced;
        color = c.comment;
      } else if (fenced) {
        color = c.string;
      } else if (line.startsWith('#')) {
        color = c.heading;
        weight = FontWeight.w700;
      } else if (line.startsWith('>')) {
        color = c.comment;
      } else if (RegExp(r'^\s*([-*+]|\d+\.)\s').hasMatch(line)) {
        color = c.keyword;
      }
      out.add(TextSpan(text: tail, style: color == null ? base : base.copyWith(color: color, fontWeight: weight)));
    }
    return out;
  }
}
