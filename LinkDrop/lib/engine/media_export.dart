import 'dart:io';

import 'package:flutter/services.dart';

/// Publishes a finished download into the phone's shared media collections
/// so it turns up in the gallery / Downloads app.
///
/// FileReceiver writes into getApplicationDocumentsDirectory(), which on
/// Android is app-private internal storage (mode 0700). Nothing outside this
/// app can read that — not even the media scanner — so a received photo lands
/// on disk correctly and is still invisible to the gallery. This bridges that
/// gap via MethodChannel('linkdrop/media_store') → MainActivity.kt.
///
/// Android-only: on Linux the received directory is a normal visible folder
/// and needs no equivalent, so [export] is a no-op returning null.
class MediaExport {
  static const MethodChannel _channel = MethodChannel('linkdrop/media_store');

  /// True where publishing to a system media collection is a thing at all.
  static bool get isSupported => Platform.isAndroid;

  /// Copies [path] into the gallery (images/video/audio) or Downloads
  /// (everything else), filed under a "LinkDrop" subfolder.
  ///
  /// Call this only for *complete* files — publishing from onComplete rather
  /// than onProgress is what keeps Decision 014's "never leave a corrupt file
  /// behind" true for the gallery copy too.
  ///
  /// Returns the new content:// URI, or null if the export did not happen.
  /// Failures are reported through [onError] rather than thrown, matching the
  /// rest of the engine (Decision 008).
  static Future<String?> export({
    required String path,
    required String filename,
    void Function(String message)? onError,
  }) async {
    if (!isSupported) return null;

    try {
      return await _channel.invokeMethod<String>('export', {
        'path': path,
        'filename': filename,
      });
    } on PlatformException catch (e) {
      onError?.call(
        e.code == 'PERMISSION_DENIED'
            ? 'Saved to app storage, but not the gallery: storage permission denied.'
            : 'Saved to app storage, but could not add to gallery: ${e.message ?? e.code}',
      );
      return null;
    } on MissingPluginException {
      // Older build of the app without the native side wired up.
      return null;
    }
  }
}
