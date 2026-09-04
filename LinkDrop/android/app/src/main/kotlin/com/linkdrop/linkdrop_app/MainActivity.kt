package com.linkdrop.linkdrop_app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

private const val METHOD_CHANNEL = "linkdrop/wifi_direct"
private const val EVENT_CHANNEL = "linkdrop/wifi_direct_events"
private const val MEDIA_CHANNEL = "linkdrop/media_store"

class MainActivity : FlutterActivity() {
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        acquireMulticastLock()

        manager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
        channel = manager?.initialize(this, mainLooper, null)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(manager != null)
                    "startDiscovery" -> startDiscovery(result)
                    "stopDiscovery" -> stopDiscovery(result)
                    "connect" -> connect(call.argument("address"), result)
                    "disconnect" -> disconnect(result)
                    "removeGroup" -> removeGroup(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "export" -> exportToMediaStore(
                        call.argument("path"),
                        call.argument("filename"),
                        result
                    )
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    registerReceiver()
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                    unregisterReceiver()
                }
            })
    }

    private fun registerReceiver() {
        if (receiver != null) return
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        manager?.requestPeers(channel) { peers ->
                            val list = peers.deviceList.map { deviceToMap(it) }
                            eventSink?.success(mapOf("type" to "peers", "peers" to list))
                        }
                    }
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        manager?.requestConnectionInfo(channel) { info: WifiP2pInfo ->
                            eventSink?.success(
                                mapOf(
                                    "type" to "connection",
                                    "isConnected" to info.groupFormed,
                                    "isGroupOwner" to info.isGroupOwner,
                                    "groupOwnerAddress" to (info.groupOwnerAddress?.hostAddress ?: "")
                                )
                            )
                        }
                    }
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                        val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        eventSink?.success(mapOf("type" to "state", "enabled" to enabled))
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun unregisterReceiver() {
        receiver?.let { unregisterReceiver(it) }
        receiver = null
    }

    private fun deviceToMap(d: WifiP2pDevice): Map<String, Any> = mapOf(
        "name" to d.deviceName,
        "address" to d.deviceAddress,
        "status" to d.status
    )

    private fun startDiscovery(result: MethodChannel.Result) {
        val m = manager
        val c = channel
        if (m == null || c == null) {
            result.error("UNAVAILABLE", "Wi-Fi P2P not available", null)
            return
        }
        m.discoverPeers(c, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(true)
            override fun onFailure(reason: Int) = result.error("DISCOVERY_FAILED", "reason=$reason", null)
        })
    }

    private fun stopDiscovery(result: MethodChannel.Result) {
        val m = manager
        val c = channel
        if (m == null || c == null) {
            result.success(false)
            return
        }
        m.stopPeerDiscovery(c, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(true)
            override fun onFailure(reason: Int) = result.error("STOP_FAILED", "reason=$reason", null)
        })
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        val m = manager
        val c = channel
        if (m == null || c == null || address == null) {
            result.error("INVALID", "manager/channel/address missing", null)
            return
        }
        val config = WifiP2pConfig().apply { deviceAddress = address }
        m.connect(c, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(true)
            override fun onFailure(reason: Int) = result.error("CONNECT_FAILED", "reason=$reason", null)
        })
    }

    private fun disconnect(result: MethodChannel.Result) = removeGroup(result)

    private fun removeGroup(result: MethodChannel.Result) {
        val m = manager
        val c = channel
        if (m == null || c == null) {
            result.success(false)
            return
        }
        m.removeGroup(c, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(true)
            override fun onFailure(reason: Int) = result.error("REMOVE_FAILED", "reason=$reason", null)
        })
    }

    /**
     * Copies a finished download out of app-private storage and into the
     * phone's shared media collections, so received photos actually show up
     * in the gallery. FileReceiver writes to getApplicationDocumentsDirectory()
     * (mode 0700) — nothing outside this app can read that, by OS design, and
     * MediaStore never learns the file exists.
     *
     * Only complete files are published: the Dart side calls this from
     * onComplete, so a transfer that dies mid-write never reaches the gallery
     * (keeps Decision 014's "no corrupt file left behind" true end to end).
     *
     * Returns the content:// (or file://, pre-Q) URI as a String, or an error.
     */
    private fun exportToMediaStore(
        path: String?,
        filename: String?,
        result: MethodChannel.Result
    ) {
        if (path == null || filename == null) {
            result.error("INVALID", "path and filename are required", null)
            return
        }
        val source = File(path)
        if (!source.isFile) {
            result.error("NOT_FOUND", "no file at $path", null)
            return
        }
        try {
            val mime = mimeTypeOf(filename)
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                insertViaMediaStore(source, filename, mime)
            } else {
                insertLegacy(source, filename, mime)
            }
            if (uri == null) {
                result.error("EXPORT_FAILED", "MediaStore refused the insert", null)
            } else {
                result.success(uri.toString())
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "storage permission denied", null)
        } catch (e: Exception) {
            result.error("EXPORT_FAILED", e.message ?: e.toString(), null)
        }
    }

    private fun mimeTypeOf(filename: String): String {
        val ext = filename.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }

    /**
     * Where a given type belongs: images/video/audio go to the collections the
     * gallery actually scans, everything else to Downloads.
     */
    private fun collectionFor(mime: String): Pair<Uri, String> = when {
        mime.startsWith("image/") ->
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_PICTURES
        mime.startsWith("video/") ->
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_MOVIES
        mime.startsWith("audio/") ->
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_MUSIC
        else ->
            MediaStore.Downloads.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_DOWNLOADS
    }

    /**
     * Scoped storage (API 29+). No storage permission needed — the app owns
     * what it inserts. IS_PENDING hides the row until the bytes are all there,
     * so the gallery never shows a half-copied image. MediaStore de-duplicates
     * DISPLAY_NAME itself, appending "(1)" rather than clobbering.
     */
    private fun insertViaMediaStore(source: File, filename: String, mime: String): Uri? {
        val (collection, directory) = collectionFor(mime)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$directory/LinkDrop")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = contentResolver
        val uri = resolver.insert(collection, values) ?: return null
        try {
            val wrote = resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(source).use { it.copyTo(out) }
                true
            } ?: false
            if (!wrote) {
                resolver.delete(uri, null, null)
                return null
            }
        } catch (e: Exception) {
            // Don't leave a permanently-pending row behind on a failed copy.
            resolver.delete(uri, null, null)
            throw e
        }

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri
    }

    /**
     * Pre-scoped-storage (API 24-28): write into the public directory
     * directly, then tell the scanner. Needs WRITE_EXTERNAL_STORAGE, which is
     * declared with maxSdkVersion=28 and must already have been granted at
     * runtime — we surface a clear error rather than copying to a path the
     * gallery will never index.
     */
    private fun insertLegacy(source: File, filename: String, mime: String): Uri? {
        val granted = checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) throw SecurityException("WRITE_EXTERNAL_STORAGE not granted")

        val (_, directory) = collectionFor(mime)
        val dir = File(Environment.getExternalStoragePublicDirectory(directory), "LinkDrop")
        if (!dir.isDirectory && !dir.mkdirs()) return null

        // Match MediaStore's behaviour on API 29+: never overwrite.
        val base = filename.substringBeforeLast('.', filename)
        val ext = filename.substringAfterLast('.', "")
        var destination = File(dir, filename)
        var n = 1
        while (destination.exists()) {
            val candidate = if (ext.isEmpty()) "$base ($n)" else "$base ($n).$ext"
            destination = File(dir, candidate)
            n++
        }

        FileInputStream(source).use { input ->
            destination.outputStream().use { input.copyTo(it) }
        }
        MediaScannerConnection.scanFile(
            this,
            arrayOf(destination.absolutePath),
            arrayOf(mime),
            null
        )
        return Uri.fromFile(destination)
    }

    /**
     * Android's Wi-Fi driver drops incoming broadcast/multicast packets
     * unless a MulticastLock is held, to save power. LinkDrop's device
     * discovery (UDP broadcast on 6868) therefore *sends* fine without
     * one but often never *receives* peer announcements — so the phone
     * can be found by a laptop while showing an empty device list itself.
     *
     * Held for the lifetime of the activity rather than only around
     * discovery: this is a short-lived foreground transfer app, and
     * scoping it any tighter risks the lock being missing exactly when a
     * screen starts listening. Released in onDestroy.
     */
    private fun acquireMulticastLock() {
        if (multicastLock != null) return
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifi?.createMulticastLock("linkdrop-discovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            // Non-fatal: discovery may be unreliable, but transfers over a
            // directly-supplied IP (Wi-Fi Direct / hotspot) still work.
            multicastLock = null
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
            // Ignore — nothing useful to do if the release itself fails.
        }
        multicastLock = null
    }

    override fun onDestroy() {
        unregisterReceiver()
        releaseMulticastLock()
        super.onDestroy()
    }
}
