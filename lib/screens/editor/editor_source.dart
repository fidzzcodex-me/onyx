import '../../core/api.dart';
import '../../core/models.dart';

class EditorDoc {
  const EditorDoc({
    required this.text,
    required this.encoding,
    required this.bom,
    required this.lineEnding,
    required this.modified,
    required this.readonly,
    required this.language,
    required this.encodings,
    required this.size,
  });

  final String text;
  final String encoding;
  final bool bom;
  final String lineEnding;
  final int modified;
  final bool readonly;
  final String language;
  final List<String> encodings;
  final int size;
}

abstract class EditorSource {
  const EditorSource();

  String get path;
  String get name;
  String? get origin;
  bool get remote;
  bool get canChangeEncoding;

  Future<EditorDoc> load(Api api, {String? encoding});

  Future<int> save(
    Api api, {
    required String text,
    required String encoding,
    required String lineEnding,
    required bool bom,
    required bool backup,
    int? expectedModified,
  });
}

class LocalEditorSource extends EditorSource {
  const LocalEditorSource(this.path);

  @override
  final String path;

  @override
  String get name => path.split('/').last;

  @override
  String? get origin => null;

  @override
  bool get remote => false;

  @override
  bool get canChangeEncoding => true;

  @override
  Future<EditorDoc> load(Api api, {String? encoding}) async {
    final m = await api.editor.read(path, encoding: encoding);
    return EditorDoc(
      text: (m['text'] ?? '') as String,
      encoding: (m['encoding'] ?? 'UTF-8') as String,
      bom: (m['bom'] ?? false) as bool,
      lineEnding: (m['lineEnding'] ?? 'lf') as String,
      modified: ((m['modified'] ?? 0) as num).toInt(),
      readonly: (m['readonly'] ?? false) as bool,
      language: (m['language'] ?? 'plaintext') as String,
      encodings: ((m['encodings'] ?? const <String>['UTF-8']) as List).map((e) => e.toString()).toList(),
      size: ((m['size'] ?? 0) as num).toInt(),
    );
  }

  @override
  Future<int> save(
    Api api, {
    required String text,
    required String encoding,
    required String lineEnding,
    required bool bom,
    required bool backup,
    int? expectedModified,
  }) async {
    final m = await api.editor.write(
      path: path,
      text: text,
      encoding: encoding,
      lineEnding: lineEnding,
      bom: bom,
      backup: backup,
      expectedModified: expectedModified,
    );
    return ((m['modified'] ?? 0) as num).toInt();
  }
}

class RemoteEditorSource extends EditorSource {
  const RemoteEditorSource({required this.sessionId, required this.path, required this.profile});

  final String sessionId;
  final ConnProfile profile;

  @override
  final String path;

  @override
  String get name => path.split('/').last;

  @override
  String? get origin => '${profile.username}@${profile.host}';

  @override
  bool get remote => true;

  @override
  bool get canChangeEncoding => false;

  @override
  Future<EditorDoc> load(Api api, {String? encoding}) async {
    final raw = await api.sftp.readText(sessionId, path);
    final crlf = raw.contains('\r\n');
    final text = crlf ? raw.replaceAll('\r\n', '\n') : raw;
    final language = await api.editor.language(path);
    return EditorDoc(
      text: text,
      encoding: 'UTF-8',
      bom: false,
      lineEnding: crlf ? 'crlf' : 'lf',
      modified: 0,
      readonly: false,
      language: language,
      encodings: const ['UTF-8'],
      size: raw.length,
    );
  }

  @override
  Future<int> save(
    Api api, {
    required String text,
    required String encoding,
    required String lineEnding,
    required bool bom,
    required bool backup,
    int? expectedModified,
  }) async {
    final body = lineEnding == 'crlf' ? text.replaceAll('\n', '\r\n') : text;
    await api.sftp.writeText(sessionId, path, body);
    return 0;
  }
}
