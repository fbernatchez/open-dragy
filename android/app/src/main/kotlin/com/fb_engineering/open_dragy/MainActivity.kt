package com.fb_engineering.open_dragy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var debugChannel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null
    private var debugReceiver: BroadcastReceiver? = null
    private var carCmdReceiver: BroadcastReceiver? = null
    private var mediaSession: ArmMediaSessionController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        debugChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEBUG_CHANNEL,
        )
        mediaChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_CHANNEL,
        )
        mediaChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    CarStateStore.enabled = enabled
                    CarStateStore.persist(this)
                    if (enabled) {
                        ensureMediaSession()
                    } else {
                        mediaSession?.stop()
                        mediaSession = null
                    }
                    broadcastCarState()
                    result.success(null)
                }
                "updateState" -> {
                    CarStateStore.armed = call.argument<Boolean>("armed") ?: false
                    CarStateStore.running = call.argument<Boolean>("running") ?: false
                    CarStateStore.speedKmh =
                        (call.argument<Number>("speedKmh")?.toDouble()) ?: 0.0
                    CarStateStore.targetLabel =
                        call.argument<String>("targetLabel") ?: "—"
                    CarStateStore.dragTargetName =
                        call.argument<String>("dragTargetName") ?: CarStateStore.dragTargetName
                    CarStateStore.lastResult = call.argument<String>("lastResult")
                    CarStateStore.finishToken =
                        call.argument<Number>("finishToken")?.toInt()
                            ?: CarStateStore.finishToken
                    CarStateStore.finishHeadline =
                        call.argument<String>("finishHeadline")
                            ?: CarStateStore.finishHeadline
                    @Suppress("UNCHECKED_CAST")
                    val finishLines = call.argument<List<*>>("finishLines")
                    if (finishLines != null) {
                        CarStateStore.finishLines =
                            finishLines.mapNotNull { it?.toString() }
                    }
                    val rawTargets = call.argument<List<*>>("dragTargets")
                    if (rawTargets != null) {
                        CarStateStore.dragTargets = rawTargets.mapNotNull { item ->
                            val m = item as? Map<*, *> ?: return@mapNotNull null
                            val name = m["name"]?.toString() ?: return@mapNotNull null
                            val label = m["label"]?.toString() ?: name
                            DragTargetOption(name, label)
                        }
                    }
                    CarStateStore.vehicleId =
                        call.argument<String>("vehicleId") ?: CarStateStore.vehicleId
                    CarStateStore.vehicleLabel =
                        call.argument<String>("vehicleLabel") ?: CarStateStore.vehicleLabel
                    val rawVehicles = call.argument<List<*>>("vehicles")
                    if (rawVehicles != null) {
                        CarStateStore.vehicles = rawVehicles.mapNotNull { item ->
                            val m = item as? Map<*, *> ?: return@mapNotNull null
                            val id = m["id"]?.toString() ?: return@mapNotNull null
                            val label = m["label"]?.toString() ?: id
                            CarVehicleOption(id, label)
                        }
                    }
                    val rawHistory = call.argument<List<*>>("history")
                    if (rawHistory != null) {
                        CarStateStore.history = rawHistory.mapNotNull { item ->
                            val m = item as? Map<*, *> ?: return@mapNotNull null
                            val id = m["id"]?.toString() ?: return@mapNotNull null
                            val title = m["title"]?.toString() ?: id
                            val subtitle = m["subtitle"]?.toString() ?: ""
                            val linesRaw = m["lines"] as? List<*> ?: emptyList<Any>()
                            CarHistoryEntry(
                                id = id,
                                title = title,
                                subtitle = subtitle,
                                lines = linesRaw.mapNotNull { it?.toString() },
                            )
                        }
                    }
                    CarStateStore.persist(this)
                    if (CarStateStore.enabled) {
                        ensureMediaSession()
                        mediaSession?.publishState()
                    }
                    broadcastCarState()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CarStateStore.load(this)
        registerDebugReceiver()
        registerCarCmdReceiver()
        handleDebugIntent(intent)
        if (CarStateStore.enabled) {
            ensureMediaSession()
        }
    }

    override fun onResume() {
        super.onResume()
        if (CarStateStore.enabled) {
            ensureMediaSession()
            mediaSession?.publishState()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDebugIntent(intent)
    }

    override fun onDestroy() {
        unregisterDebugReceiver()
        unregisterCarCmdReceiver()
        mediaSession?.stop()
        mediaSession = null
        super.onDestroy()
    }

    private fun ensureMediaSession() {
        if (mediaSession != null) return
        mediaSession = ArmMediaSessionController(
            applicationContext,
            onNext = { invokeFlutterMedia("mediaNext") },
            onPrevious = { invokeFlutterMedia("mediaPrevious") },
        ).also { it.start() }
    }

    private fun invokeFlutterMedia(method: String, args: Any? = null) {
        runOnUiThread {
            mediaChannel?.invokeMethod(method, args)
        }
    }

    private fun broadcastCarState() {
        val intent = Intent(OpenDragyMainScreen.ACTION_STATE_CHANGED)
            .setPackage(packageName)
        sendBroadcast(intent)
    }

    private fun registerCarCmdReceiver() {
        if (carCmdReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.getStringExtra(OpenDragyMainScreen.EXTRA_CMD)) {
                    "arm" -> invokeFlutterMedia("mediaNext")
                    "disarm" -> invokeFlutterMedia("mediaPrevious")
                    "setDragTarget" -> {
                        val name = intent.getStringExtra(OpenDragyMainScreen.EXTRA_TARGET)
                        if (name != null) {
                            invokeFlutterMedia(
                                "setDragTarget",
                                hashMapOf("name" to name),
                            )
                        }
                    }
                    "cycleDragTarget" -> invokeFlutterMedia("cycleDragTarget")
                    "setVehicle" -> {
                        val id = intent.getStringExtra(OpenDragyMainScreen.EXTRA_VEHICLE)
                        if (id != null) {
                            invokeFlutterMedia(
                                "setVehicle",
                                hashMapOf("id" to id),
                            )
                        }
                    }
                }
            }
        }
        carCmdReceiver = receiver
        val filter = IntentFilter(OpenDragyMainScreen.ACTION_CAR_COMMAND)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun unregisterCarCmdReceiver() {
        carCmdReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        carCmdReceiver = null
    }

    private fun registerDebugReceiver() {
        if (debugReceiver != null) return
        val action = "$packageName.DEBUG_CMD"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val cmd = intent.getStringExtra(EXTRA_CMD) ?: return
                val args = HashMap<String, Any?>()
                intent.extras?.keySet()?.forEach { key ->
                    if (key != EXTRA_CMD) {
                        args[key] = intent.extras?.get(key)
                    }
                }
                runOnUiThread {
                    debugChannel?.invokeMethod(cmd, args)
                }
            }
        }
        debugReceiver = receiver
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun unregisterDebugReceiver() {
        debugReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        debugReceiver = null
    }

    private fun handleDebugIntent(intent: Intent?) {
        if (intent == null) return
        val data = intent.data
        if (data != null && data.scheme == "opendragy") {
            val args = hashMapOf<String, Any?>("uri" to data.toString())
            window.decorView.post {
                debugChannel?.invokeMethod("deep_link", args)
            }
            return
        }
        val cmd = intent.getStringExtra(EXTRA_CMD)
        if (cmd != null) {
            window.decorView.post {
                debugChannel?.invokeMethod(cmd, emptyMap<String, Any?>())
            }
        }
    }

    companion object {
        private const val DEBUG_CHANNEL = "opendragy/debug"
        private const val MEDIA_CHANNEL = "opendragy/media_arm"
        const val EXTRA_CMD = "cmd"
    }
}
