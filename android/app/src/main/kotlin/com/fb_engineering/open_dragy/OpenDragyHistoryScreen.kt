package com.fb_engineering.open_dragy

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** Recent runs — tap for metric detail. */
class OpenDragyHistoryScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        CarStateStore.load(carContext)
        val history = CarStateStore.history
        if (history.isEmpty()) {
            return MessageTemplate.Builder("No runs yet")
                .setTitle("History")
                .setHeaderAction(Action.BACK)
                .addAction(
                    Action.Builder()
                        .setTitle("OK")
                        .setOnClickListener { screenManager.pop() }
                        .build(),
                )
                .build()
        }

        val list = ItemList.Builder()
        for (entry in history) {
            list.addItem(
                Row.Builder()
                    .setTitle(entry.title)
                    .addText(entry.subtitle)
                    .setOnClickListener {
                        screenManager.push(
                            OpenDragyRunDetailScreen(carContext, entry.id),
                        )
                    }
                    .build(),
            )
        }

        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle("History")
            .setHeaderAction(Action.BACK)
            .build()
    }
}

class OpenDragyRunDetailScreen(
    carContext: CarContext,
    private val runId: String,
) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        CarStateStore.load(carContext)
        val entry = CarStateStore.history.firstOrNull { it.id == runId }
        if (entry == null) {
            return MessageTemplate.Builder("Run not found")
                .setTitle("Run")
                .setHeaderAction(Action.BACK)
                .addAction(
                    Action.Builder()
                        .setTitle("OK")
                        .setOnClickListener { screenManager.pop() }
                        .build(),
                )
                .build()
        }

        val list = ItemList.Builder()
        list.addItem(
            Row.Builder()
                .setTitle(entry.title)
                .addText(entry.subtitle)
                .build(),
        )
        for (line in entry.lines) {
            val parts = line.split('|', limit = 2)
            val row = Row.Builder().setTitle(parts.getOrElse(0) { line })
            val value = parts.getOrElse(1) { "" }
            if (value.isNotBlank()) row.addText(value)
            list.addItem(row.build())
        }

        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle("Run")
            .setHeaderAction(Action.BACK)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Back")
                            .setOnClickListener { screenManager.pop() }
                            .build(),
                    )
                    .build(),
            )
            .build()
    }
}
