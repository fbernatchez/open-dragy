package com.fb_engineering.open_dragy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var debugChannel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null
    private var cueAudioChannel: MethodChannel? = null
    private var debugReceiver: BroadcastReceiver? = null
    private var carCmdReceiver: BroadcastReceiver? = null
    private var mediaSession: ArmMediaSessionController? = null
    private var cueFocusRequest: AudioFocusRequest? = null
    private var cueFocusHeld: Boolean = false
    /** Linear cue gain (≥1). Above 1.0 briefly raises STREAM_MUSIC during focus. */
    private var cueGainLinear: Float = 1.0f
    private var savedMusicVolume: Int? = null

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
        cueAudioChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CUE_AUDIO_CHANNEL,
        )
        cueAudioChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireFocus" -> {
                    acquireCueAudioFocus()
                    result.success(null)
                }
                "releaseFocus" -> {
                    releaseCueAudioFocus()
                    result.success(null)
                }
                "setCueGain" -> {
                    val linear = call.argument<Number>("linear")?.toFloat() ?: 1.0f
                    cueGainLinear = linear.coerceIn(0.3f, 1.5f)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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

    /** Pause other media during cues; optionally boost stream volume when gain > 1. */
    private fun acquireCueAudioFocus() {
        val am = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return
        applyCueVolumeBoost(am)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (cueFocusRequest == null) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                cueFocusRequest = AudioFocusRequest.Builder(
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
                )
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener { }
                    .build()
            }
            val req = cueFocusRequest ?: return
            cueFocusHeld =
                am.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            cueFocusHeld = am.requestAudioFocus(
                null,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun releaseCueAudioFocus() {
        val am = getSystemService(AUDIO_SERVICE) as? AudioManager
        if (cueFocusHeld && am != null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    cueFocusRequest?.let { am.abandonAudioFocusRequest(it) }
                } else {
                    @Suppress("DEPRECATION")
                    am.abandonAudioFocus(null)
                }
            } catch (_: Exception) {
            }
        }
        cueFocusHeld = false
        restoreCueVolumeBoost(am)
    }

    private fun applyCueVolumeBoost(am: AudioManager) {
        if (cueGainLinear <= 1.001f) return
        if (savedMusicVolume != null) return
        try {
            val stream = AudioManager.STREAM_MUSIC
            val current = am.getStreamVolume(stream)
            val max = am.getStreamMaxVolume(stream)
            savedMusicVolume = current
            val boosted = (current * cueGainLinear).toInt().coerceIn(current, max)
            if (boosted > current) {
                am.setStreamVolume(stream, boosted, 0)
            }
        } catch (_: Exception) {
            savedMusicVolume = null
        }
    }

    private fun restoreCueVolumeBoost(am: AudioManager?) {
        val saved = savedMusicVolume ?: return
        savedMusicVolume = null
        if (am == null) return
        try {
            am.setStreamVolume(AudioManager.STREAM_MUSIC, saved, 0)
        } catch (_: Exception) {
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
                    // Parked HU / AA templates: always ARM+TTS (no headset-media toggle gate).
                    "arm" -> invokeFlutterMedia("parkedArmToggle")
                    "disarm" -> invokeFlutterMedia("parkedDisarm")
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
        private const val CUE_AUDIO_CHANNEL = "opendragy/cue_audio"
        const val EXTRA_CMD = "cmd"
    }
}
