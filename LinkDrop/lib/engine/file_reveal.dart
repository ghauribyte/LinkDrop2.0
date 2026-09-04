import 'dart:io';

import 'package:flutter/services.dart';

/// Opens a received file where the user expects to find it: the gallery /
/// a viewer on Android, the file manager with the file selected on Linux.
///
/// UI-free per Decision 008 — reports failure through [onError] and returns
/// false rather than throwing, since "your file manager could not be
/// launched" must never look like the transfer went wrong.
class FileReveal {
  static const MethodChannel _channel = MethodChannel('linkdrop/reveal');

  /// Opens the file itself — the gallery viewer on Android, the default
  /// application on Linux.
  ///
  /// [contentUri] is the Android MediaStore URI, and is the only handle
  /// that still works there once the staging copy has been moved into the
  /// gallery. [path] is used on Linux and as the Android fallback.
  static Future<bool> open({
    required String path,
    String? contentUri,
    void Function(String message)? onError,
  }) async {
    if (Platform.isAndroid) {
      return _invoke('open', {'path': path, 'uri': contentUri}, onError);
    }
    if (Platform.isLinux) {
      if (!await File(path).exists()) {
        onError?.call('That file is no longer at $path.');
        return false;
      }
      return _run('xdg-open', [path], onError);
    }
    return false;
  }

  /// Shows the file *in its folder*, selected, rather than opening it.
  ///
  /// On Linux this asks the file manager over D-Bus, which is the only way
  /// to get the file highlighted rather than just opening the directory and
  /// leaving the user to find it. Falls back to opening the containing
  /// folder when no D-Bus file manager answers.
  ///
  /// Android has no file-manager equivalent to select an item, so this
  /// falls through to [open].
  static Future<bool> revealInFolder({
    required String path,
    String? contentUri,
    void Function(String message)? onError,
  }) async {
    if (!Platform.isLinux) {
      return open(path: path, contentUri: contentUri, onError: onError);
    }

    final file = File(path);
    if (!await file.exists()) {
      onError?.call('That file is no longer at $path.');
      return false;
    }

    final uri = Uri.file(path).toString();
    final viaDbus = await _run(
      'dbus-send',
      [
        '--session',
        '--dest=org.freedesktop.FileManager1',
        '--type=method_call',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        'array:string:$uri',
        'string:',
      ],
      null,
    );
    if (viaDbus) return true;

    // No D-Bus file manager — open the containing directory instead. The
    // file is not selected, but the user still lands in the right place.
    return _run('xdg-open', [file.parent.path], onError);
  }

  static Future<bool> _invoke(
    String method,
    Map<String, dynamic> args,
    void Function(String message)? onError,
  ) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException catch (e) {
      onError?.call('Could not open the file: ${e.message ?? e.code}');
      return false;
    } on MissingPluginException {
      onError?.call('This build cannot open files yet.');
      return false;
    }
  }

  static Future<bool> _run(
    String executable,
    List<String> args,
    void Function(String message)? onError,
  ) async {
    try {
      final result = await Process.run(executable, args);
      if (result.exitCode != 0) {
        onError?.call(
          'Could not open the file: ${(result.stderr as String).trim()}',
        );
        return false;
      }
      return true;
    } catch (e) {
      onError?.call('Could not open the file: $e');
      return false;
    }
  }
}
