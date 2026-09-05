import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Asks for permission to show the transfer notification.
///
/// Android 13 (API 33) made POST_NOTIFICATIONS a runtime permission. Declaring
/// it in the manifest is not enough: without an explicit request the app is
/// left at `importance=NONE`, and the foreground service's ongoing
/// notification is silently hidden. Verified on a Pixel 7, where the service
/// was confirmed running (`isForeground=true`) while
/// `POST_NOTIFICATIONS: granted=false` meant nothing was ever visible.
///
/// The transfer itself does not depend on this. The foreground service still
/// runs and still protects a long transfer from being killed; a denial costs
/// only the user's ability to see that it is happening. So this never blocks
/// and never reports failure — asking again on a later transfer is the only
/// remedy, and Android stops showing the dialog after a denial anyway.
class NotificationPermission {
  /// Requests the permission if it has not been decided yet.
  ///
  /// Call this *before* a transfer starts rather than when the notification is
  /// posted: a system dialog appearing mid-transfer interrupts exactly the
  /// moment the user is watching progress.
  ///
  /// A no-op off Android, and on Android below 13 where the permission is
  /// granted at install time.
  static Future<void> ensureRequested() async {
    if (!Platform.isAndroid) return;

    try {
      final status = await Permission.notification.status;

      // Only ask when the user has not already answered. Re-requesting a
      // permanently denied permission does nothing on Android and asking
      // again after a grant is pure noise.
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Plugin missing or the platform refused the query. The transfer is
      // unaffected, so there is nothing worth surfacing.
    }
  }
}
