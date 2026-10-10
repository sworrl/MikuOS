package com.miku.update.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.format.DateUtils
import android.text.format.Formatter
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.miku.update.BuildConfig
import com.miku.update.ota.Installer
import com.miku.update.ota.OtaConfig
import com.miku.update.ota.OtaEngine
import com.miku.update.ota.OtaEngine.Phase
import com.miku.update.ota.Prefs
import com.miku.update.ota.SignatureVerifier
import com.miku.update.ota.WebInstallerPath
import com.miku.update.work.UpdateWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.SupervisorJob
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MikuTheme { UpdateScreen() } }
    }

    override fun onResume() {
        super.onResume()
        // If PackageInstaller ever asks for a confirmation while we are on screen, show it here
        // instead of as a notification.
        Installer.onUserAction = { ctx, confirm, _ ->
            runCatching { startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                .onFailure { com.miku.update.ota.Notifier.userActionNeeded(ctx, confirm, "") }
        }
        OtaEngine.refreshInstalled(applicationContext)
    }

    override fun onPause() {
        Installer.onUserAction = null
        super.onPause()
    }

    companion object {
        /**
         * Work started from the screen keeps going if the user leaves it: it runs in the app's
         * process scope, not the activity's, so a rotation or a back press does not cut an install
         * in half.
         */
        val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    }
}

private fun toast(ctx: Context, msg: String) = Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()

private fun size(ctx: Context, bytes: Long) = Formatter.formatShortFileSize(ctx, bytes)

@Composable
fun UpdateScreen() {
    val ctx = LocalContext.current.applicationContext
    val s by OtaEngine.state.collectAsState()
    val prefs = remember { Prefs(ctx) }
    var settingsTick by remember { mutableStateOf(0) }

    LaunchedEffect(Unit) {
        OtaEngine.refreshInstalled(ctx)
        if (s.manifest == null && s.busy == null) MainActivity.appScope.launch { OtaEngine.check(ctx) }
    }
    LaunchedEffect(s.notice) {
        s.notice?.let { toast(ctx, it); OtaEngine.clearNotice() }
    }

    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF0A1A1D), MikuDarkBg, MikuDarkBg)))) {
        LazyColumn(
            Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(top = 10.dp, bottom = 28.dp),
        ) {
            item { Header(s) }
            item { StatusCard(ctx, s, prefs) }
            s.systemUpdate?.let { su -> item { SystemUpdateCard(ctx, su, s.blockedByMinBuild) } }
            if (s.items.isNotEmpty()) item { UpdatesCard(ctx, s) }
            if (s.installed.isNotEmpty()) item { InstalledCard(ctx, s) }
            item {
                // settingsTick forces a re-read of prefs after a change.
                SettingsCard(ctx, prefs, settingsTick) { settingsTick++ }
            }
            item { AboutCard(ctx, s, prefs, settingsTick) { settingsTick++ } }
        }
    }
}

@Composable
private fun Header(s: OtaEngine.State) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("MIKU", color = MikuTealBright, fontSize = 20.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
            Spacer(Modifier.width(6.dp))
            Text("UPDATE", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
        }
        Spacer(Modifier.height(2.dp))
        val build = s.deviceBuild?.let { "MikuOS $it" } ?: "MikuOS build unknown"
        Text("$build  ·  ${Prefs(LocalContext.current).channel} channel", color = MikuMuted, fontSize = 11.5.sp)
    }
}

