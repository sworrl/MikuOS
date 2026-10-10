package com.miku.settings.pages

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.miku.settings.lock.MikuCredentialActivity
import com.miku.settings.lock.MikuLock
import com.miku.settings.ui.*

/**
 * Security > Screen lock. Set, change or remove the PIN or password, choose when MikuOS asks for
 * it, and whether notifications show their content while locked.
 */
@Composable
fun ScreenLockPage() {
    val ctx = LocalContext.current
    var refresh by remember { mutableIntStateOf(0) }
    LifecycleResumeTick { refresh++ }

    PageList {
        item {
            key(refresh) {
                val type = remember { MikuLock.credentialType(ctx) }
                val secure = type != MikuLock.TYPE_NONE
                Section("Screen lock") {
                    InfoRow("Current lock", MikuLock.typeName(type))
                    if (!secure) {
                        NavRow("Set a PIN", "${MikuLock.MIN_LENGTH} to ${MikuLock.MAX_LENGTH} digits", Icons.Default.Pin) {
                            ctx.startActivity(MikuCredentialActivity.intent(ctx, MikuCredentialActivity.MODE_SET, MikuLock.TYPE_PIN))
                        }
                        NavRow("Set a password", "${MikuLock.MIN_LENGTH} to ${MikuLock.MAX_LENGTH} characters, at least one letter", Icons.Default.Password) {
                            ctx.startActivity(MikuCredentialActivity.intent(ctx, MikuCredentialActivity.MODE_SET, MikuLock.TYPE_PASSWORD))
                        }
                    } else {
                        NavRow("Change screen lock", "Asks for the current one first", Icons.Default.Lock) {
                            ctx.startActivity(MikuCredentialActivity.intent(ctx, MikuCredentialActivity.MODE_CHANGE))
                        }
                        NavRow("Remove screen lock", "Asks for the current one first", Icons.Default.LockOpen) {
                            ctx.startActivity(MikuCredentialActivity.intent(ctx, MikuCredentialActivity.MODE_REMOVE))
                        }
                    }
                }
            }
        }
        item {
            key(refresh) {
                val type = remember { MikuLock.credentialType(ctx) }
                val secure = type != MikuLock.TYPE_NONE
                val noun = if (type == MikuLock.TYPE_PASSWORD) "password" else "PIN"
                var until by remember { mutableStateOf(MikuLock.untilRestart(ctx)) }
                Section(
                    "When to ask",
                    note = "Android also asks again 24 hours after the last time you entered it, " +
                        "and when the screen stayed off for 8 hours. MikuOS cannot change that."
                ) {
                    ToggleRow(
                        "Ask for $noun only after restart",
                        if (until) "After the first unlock, swipe up opens the device until the next restart"
                        else "Asks every time the screen turns on",
                        if (secure) until else false,
                        enabled = secure
                    ) {
                        if (MikuLock.setUntilRestart(ctx, it)) until = it else toast(ctx, "That setting was refused")
                    }
                    if (!secure) BodyText("Set a PIN or password first.")
                }
            }
        }
        item {
            key(refresh) {
                var show by remember { mutableStateOf(MikuLock.showContent(ctx)) }
                Section("Lock screen") {
                    ToggleRow(
                        "Show notification content when locked",
                        if (show) "The shade shows full notifications while locked"
                        else "The shade shows only the app name until you unlock",
                        show
                    ) {
                        if (MikuLock.setShowContent(ctx, it)) show = it else toast(ctx, "That setting was refused")
                    }
                }
            }
        }
    }
}
