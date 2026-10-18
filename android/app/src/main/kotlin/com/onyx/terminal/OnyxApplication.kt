package com.onyx.terminal

import android.app.Application
import android.content.pm.ApplicationInfo
import com.onyx.terminal.security.Crypto
import com.onyx.terminal.service.NotificationHelper
import com.onyx.terminal.util.Logger

class OnyxApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        Logger.init(this, debuggable)
        Crypto.init()
        NotificationHelper.init(this)
        Logger.i("app", "Onyx dimulai")
    }

    companion object {
        lateinit var instance: OnyxApplication
            private set
    }
}
