package com.fb_engineering.open_dragy

import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** Pick active garage vehicle for the next run. */
class OpenDragyVehicleScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        CarStateStore.load(carContext)
        val vehicles = CarStateStore.vehicles
        if (vehicles.isEmpty()) {
            return MessageTemplate.Builder("Add vehicles in the phone Garage first")
                .setTitle("Vehicle")
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
        for (v in vehicles) {
            val selected = v.id == CarStateStore.vehicleId
            val row = Row.Builder()
                .setTitle(v.label)
                .setOnClickListener {
                    if (!CarStateStore.running) {
                        val intent = Intent(OpenDragyMainScreen.ACTION_CAR_COMMAND)
                            .setPackage(carContext.packageName)
                        intent.putExtra(OpenDragyMainScreen.EXTRA_CMD, "setVehicle")
                        intent.putExtra(OpenDragyMainScreen.EXTRA_VEHICLE, v.id)
                        carContext.sendBroadcast(intent)
                    }
                    screenManager.pop()
                }
            if (selected) {
                row.addText("Selected")
            }
            list.addItem(row.build())
        }

        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle("Vehicle")
            .setHeaderAction(Action.BACK)
            .build()
    }
}
