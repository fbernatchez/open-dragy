package com.fb_engineering.open_dragy

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.TextView

/**
 * Landscape ARM screen for Android Auto parked launcher (CAR_LAUNCHER / games).
 * Sends the same CAR_CMD broadcasts as the Car App Library templates.
 * Requires OpenDragy (Flutter) running on the phone so ARM + TTS can execute.
 */
class ParkedArmActivity : Activity() {
    private lateinit var statusView: TextView
    private lateinit var metaView: TextView
    private lateinit var armButton: Button
    private var stateReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_parked_arm)

        statusView = findViewById(R.id.parkedStatus)
        metaView = findViewById(R.id.parkedMeta)
        armButton = findViewById(R.id.parkedArmButton)

        armButton.setOnClickListener { onArmPressed() }
        refreshUi()
    }

    override fun onStart() {
        super.onStart()
        CarStateStore.load(this)
        refreshUi()
        registerStateReceiver()
    }

    override fun onStop() {
        unregisterStateReceiver()
        super.onStop()
    }

    private fun onArmPressed() {
        CarStateStore.load(this)
        if (CarStateStore.running) return

        val cmd = if (CarStateStore.armed) "disarm" else "arm"
        val intent = Intent(OpenDragyMainScreen.ACTION_CAR_COMMAND)
            .setPackage(packageName)
            .putExtra(OpenDragyMainScreen.EXTRA_CMD, cmd)
            .putExtra(EXTRA_SOURCE, SOURCE_PARKED)
        sendBroadcast(intent)

        // Optimistic UI; Flutter will confirm via CAR_STATE.
        CarStateStore.armed = cmd == "arm"
        CarStateStore.persist(this)
        refreshUi()
    }

    private fun refreshUi() {
        CarStateStore.load(this)
        val status = CarStateStore.statusLine()
        statusView.text = status
        statusView.setTextColor(
            getColor(
                when {
                    CarStateStore.running -> R.color.parked_armed_glow
                    CarStateStore.armed -> R.color.parked_armed_glow
                    else -> R.color.parked_text
                },
            ),
        )

        val speed = String.format("%.0f km/h", CarStateStore.speedKmh)
        val target = CarStateStore.targetLabel.ifBlank { "—" }
        val vehicle = CarStateStore.vehicleLabel.ifBlank { "—" }
        metaView.text = "$speed · $target · $vehicle"

        val armedOrRunning = CarStateStore.armed || CarStateStore.running
        armButton.text = if (armedOrRunning) "DISARM" else "ARM"
        armButton.isEnabled = !CarStateStore.running
        armButton.backgroundTintList = null
        val bg = GradientDrawable().apply {
            cornerRadius = 24f * resources.displayMetrics.density
            setColor(
                getColor(
                    when {
                        CarStateStore.running -> R.color.parked_idle
                        CarStateStore.armed -> R.color.parked_disarm
                        else -> R.color.parked_arm
                    },
                ),
            )
        }
        armButton.background = bg
    }

    private fun registerStateReceiver() {
        if (stateReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                refreshUi()
            }
        }
        stateReceiver = receiver
        val filter = IntentFilter(OpenDragyMainScreen.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun unregisterStateReceiver() {
        stateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        stateReceiver = null
    }

    companion object {
        const val EXTRA_SOURCE = "source"
        const val SOURCE_PARKED = "parked"
    }
}
