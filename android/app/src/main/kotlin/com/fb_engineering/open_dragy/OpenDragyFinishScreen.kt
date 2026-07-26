package com.fb_engineering.open_dragy

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/**
 * Post-run celebration. AA cannot draw a real checkered flag —
 * green Done + audio cues carry the finish signal.
 */
class OpenDragyFinishScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        CarStateStore.load(carContext)
        val headline = CarStateStore.finishHeadline.ifBlank {
            CarStateStore.lastResult ?: "Run complete"
        }

        return MessageTemplate.Builder(headline)
            .setTitle("FINISH")
            .setHeaderAction(Action.BACK)
            .addAction(
                Action.Builder()
                    .setTitle("Done")
                    .setBackgroundColor(CarColor.GREEN)
                    .setOnClickListener { screenManager.pop() }
                    .build(),
            )
            .addAction(
                Action.Builder()
                    .setTitle("Metrics")
                    .setOnClickListener {
                        screenManager.push(OpenDragyMetricsScreen(carContext))
                    }
                    .build(),
            )
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("History")
                            .setOnClickListener {
                                screenManager.push(OpenDragyHistoryScreen(carContext))
                            }
                            .build(),
                    )
                    .build(),
            )
            .build()
    }
}

/** Full metric list for the just-finished (or last) run. */
class OpenDragyMetricsScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        CarStateStore.load(carContext)
        val headline = CarStateStore.finishHeadline.ifBlank {
            CarStateStore.lastResult ?: "Run complete"
        }
        val list = ItemList.Builder()
        list.addItem(
            Row.Builder()
                .setTitle(headline)
                .addText("Full run metrics")
                .build(),
        )
        for (line in CarStateStore.finishLines) {
            val parts = line.split('|', limit = 2)
            val row = Row.Builder().setTitle(parts.getOrElse(0) { line })
            val value = parts.getOrElse(1) { "" }
            if (value.isNotBlank()) row.addText(value)
            list.addItem(row.build())
        }

        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle("Metrics")
            .setHeaderAction(Action.BACK)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Done")
                            .setBackgroundColor(CarColor.GREEN)
                            .setOnClickListener {
                                // Pop metrics + finish → back to main.
                                screenManager.popToRoot()
                            }
                            .build(),
                    )
                    .build(),
            )
            .build()
    }
}
