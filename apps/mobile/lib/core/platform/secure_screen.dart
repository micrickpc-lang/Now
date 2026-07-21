import 'package:flutter/services.dart';

abstract final class SecureScreen {
  static const _channel = MethodChannel('ru.seychas/privacy');
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod<void>('secureScreen', true);
    } on MissingPluginException {
      /* Platform has no screenshot control. */
    }
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod<void>('secureScreen', false);
    } on MissingPluginException {
      /* Platform has no screenshot control. */
    }
  }
}
