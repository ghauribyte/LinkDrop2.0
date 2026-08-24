package com.linkdrop.linkdrop_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

private const val METHOD_CHANNEL = "linkdrop/wifi_direct"
private const val EVENT_CHANNEL = "linkdrop/wifi_direct_events"

class MainActivity : FlutterActivity() {
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

    override fun onDestroy() {
        unregisterReceiver()
        super.onDestroy()
    }
}
