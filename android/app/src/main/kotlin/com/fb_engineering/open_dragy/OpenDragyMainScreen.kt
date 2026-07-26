package com.fb_engineering.open_dragy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

class OpenDragyMainScreen(carContext: CarContext) : Screen(carContext) {
    private var lastSeenFinishToken: Int = -1

    private val refreshReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            CarStateStore.load(carContext)
            maybeShowFinish()
            invalidate()
        }
    }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                CarStateStore.load(carContext)
                lastSeenFinishToken = CarStateStore.finishToken
                val filter = IntentFilter(ACTION_STATE_CHANGED)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    carContext.registerReceiver(
                        refreshReceiver,
                        filter,
                        Context.RECEIVER_NOT_EXPORTED,
                    )
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    carContext.registerReceiver(refreshReceiver, filter)
                }
            }

            override fun onStop(owner: LifecycleOwner) {
                try {
                    carContext.unregisterReceiver(refreshReceiver)
                } catch (_: Exception) {
                }
            }
        })
    }

    private fun maybeShowFinish() {
        val token = CarStateStore.finishToken
        if (token > 0 && token != lastSeenFinishToken) {
            lastSeenFinishToken = token
            // Avoid stacking multiple finish screens.
            if (screenManager.stackSize <= 1) {
                screenManager.push(OpenDragyFinishScreen(carContext))
            }
        }
    }

    override fun onGetTemplate(): Template {
        CarStateStore.load(carContext)
        val status = CarStateStore.statusLine()
        val speed = String.format("%.0f km/h", CarStateStore.speedKmh)
        val last = CarStateStore.lastResult

        val pane = Pane.Builder()
            .addRow(
                Row.Builder()
                    .setTitle(status)
                    .addText(speed)
                    .build(),
            )
            .addRow(
                Row.Builder()
                    .setTitle("Target")
                    .addText(CarStateStore.targetLabel)
                    .setOnClickListener {
                        if (!CarStateStore.running) {
                            screenManager.push(OpenDragyTargetScreen(carContext))
                        }
                    }
                    .build(),
            )
            .addRow(
                Row.Builder()
                    .setTitle("Vehicle")
                    .addText(CarStateStore.vehicleLabel.ifBlank { "—" })
                    .setOnClickListener {
                        if (!CarStateStore.running) {
                            screenManager.push(OpenDragyVehicleScreen(carContext))
                        }
                    }
                    .build(),
            )
        if (!last.isNullOrBlank()) {
            pane.addRow(
                Row.Builder()
                    .setTitle("Last")
                    .addText(last)
                    .setOnClickListener {
                        screenManager.push(OpenDragyFinishScreen(carContext))
                    }
                    .build(),
            )
        }

        val armAction = Action.Builder()
            .setTitle(if (CarStateStore.armed || CarStateStore.running) "DISARM" else "ARM")
            .setBackgroundColor(
                if (CarStateStore.armed || CarStateStore.running) {
                    CarColor.RED
                } else {
                    CarColor.GREEN
                },
            )
            .setOnClickListener {
                val intent = Intent(ACTION_CAR_COMMAND).setPackage(carContext.packageName)
                intent.putExtra(
                    EXTRA_CMD,
                    if (CarStateStore.armed || CarStateStore.running) "disarm" else "arm",
                )
                carContext.sendBroadcast(intent)
            }
            .build()

        pane.addAction(armAction)

        if (!CarStateStore.running) {
            pane.addAction(
                Action.Builder()
                    .setTitle("Next target")
                    .setOnClickListener {
                        val intent = Intent(ACTION_CAR_COMMAND)
                            .setPackage(carContext.packageName)
                        intent.putExtra(EXTRA_CMD, "cycleDragTarget")
                        carContext.sendBroadcast(intent)
                    }
                    .build(),
            )
        }

        val strip = ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle("Targets")
                    .setOnClickListener {
                        if (!CarStateStore.running) {
                            screenManager.push(OpenDragyTargetScreen(carContext))
                        }
                    }
                    .build(),
            )
            .addAction(
                Action.Builder()
                    .setTitle("History")
                    .setOnClickListener {
                        screenManager.push(OpenDragyHistoryScreen(carContext))
                    }
                    .build(),
            )

        return PaneTemplate.Builder(pane.build())
            .setTitle("OpenDragy")
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(strip.build())
            .build()
    }

    companion object {
        const val ACTION_STATE_CHANGED = "com.fb_engineering.open_dragy.CAR_STATE"
        const val ACTION_CAR_COMMAND = "com.fb_engineering.open_dragy.CAR_CMD"
        const val EXTRA_CMD = "cmd"
        const val EXTRA_TARGET = "target"
        const val EXTRA_VEHICLE = "vehicle"
    }
}
