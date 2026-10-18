import 'package:flutter/services.dart';

class OnyxError implements Exception {
  OnyxError(this.code, this.message);

  final String code;
  final String message;

  factory OnyxError.from(Object error) {
    if (error is OnyxError) return error;
    if (error is PlatformException) return OnyxError(error.code, error.message ?? error.code);
    if (error is MissingPluginException) {
      return OnyxError('unavailable', 'Fitur native belum tersedia di build ini.');
    }
    return OnyxError('unknown', error.toString());
  }

  @override
  String toString() => message;
}

String describeError(Object error) => OnyxError.from(error).message;
