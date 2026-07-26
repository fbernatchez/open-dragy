package com.fb_engineering.open_dragy

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class OpenDragyCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        CarStateStore.load(carContext)
        return OpenDragyMainScreen(carContext)
    }
}
