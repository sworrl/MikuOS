package com.miku.launcher.usb

import android.content.Context
import android.provider.Settings
import com.miku.launcher.RootShell
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object MikuUsbAudioHostManager {
    fun isActive(ctx: Context): Boolean {
        val workMode = try {
            Settings.Global.getString(ctx.contentResolver, "work_mode")
        } catch (_: Throwable) { null }
        return "dacin" == workMode
    }

    /**
     * All three setters used to `return true` whenever no exception was thrown — which proved
     * nothing. Half the work (the actual UAC2 gadget switch) goes through [RootShell.execFast],
     * which returns Unit and no-ops entirely when `su` is absent, as it is on this device. The
     * sheet then closed and the preference was saved as though the mode had been applied.
     *
     * They now VERIFY by reading `work_mode` back — the key HiBy's framework actually acts on —
     * and return that. A false result means the mode was not applied; callers must say so.
     */
    private fun setWorkMode(ctx: Context, value: String): Boolean {
        runCatching { Settings.Global.putString(ctx.contentResolver, "work_mode", value) }
        // Platform-signed path for the gadget props (no su on MikuOS); best effort, unverifiable.
        runCatching {
            val c = Class.forName("android.os.SystemProperties")
            val set = c.getMethod("set", String::class.java, String::class.java)
            if (value == "dacin") {
                set.invoke(null, "vendor.usb.uac2.function.start", "1")
                set.invoke(null, "vendor.usb.port_type", "sink")
            } else {
                set.invoke(null, "vendor.usb.uac2.function.start", "0")
            }
        }
        val readBack = runCatching {
            Settings.Global.getString(ctx.contentResolver, "work_mode")
        }.getOrNull()
        return readBack == value
    }

    suspend fun setUsbDacMode(ctx: Context, enabled: Boolean): Boolean = withContext(Dispatchers.IO) {
        val target = if (enabled) "dacin" else "android"
        val ok = setWorkMode(ctx, target)
        // The gadget switch itself needs system_app (vendor.usb.* props); MikuOS has no su, so
        // com.miku.sysbridge, the one system-UID Miku package, runs HiBy's sequence for us.
        val sent = runCatching {
            ctx.sendBroadcast(
                android.content.Intent("com.miku.sysbridge.USB_DAC")
                    .setPackage("com.miku.sysbridge").putExtra("enable", enabled),
                "com.miku.permission.SYSTEM_BRIDGE"
            ); true
        }.getOrDefault(false)
        ok && sent
    }

    suspend fun setMtpMode(ctx: Context): Boolean = withContext(Dispatchers.IO) {
        val ok = setWorkMode(ctx, "android")
        RootShell.execFast("setprop vendor.usb.uac2.function.start 0; setprop sys.usb.config mtp,adb")
        ok
    }

    suspend fun setChargeOnlyMode(ctx: Context): Boolean = withContext(Dispatchers.IO) {
        val ok = setWorkMode(ctx, "android")
        RootShell.execFast("setprop vendor.usb.uac2.function.start 0; setprop sys.usb.config none")
        ok
    }
}
