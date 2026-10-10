package com.miku.update.ota

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.miku.update.R
import com.miku.update.ui.MainActivity

object Notifier {
    private const val CH_UPDATES = "updates"
    private const val CH_ACTION = "action"
    private const val ID_INSTALLED = 1
    private const val ID_AVAILABLE = 2
    private const val ID_SYSTEM = 3
    private const val ID_REVOKED = 4
    private const val ID_ACTION_BASE = 100

    fun createChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CH_UPDATES, "Updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "App updates installed or waiting, and new system images"
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_ACTION, "Needs your OK", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "When an install has to be confirmed by hand"
            }
        )
    }

    private fun openApp(ctx: Context): PendingIntent = PendingIntent.getActivity(
        ctx, 0,
        Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun post(ctx: Context, id: Int, b: NotificationCompat.Builder) {
        try {
            NotificationManagerCompat.from(ctx).notify(id, b.build())
        } catch (_: SecurityException) {
            // Notifications switched off for this app. The UI still shows everything.
        }
    }

    private fun base(ctx: Context, channel: String, title: String, text: String) =
        NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_stat_update)
            .setColor(0xFF39C5BB.toInt())
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(openApp(ctx))
            .setAutoCancel(true)

    fun installed(ctx: Context, lines: List<String>) {
        if (lines.isEmpty()) return
        val title = if (lines.size == 1) "1 app updated" else "${lines.size} apps updated"
        post(ctx, ID_INSTALLED, base(ctx, CH_UPDATES, title, lines.joinToString("\n")))
    }

    fun available(ctx: Context, lines: List<String>) {
        if (lines.isEmpty()) return
        val title = if (lines.size == 1) "1 app update ready" else "${lines.size} app updates ready"
        post(ctx, ID_AVAILABLE, base(ctx, CH_UPDATES, title, lines.joinToString("\n") + "\nOpen Miku Update to install."))
    }

    fun revoked(ctx: Context, lines: List<String>) {
        if (lines.isEmpty()) return
        val title = if (lines.size == 1) "An update was pulled" else "${lines.size} updates were pulled"
        post(ctx, ID_REVOKED, base(ctx, CH_UPDATES, title, lines.joinToString("\n") + "\nBack on the version that came with MikuOS."))
    }

    fun systemUpdate(ctx: Context, build: String, required: Boolean) {
        val text = if (required) {
            "MikuOS $build is needed before more app updates can install. It goes on from a PC with the web installer."
        } else {
            "MikuOS $build is out. It goes on from a PC with the web installer."
        }
        post(ctx, ID_SYSTEM, base(ctx, CH_UPDATES, "System update available", text))
    }

    fun userActionNeeded(ctx: Context, confirm: Intent, pkg: String) {
        val pi = PendingIntent.getActivity(
            ctx, pkg.hashCode(), confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = base(ctx, CH_ACTION, "Tap to finish an update", "${OtaConfig.displayName(pkg)} is waiting for your OK.")
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
        post(ctx, ID_ACTION_BASE + (pkg.hashCode() and 0xff), b)
    }

    fun clearAvailable(ctx: Context) = NotificationManagerCompat.from(ctx).cancel(ID_AVAILABLE)
}