@Composable
private fun StatusCard(ctx: Context, s: OtaEngine.State, prefs: Prefs) {
    val ready = s.installable
    val hot = s.error != null
    Section(title = "Status", hot = hot) {
        val headline = when {
            s.busy != null -> s.busy
            s.error != null -> "Something went wrong"
            s.manifest == null -> "Not checked yet"
            ready.isNotEmpty() -> if (ready.size == 1) "1 app update ready" else "${ready.size} app updates ready"
            s.items.any { it.phase == Phase.BLOCKED } -> "App updates are waiting on a system update"
            s.systemUpdate != null -> "Apps are up to date"
            else -> "Everything is up to date"
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (s.busy != null) {
                CircularProgressIndicator(Modifier.padding(end = 10.dp).width(18.dp).height(18.dp), color = MikuTealBright, strokeWidth = 2.dp)
            }
            Text(headline, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
        s.error?.let {
            Spacer(Modifier.height(4.dp))
            BodyText(it, MikuPinkBright)
        }
        Spacer(Modifier.height(4.dp))
        val last = prefs.lastCheckMillis
        BodyText(
            if (last == 0L) "No check yet."
            else "Last checked " + DateUtils.getRelativeTimeSpanString(last, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS) + "."
        )
        Spacer(Modifier.height(10.dp))
        ButtonRow {
            ActionButton("Check now", enabled = s.busy == null) {
                MainActivity.appScope.launch { OtaEngine.check(ctx) }
            }
            if (ready.isNotEmpty()) {
                val total = ready.sumOf { it.entry.size }
                ActionButton("Install all (${size(ctx, total)})", enabled = s.busy == null) {
                    MainActivity.appScope.launch { OtaEngine.installAll(ctx, includeHeld = true) }
                }
            }
            if (s.busy != null && s.items.any { it.phase == Phase.DOWNLOADING }) {
                ActionButton("Stop", danger = true) { OtaEngine.requestCancel() }
            }
        }
    }
}

@Composable
private fun SystemUpdateCard(ctx: Context, su: com.miku.update.ota.OtaManifest.SystemUpdate, blocked: Boolean) {
    val path = WebInstallerPath(su.installerUrl, su.build)
    val needed = su.required || blocked
    Section(
        title = if (needed) "System update needed" else "System update available",
        note = "MikuOS ${su.build}",
        hot = true,
    ) {
        BodyText(
            if (blocked) "This device is on an older MikuOS than these app updates were built for. Put MikuOS ${su.build} on first, then app updates pick up again here."
            else "Some changes, like the FM app, drivers and system settings, only come with a full image. That goes on from a computer, not from here.",
            Color.White,
        )
        if (su.notes.isNotBlank()) {
            Spacer(Modifier.height(8.dp))
            BodyText(su.notes)
        }
        Spacer(Modifier.height(10.dp))
        BodyText("On a computer with Chrome or Edge, open the address below (or scan the code), plug the M500 in with USB, and follow the steps. Your music and settings stay unless you pick a clean install.")
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            QrCode(path.link(), 132.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(path.link(), color = MikuTealBright, fontSize = 11.sp, fontFamily = FontFamily.Monospace, lineHeight = 14.sp)
                Spacer(Modifier.height(8.dp))
                ActionButton(path.actionLabel) {
                    try {
                        ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(path.link())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: ActivityNotFoundException) {
                        toast(ctx, "No browser here. Scan the code or type the address on a computer.")
                    }
                }
            }
        }
    }
}

@Composable
private fun UpdatesCard(ctx: Context, s: OtaEngine.State) {
    val m = s.manifest
    Section(title = "App updates", note = m?.let { "From the ${it.channel} channel, MikuOS ${it.build}" }) {
        if (m != null && m.changelog.isNotBlank()) {
            var open by remember { mutableStateOf(false) }
            Text(
                if (open) "Hide what changed" else "What changed",
                color = MikuPinkBright, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.clickable { open = !open }.padding(vertical = 4.dp),
            )
            if (open) {
                Text(
                    m.changelog, color = MikuWhite, fontSize = 11.5.sp, lineHeight = 15.sp,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(MikuSurface2).padding(10.dp),
                )
            }
            Spacer(Modifier.height(6.dp))
        }
        s.items.forEach { item -> UpdateRow(ctx, item, s.busy == null) }
    }
}

@Composable
private fun UpdateRow(ctx: Context, item: OtaEngine.Item, idle: Boolean) {
    val e = item.entry
    Column(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(12.dp)).background(MikuSurface2).padding(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(item.name, color = Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    "${item.installedVersionName.ifBlank { item.installedVersionCode.toString() }} to ${e.versionName.ifBlank { e.versionCode.toString() }}  ·  ${size(ctx, e.size)}",
                    color = MikuMuted, fontSize = 11.sp,
                )
            }
            when (item.phase) {
                Phase.DONE -> Badge("Installed", MikuTealBright)
                Phase.BLOCKED -> Badge("Waiting", MikuGold)
                Phase.HELD -> Badge("Held", MikuGold)
                Phase.FAILED -> Badge("Failed", MikuPinkBright)
                Phase.DOWNLOADING -> Badge("Downloading", MikuTealBright)
                Phase.VERIFYING -> Badge("Checking", MikuTealBright)
                Phase.INSTALLING -> Badge("Installing", MikuTealBright)
                Phase.READY -> Text(
                    "Install", color = MikuTealBright, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(enabled = idle) {
                        MainActivity.appScope.launch { OtaEngine.installOne(ctx, e.packageName) }
                    }.padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
        }
        if (item.phase == Phase.DOWNLOADING || item.phase == Phase.VERIFYING || item.phase == Phase.INSTALLING) {
            Spacer(Modifier.height(6.dp))
            if (item.phase == Phase.DOWNLOADING && e.size > 0) {
                LinearProgressIndicator(
                    progress = { (item.done.toFloat() / e.size).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)),
                    color = MikuPink, trackColor = MikuSurface1,
                )
                Text("${size(ctx, item.done)} of ${size(ctx, e.size)}", color = MikuMuted, fontSize = 10.5.sp)
            } else {
                LinearProgressIndicator(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)), color = MikuTealBright, trackColor = MikuSurface1)
            }
        }
        if (item.message.isNotBlank()) {
            Spacer(Modifier.height(4.dp))
            Text(item.message, color = if (item.phase == Phase.FAILED) MikuPinkBright else MikuMuted, fontSize = 11.sp, lineHeight = 14.sp)
        }
        if (item.phase == Phase.HELD && idle) {
            Text(
                "Install anyway", color = MikuTealBright, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.clickable { MainActivity.appScope.launch { OtaEngine.installOne(ctx, e.packageName) } }.padding(top = 6.dp),
            )
        }
    }
}

