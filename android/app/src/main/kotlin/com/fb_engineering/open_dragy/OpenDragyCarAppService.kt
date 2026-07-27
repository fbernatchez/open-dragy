package com.fb_engineering.open_dragy

import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class OpenDragyCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // Debuggable / DIY builds: allow DHU + projected hosts.
        // Play-distributed release should still validate against the sample allowlist.
        val debuggable =
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        return if (debuggable) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(): Session = OpenDragyCarSession()
}
