package com.miku.update

import android.app.Application
import com.miku.update.ota.Notifier
import com.miku.update.work.UpdateWorker

class MikuUpdateApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Notifier.createChannels(this)
        // WorkManager keeps periodic work across reboots itself; this only (re)applies settings.
        runCatching { UpdateWorker.schedule(this) }
    }
}
