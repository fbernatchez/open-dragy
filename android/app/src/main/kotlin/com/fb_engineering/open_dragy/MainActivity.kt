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
    private var debugReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        debugChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerDebugReceiver()
        handleDebugIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDebugIntent(intent)
    }

    override fun onDestroy() {
        unregisterDebugReceiver()
        super.onDestroy()
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
            // Defer until Flutter engine is up.
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
        private const val CHANNEL = "opendragy/debug"
        const val EXTRA_CMD = "cmd"
    }
}
