package com.miku.update.work

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Nothing launches Miku Update on a fresh image, so without this the daily check would only start
 * once someone opened the app. Boot (and our own update) starts the process; schedule() is
 * idempotent.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                runCatching { UpdateWorker.schedule(context.applicationContext) }
        }
    }
}
