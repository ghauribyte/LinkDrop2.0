package com.linkdrop.linkdrop_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps a transfer alive for as long as it takes.
 *
 * The locks used to be held by MainActivity, which was wrong in two ways.
 *
 * First, the PARTIAL_WAKE_LOCK was acquired with a ten-minute timeout. A
 * multi-gigabyte file over a slow link takes longer than that, so the lock
 * expired *mid-transfer* — the CPU was allowed to sleep and the socket died,
 * with nothing in the app to explain it. Wake locks here are untimed and
 * released deterministically when the service stops instead.
 *
 * Second, and more fundamental: an Activity's locks do not protect a
 * *process*. Android is free to freeze or kill a backgrounded app under
 * memory pressure or Doze, and FLAG_KEEP_SCREEN_ON only applies while the
 * activity is actually visible. So a transfer survived only as long as the
 * user kept staring at the screen. A foreground service is the sanctioned way
 * to say "this app is doing user-visible work, leave it alone", and the
 * ongoing notification is the honest cost of that promise: the user can see
 * the transfer is running and how to get back to it.
 *
 * Started and stopped from the wake-lock method channel, so Dart's existing
 * acquire()/release() calls now drive this rather than raw locks.
 */
class TransferService : Service() {

    companion object {
        const val ACTION_START = "com.linkdrop.linkdrop_app.TRANSFER_START"
        const val ACTION_STOP = "com.linkdrop.linkdrop_app.TRANSFER_STOP"

        private const val CHANNEL_ID = "linkdrop_transfer"
        private const val NOTIFICATION_ID = 4711

        fun start(context: Context) {
            val intent = Intent(context, TransferService::class.java).apply {
                action = ACTION_START
            }
            // startForegroundService requires the service to call
            // startForeground() promptly or the system kills it with an ANR.
            // onStartCommand does that as its first act.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, TransferService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.startService(intent)
            } catch (e: Exception) {
                // Nothing running to stop, or the process is already going
                // away — either way the locks die with it.
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            releaseLocks()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundCompat()
        acquireLocks()

        // Deliberately not START_STICKY: if the process dies the transfer is
        // already gone, and restarting the service would leave a notification
        // claiming a transfer that no longer exists.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun startForegroundCompat() {
        ensureChannel()

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("LinkDrop transfer in progress")
            .setContentText("Keeping the connection awake until it finishes.")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setContentIntent(pending)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // API 34+ demands the type be declared at startForeground as
                // well as in the manifest, and throws if they disagree.
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Notifications denied, or a foreground-service start restriction.
            // The transfer can still proceed on the locks alone; it just loses
            // the protection from being killed while backgrounded.
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            // Already gone.
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        // LOW keeps it silent: this is a status indicator for something the
        // user just started, not an alert worth a sound and a heads-up.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "File transfers",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while a transfer is running so Android does " +
                "not sleep or kill the app partway through."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireLocks() {
        // Untimed, unlike the old ten-minute Activity lock that expired
        // mid-transfer. The service's lifetime is the timeout: onDestroy and
        // ACTION_STOP both release, and if the process dies the locks go with
        // it, so there is no path that leaks one indefinitely.
        try {
            val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (wakeLock?.isHeld != true) {
                wakeLock = power
                    ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "linkdrop:transfer")
                    ?.apply {
                        setReferenceCounted(false)
                        acquire()
                    }
            }
        } catch (e: Exception) {
            wakeLock = null
        }

        // A PARTIAL_WAKE_LOCK keeps the CPU running but says nothing about the
        // Wi-Fi radio, which is why holding one alone still lost transfers
        // when the screen went off: Android put Wi-Fi into power save and the
        // socket died.
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wifiLock?.isHeld != true) {
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wifi?.createWifiLock(mode, "linkdrop:transfer")?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (e: Exception) {
            wifiLock = null
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
            // Nothing useful to do if the release itself fails.
        }
        wakeLock = null

        try {
            wifiLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
            // Ignore.
        }
        wifiLock = null
    }
}
