package com.miku.settings

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.widget.Toast

/**
 * Opens the one DAC settings page on MikuOS: the Hardware app (com.m500.hardware).
 * The same helper exists in Miku Music, the launcher and SystemUI.
 *
 * Tries the action inside the Hardware package first, then the activity by name (works with a
 * Hardware build that predates the action), then says so if neither is there.
 */
object DacSettingsLink {
    const val ACTION = "com.miku.action.DAC_SETTINGS"
    const val PACKAGE = "com.m500.hardware"
    private const val ACTIVITY = "com.m500.hardware.MainActivity"

    fun open(ctx: Context): Boolean {
        val tries = listOf(
            Intent(ACTION).setPackage(PACKAGE),
            Intent(ACTION).setClassName(PACKAGE, ACTIVITY),
        )
        for (i in tries) {
            if (ctx !is Activity) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                ctx.startActivity(i)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        Toast.makeText(ctx, "The Hardware app is not installed, so DAC settings are not available.", Toast.LENGTH_LONG).show()
        return false
    }
}
