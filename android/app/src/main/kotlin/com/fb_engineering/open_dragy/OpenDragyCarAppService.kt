package com.fb_engineering.open_dragy

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class OpenDragyCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // Sideload / DIY — allow DHU, phone projection, bike AA displays.
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session = OpenDragyCarSession()
}