@Composable
private fun InstalledCard(ctx: Context, s: OtaEngine.State) {
    var confirm by remember { mutableStateOf<Pair<OtaEngine.InstalledApp, Boolean>?>(null) }
    Section(
        title = "Installed MikuOS apps",
        note = "Image means the copy that came with MikuOS. Updated means a newer copy is installed over it.",
    ) {
        s.installed.forEach { app ->
            Column(
                Modifier.fillMaxWidth().padding(vertical = 3.dp).clip(RoundedCornerShape(12.dp)).background(MikuSurface2).padding(10.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(app.name, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        Text(app.versionName.ifBlank { app.versionCode.toString() }, color = MikuMuted, fontSize = 11.sp)
                    }
                    if (app.pkg in OtaConfig.NEVER_UPDATE) Badge("Image only", MikuMuted)
                    else if (app.isUpdate) Badge("Updated", MikuPinkBright) else Badge("Image", MikuTeal)
                }
                if (app.isUpdate && s.busy == null) {
                    Spacer(Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        val kept = app.kept
                        if (kept != null && app.pkg != ctx.packageName) {
                            Text(
                                "Back to ${kept.versionName.ifBlank { kept.versionCode.toString() }}",
                                color = MikuTealBright, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                modifier = Modifier.clickable { confirm = app to false },
                            )
                        }
                        Text(
                            "Back to image version" + (app.imageVersionName?.let { " ($it)" } ?: ""),
                            color = MikuPinkBright, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            modifier = Modifier.clickable { confirm = app to true },
                        )
                    }
                }
            }
        }
    }
    confirm?.let { (app, toImage) ->
        val target = if (toImage) "the version that came with MikuOS" else "${app.kept?.versionName ?: "the previous version"}"
        MikuAlert(
            title = "Roll back ${app.name}?",
            text = "This puts ${app.name} back to $target. Its settings and data stay, but an older version may not understand everything a newer one saved. Automatic updates will skip ${app.versionName} from now on.",
            confirm = "Roll back",
            danger = true,
            onConfirm = {
                confirm = null
                MainActivity.appScope.launch {
                    val msg = OtaEngine.rollback(ctx, app.pkg, toImage)
                    OtaEngine.setNotice(msg)
                }
            },
            onDismiss = { confirm = null },
        )
    }
}

