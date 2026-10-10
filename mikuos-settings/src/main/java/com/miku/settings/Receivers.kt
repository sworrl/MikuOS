package com.miku.settings

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.i("MikuOS_Settings", "Boot received, initializing MikuOS hardware & settings")
        // Dev builds only: a release build (ro.miku.release=1) leaves adb and developer options
        // to the user.
        val release = runCatching {
            Class.forName("android.os.SystemProperties").getMethod("get", String::class.java)
                .invoke(null, "ro.miku.release") as String
        }.getOrDefault("") == "1"
        if (!release) try {
            android.provider.Settings.Global.putInt(context.contentResolver, android.provider.Settings.Global.ADB_ENABLED, 1)
            android.provider.Settings.Global.putInt(context.contentResolver, android.provider.Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 1)
            android.provider.Settings.Global.putInt(context.contentResolver, "adb_wifi_enabled", 1)
        } catch (_: Throwable) {}

        // Root HAL Daemon initialization (dev only; no su on MikuOS, so this is a no-op anyway)
        if (!release) RootShell.execFast(
            "settings put global adb_enabled 1; " +
            "settings put global development_settings_enabled 1; " +
            "settings put global adb_wifi_enabled 1; " +
            "setprop persist.sys.usb.config mtp,adb; " +
            "setprop service.adb.tcp.port 5555; " +
            "setprop persist.service.adb.enable 1; " +
            "stop adbd 2>/dev/null; start adbd 2>/dev/null"
        )

        // Settings parity: claim the settings intents we tie with stock on (see PreferredRouting),
        // and keep a boot-time HOME placeholder available if stock FallbackHome is gone.
        if (intent?.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            val app = context.applicationContext
            val pending = goAsync()
            Thread {
                try {
                    com.miku.settings.home.MikuFallbackHome.syncWithStock(app)
                    com.miku.settings.route.PreferredRouting.claim(app)
                } catch (t: Throwable) {
                    Log.w("MikuOS_Settings", "settings routing setup failed", t)
                } finally { pending.finish() }
            }.start()
        }

    }
}

