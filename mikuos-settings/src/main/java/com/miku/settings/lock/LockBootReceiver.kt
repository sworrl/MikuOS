package com.miku.settings.lock

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.UserManager
import android.util.Log

/**
 * After a restart with a screen lock set, puts the MikuOS unlock pad over the stock keyguard so
 * the first unlock (the one that unlocks storage) is entered on the Miku pad.
 *
 * Direct boot aware: LOCKED_BOOT_COMPLETED arrives before the user's storage is unlocked, which is
 * exactly when the pad is needed. The Miku lockscreen in the launcher cannot run yet at that point.
 */
class LockBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) return
        try {
            val um = context.getSystemService(UserManager::class.java)
            val km = context.getSystemService(KeyguardManager::class.java)
            val type = MikuLock.credentialType(context)
            if (um?.isUserUnlocked == false && km?.isDeviceSecure == true &&
                (type == MikuLock.TYPE_PIN || type == MikuLock.TYPE_PASSWORD)
            ) {
                MikuUnlockActivity.start(context)
            }
        } catch (t: Throwable) {
            Log.w("MikuUnlock", "boot pad failed", t)
        }
    }
}
