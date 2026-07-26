package com.fb_engineering.open_dragy

import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** Pick drag distance target (60ft … 1/2 mile). */
class OpenDragyTargetScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        CarStateStore.load(carContext)
        val list = ItemList.Builder()
        for (t in CarStateStore.dragTargets) {
            val selected = t.name == CarStateStore.dragTargetName
            val row = Row.Builder()
                .setTitle(t.label)
                .setOnClickListener {
                    if (!CarStateStore.running) {
                        val intent = Intent(OpenDragyMainScreen.ACTION_CAR_COMMAND)
                            .setPackage(carContext.packageName)
                        intent.putExtra(OpenDragyMainScreen.EXTRA_CMD, "setDragTarget")
                        intent.putExtra(OpenDragyMainScreen.EXTRA_TARGET, t.name)
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
            .setTitle("Drag target")
            .setHeaderAction(Action.BACK)
            .build()
    }
}
