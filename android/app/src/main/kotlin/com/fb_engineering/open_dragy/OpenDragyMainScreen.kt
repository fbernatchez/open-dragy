package com.fb_engineering.open_dragy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
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
        return try {
            buildTemplate()
        } catch (e: Exception) {
            // Never crash the phone process because AA templates are strict.
            Log.e(TAG, "AA template error", e)
            MessageTemplate.Builder(e.message ?: "Template error")
                .setTitle("OpenDragy")
                .setHeaderAction(Action.APP_ICON)
                .addAction(
                    Action.Builder()
                        .setTitle("Retry")
                        .setOnClickListener { invalidate() }
                        .build(),
                )
                .build()
        }
    }

    private fun buildTemplate(): Template {
        CarStateStore.load(carContext)
        val status = CarStateStore.statusLine()
        val speed = String.format("%.0f km/h", CarStateStore.speedKmh)
        val last = CarStateStore.lastResult

        // ListTemplate (not Pane): rows may be clickable; ActionStrip max 1 custom title.
        val list = ItemList.Builder()
        list.addItem(
            Row.Builder()
                .setTitle(status)
                .addText(speed)
                .build(),
        )
        list.addItem(
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
        list.addItem(
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
        list.addItem(
            Row.Builder()
                .setTitle("History")
                .addText("Recent runs")
                .setOnClickListener {
                    screenManager.push(OpenDragyHistoryScreen(carContext))
                }
                .build(),
        )
        if (!last.isNullOrBlank()) {
            list.addItem(
                Row.Builder()
                    .setTitle("Last")
                    .addText(last)
                    .setOnClickListener {
                        screenManager.push(OpenDragyFinishScreen(carContext))
                    }
                    .build(),
            )
        }

        // ActionStrip cannot use setBackgroundColor (only Message/Pane primary actions).
        val armTitle = if (CarStateStore.armed || CarStateStore.running) "DISARM" else "ARM"
        val strip = ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle(armTitle)
                    .setOnClickListener {
                        val intent = Intent(ACTION_CAR_COMMAND)
                            .setPackage(carContext.packageName)
                        intent.putExtra(
                            EXTRA_CMD,
                            if (CarStateStore.armed || CarStateStore.running) {
                                "disarm"
                            } else {
                                "arm"
                            },
                        )
                        carContext.sendBroadcast(intent)
                    }
                    .build(),
            )

        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle("OpenDragy")
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(strip.build())
            .build()
    }

    companion object {
        private const val TAG = "OpenDragyAA"
        const val ACTION_STATE_CHANGED = "com.fb_engineering.open_dragy.CAR_STATE"
        const val ACTION_CAR_COMMAND = "com.fb_engineering.open_dragy.CAR_CMD"
        const val EXTRA_CMD = "cmd"
        const val EXTRA_TARGET = "target"
        const val EXTRA_VEHICLE = "vehicle"
    }
}