@Composable
private fun SettingsCard(ctx: Context, prefs: Prefs, tick: Int, changed: () -> Unit) {
    @Suppress("UNUSED_EXPRESSION") tick
    fun apply(block: () -> Unit) {
        block()
        UpdateWorker.schedule(ctx)
        changed()
    }
    Section(title = "Settings") {
        Text("Channel", color = Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
        val descriptions = mapOf(
            "stable" to "Tested builds. The right pick for most people.",
            "beta" to "Next release, mostly finished. Expect the odd rough edge.",
            "dev" to "Whatever was built last. Things will break sometimes.",
        )
        OtaConfig.CHANNELS.forEach { ch ->
            RadioRow(ch.replaceFirstChar { it.uppercase() }, descriptions[ch], prefs.channel == ch) {
                if (prefs.channel != ch) {
                    apply { prefs.channel = ch }
                    MainActivity.appScope.launch { OtaEngine.check(ctx) }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        ToggleRow("Install app updates on their own", "Installs in the background after a scheduled check. Off means you get a notification instead.", prefs.autoInstall) {
            apply { prefs.autoInstall = it }
        }
        ToggleRow("Check automatically", null, prefs.scheduleEnabled) { apply { prefs.scheduleEnabled = it } }
        if (prefs.scheduleEnabled) {
            Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(6 to "6 h", 12 to "12 h", 24 to "Daily", 168 to "Weekly").forEach { (h, label) ->
                    Chip(label, prefs.intervalHours == h) { apply { prefs.intervalHours = h } }
                }
            }
            ToggleRow("Only on Wi-Fi", "Skip scheduled checks on metered connections.", prefs.wifiOnly) { apply { prefs.wifiOnly = it } }
            ToggleRow("Only while charging", null, prefs.chargingOnly) { apply { prefs.chargingOnly = it } }
        }
    }
}

@Composable
private fun AboutCard(ctx: Context, s: OtaEngine.State, prefs: Prefs, tick: Int, changed: () -> Unit) {
    @Suppress("UNUSED_EXPRESSION") tick
    val keys = remember { runCatching { SignatureVerifier.load(ctx).keyInfo() }.getOrDefault(emptyList()) }
    var showDev by remember { mutableStateOf(prefs.baseUrlOverride.isNotBlank()) }
    Section(title = "About") {
        Text("Miku Update ${BuildConfig.VERSION_NAME}", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(4.dp))
        BodyText("Every update list is signed, and every app is checked against its signed hash and against the key the installed app was signed with before anything installs. The FM app is never updated here. It only comes with a system image.")
        Spacer(Modifier.height(6.dp))
        s.manifest?.let { m ->
            val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm").withZone(ZoneId.systemDefault())
            BodyText("List published ${fmt.format(m.publishedAt)}, signed with the ${s.signedBy ?: "?"} key.")
        }
        keys.forEach { (name, fp) -> BodyText("Trusted $name key  $fp") }
        Spacer(Modifier.height(6.dp))
        Text(
            if (showDev) "Hide test server" else "Test server",
            color = MikuMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.clickable { showDev = !showDev }.padding(vertical = 4.dp),
        )
        if (showDev) {
            BodyText("Point at a test server on your network, like http://192.168.1.20:8000/ota/. Lists there still have to be signed with the real keys. Leave it empty for the normal server.")
            var text by remember { mutableStateOf(prefs.baseUrlOverride) }
            Spacer(Modifier.height(6.dp))
            BasicTextField(
                value = text,
                onValueChange = { text = it },
                singleLine = true,
                textStyle = TextStyle(color = Color.White, fontSize = 12.sp, fontFamily = FontFamily.Monospace),
                cursorBrush = SolidColor(MikuTealBright),
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(MikuSurface2).padding(10.dp),
                decorationBox = { inner ->
                    if (text.isEmpty()) Text(OtaConfig.DEFAULT_BASE_URL, color = MikuMuted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                    inner()
                },
            )
            Spacer(Modifier.height(6.dp))
            ButtonRow {
                ActionButton("Use this server") {
                    val t = text.trim()
                    if (t.isNotEmpty() && !(t.startsWith("http://") || t.startsWith("https://"))) {
                        toast(ctx, "That needs to start with http:// or https://")
                    } else {
                        prefs.baseUrlOverride = t
                        // A different server has its own publish history; start the replay check over.
                        OtaConfig.CHANNELS.forEach { prefs.setLastPublished(it, 0L) }
                        changed()
                        MainActivity.appScope.launch { OtaEngine.check(ctx) }
                    }
                }
                ActionButton("Reset", danger = true) {
                    text = ""
                    prefs.baseUrlOverride = ""
                    OtaConfig.CHANNELS.forEach { prefs.setLastPublished(it, 0L) }
                    changed()
                    MainActivity.appScope.launch { OtaEngine.check(ctx) }
                }
            }
            BodyText("Now using ${prefs.baseUrl}")
        }
    }
}
