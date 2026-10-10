package com.miku.launcher

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.miku.launcher.bpm.MikuBpmEngine
import com.miku.launcher.bpm.MikuSecrets
import com.miku.launcher.bpm.MikuUnlocks
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.sin

// Launcher-side consumers of the BPM game's hidden tier (see bpm/MikuSecrets.kt). Each one reads
// its id from the one store and changes real behaviour; nothing here can grant anything.

/**
 * Earned AND switched on, re-read whenever the store changes. The game writes in this process, so
 * [MikuUnlocks.version] ticks the moment a secret is earned or toggled and the home screen
 * updates without a restart or a poll.
 */
@Composable
fun rememberUnlockEnabled(id: String): Boolean {
    val ctx = LocalContext.current
    val v by MikuUnlocks.version.collectAsState()
    return remember(id, v) { MikuUnlocks.isEnabled(ctx, id) }
}

/**
 * The secrets that are whole apps (Riot mode, the MikuPod eras) open from their card in the
 * Secrets list. This is the intent for that, or null when the secret is not an app or the app is
 * not installed. The app checks the unlock itself, so this never bypasses anything.
 */
fun secretOpenIntent(ctx: Context, id: String): Intent? {
    val i = when (id) {
        MikuSecrets.RIOT_MODE ->
            Intent("com.miku.riot.action.ENTER").setPackage("com.miku.riot")
        MikuSecrets.WHEEL_2001, MikuSecrets.WHEEL_2004, MikuSecrets.WHEEL_2005, MikuSecrets.WHEEL_2007 ->
            Intent("com.miku.wheel.action.ENTER").setPackage("com.miku.wheel")
                .putExtra("era", id.substringAfterLast('.'))
        else -> return null
    }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    return if (i.resolveActivity(ctx.packageManager) != null) i else null
}

/** The Miku Music icon to draw: gold once [MikuSecrets.GOLDEN_ICON] is earned and on. */
fun mikuMusicIconRes(golden: Boolean): Int =
    if (golden) R.drawable.ic_miku_music_golden else R.drawable.ic_miku_music_brand

/** Any app icon resource, with the Miku Music brand icon swapped for gold when earned. */
fun displayIconRes(resId: Int?, golden: Boolean): Int? =
    if (golden && resId == R.drawable.ic_miku_music_brand) R.drawable.ic_miku_music_golden else resId

/**
 * Concert Mode's on/off. Toggled by double-tapping the home hearts clock once the secret is
 * earned; not persisted, on purpose — it is a party trick for now, not a setting that should
 * still be running tomorrow when you have forgotten how you turned it on.
 */
object MikuConcertMode {
    val active = mutableStateOf(false)
}

/**
 * NEGI BATTERY: the battery glyph as a leek lying on its side. White bulb and roots on the left,
 * the stalk fills from white to green with charge, and the leaves fan out at the top end.
 * Same information as the four bars it replaces — level, charging, low — just a lot more leek.
 */
@Composable
fun MikuNegiBatteryGlyph(pct: Int, charging: Boolean, low: Boolean, modifier: Modifier = Modifier) {
    Canvas(modifier.size(width = 26.dp, height = 11.dp)) {
        val w = size.width
        val h = size.height
        val cy = h / 2f
        val bulbR = h * 0.36f
        val bulbX = bulbR + 1f
        // Roots
        for (k in -1..1) {
            drawLine(Color(0xFFE8E2D0), Offset(bulbX - bulbR * 0.6f, cy + k * 2.2f), Offset(0f, cy + k * 3.4f), strokeWidth = 1f)
        }
        val stalkStart = bulbX
        val stalkEnd = w * 0.72f
        val stalkH = h * 0.42f
        // Stalk outline
        drawRoundRectCompat(Offset(stalkStart, cy - stalkH / 2f), Size(stalkEnd - stalkStart, stalkH), Color(0x55FFFFFF), stroke = true)
        // Fill: the charge. Unknown (pct < 0) draws an empty stalk, never a flat battery.
        val frac = if (pct < 0) 0f else (pct / 100f).coerceIn(0f, 1f)
        if (frac > 0f) {
            val fillCol = when {
                charging -> Color(0xFF7CFF6B)
                low -> Color(0xFFFF6B6B)
                else -> Color(0xFF8BE36A)
            }
            drawRoundRectCompat(Offset(stalkStart, cy - stalkH / 2f), Size((stalkEnd - stalkStart) * frac, stalkH), fillCol, stroke = false)
        }
        // Bulb on top of the stalk's start
        drawCircle(Color(0xFFF5F2E6), bulbR, Offset(bulbX, cy))
        // Leaves fanning from the stalk end
        val leaf = Color(0xFF3FAF4A)
        drawLine(leaf, Offset(stalkEnd, cy), Offset(w, cy - h * 0.42f), strokeWidth = 2.2f, cap = StrokeCap.Round)
        drawLine(leaf, Offset(stalkEnd, cy), Offset(w, cy), strokeWidth = 2.2f, cap = StrokeCap.Round)
        drawLine(Color(0xFF2E8B3A), Offset(stalkEnd, cy), Offset(w - 2f, cy + h * 0.40f), strokeWidth = 2.2f, cap = StrokeCap.Round)
        if (charging) drawCircle(Color.White.copy(alpha = 0.9f), 1.6f, Offset(stalkStart + (stalkEnd - stalkStart) * frac, cy))
    }
}

private fun DrawScope.drawRoundRectCompat(topLeft: Offset, size: Size, color: Color, stroke: Boolean) {
    val r = androidx.compose.ui.geometry.CornerRadius(size.height / 2f, size.height / 2f)
    if (stroke) drawRoundRect(color, topLeft, size, r, style = Stroke(width = 1f))
    else drawRoundRect(color, topLeft, size, r)
}

/**
 * Home-screen secret effects drawn over the wallpaper: NEGI SNOW (leeks drifting down) and
 * CONCERT MODE (penlights swaying and stage beams sweeping on the beat).
 *
 * POWER. This sits on the home screen, which can be on for hours, so it is deliberately cheap:
 * about thirty primitive draws, invalidated at ~30 fps by a delay loop (not every vsync), and the
 * loop does not run at all while the ambient/low-power gate is closed, the launcher is covered, or
 * neither effect is on. Concert Mode only performs while music is actually playing.
 */
@Composable
fun MikuSecretHomeFx(isPlaying: Boolean, accent: Color, modifier: Modifier = Modifier) {
    val snow = rememberUnlockEnabled(MikuSecrets.NEGI_SNOW)
    val concertEarned = rememberUnlockEnabled(MikuSecrets.CONCERT_MODE)
    val concert = concertEarned && MikuConcertMode.active.value && isPlaying
    if (!snow && !concert) return
    val gate by com.miku.launcher.ui.rememberAmbientGate()
    val clock = remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(gate, snow, concert) {
        if (gate) return@LaunchedEffect
        while (true) {
            clock.longValue = System.currentTimeMillis()
            delay(33L)
        }
    }
    val bpmState by MikuBpmEngine.state.collectAsState()
    Canvas(modifier.fillMaxSize()) {
        val t = clock.longValue
        if (snow) drawNegiSnow(t, if (isPlaying) 2.2f else 1f)
        if (concert) drawConcert(t, bpmState.beatIntervalMs, bpmState.lastPulseEpochMs, bpmState.bpm > 0f, accent)
    }
}

private fun DrawScope.drawNegiSnow(t: Long, speedMul: Float) {
    val w = size.width
    val h = size.height
    for (i in 0 until 16) {
        val seed = (i * 0.618034f) % 1f
        val speed = (22f + 18f * ((i * 7) % 5)) * speedMul      // px per second
        val travel = h + 80f
        val y = ((seed * travel + (t % 600_000L) / 1000f * speed) % travel) - 40f
        val x = (((i * 97) % 100) / 100f) * w + sin(t / 1400.0 + i).toFloat() * 14f
        val tilt = sin(t / 1100.0 + i * 1.3).toFloat() * 25f + (i % 3 - 1) * 15f
        val len = 20f + (i % 4) * 5f
        rotate(tilt, pivot = Offset(x, y)) {
            // Stalk (white into pale green), bulb, and two leaves.
            drawLine(Color(0xCCF2F0E4), Offset(x, y), Offset(x, y + len * 0.55f), strokeWidth = 4f, cap = StrokeCap.Round)
            drawLine(Color(0xCC9BDD7A), Offset(x, y + len * 0.55f), Offset(x, y + len), strokeWidth = 4f, cap = StrokeCap.Round)
            drawLine(Color(0xCC3FAF4A), Offset(x, y + len), Offset(x - 5f, y + len + 9f), strokeWidth = 2.5f, cap = StrokeCap.Round)
            drawLine(Color(0xCC2E8B3A), Offset(x, y + len), Offset(x + 5f, y + len + 9f), strokeWidth = 2.5f, cap = StrokeCap.Round)
            drawCircle(Color(0xDDFFFFFF), 3.2f, Offset(x, y))
        }
    }
}

private val BEAM_PINK = Color(0xFFFF4FA3)
private val BEAM_TEAL = Color(0xFF39C5BB)

private fun DrawScope.drawConcert(t: Long, periodMs: Long, anchorMs: Long, hasTempo: Boolean, accent: Color) {
    val w = size.width
    val h = size.height
    // Beat phase from the real beat clock when there is one. Without a tempo the crowd still
    // waves, slowly and evenly, without pretending to be on a beat nobody measured.
    val period = if (hasTempo && periodMs in 200..2000) periodMs.toDouble() else 1400.0
    val since = if (hasTempo && anchorMs > 0L) (t - anchorMs).toDouble() else t.toDouble()
    val beats = since / period
    val beatPulse = (1.0 - (beats - kotlin.math.floor(beats))).let { it * it }.toFloat()

    // Stage beams from the top corners, sweeping on a two-bar cycle.
    val sweep = sin(beats * PI / 4.0).toFloat()
    for (k in 0 until 3) {
        val ox = w * (0.1f + 0.4f * k)
        val ang = 90f + sweep * (28f - 8f * k) * (if (k % 2 == 0) 1f else -1f)
        rotate(ang - 90f, pivot = Offset(ox, 0f)) {
            drawRect(
                (if (k == 0) accent else if (k == 1) BEAM_PINK else BEAM_TEAL).copy(alpha = 0.07f + 0.08f * beatPulse),
                topLeft = Offset(ox - 18f, 0f), size = Size(36f, h * 0.85f)
            )
        }
    }
    // Penlight crowd along the bottom: alternating colours, swaying one way per beat.
    val n = 14
    for (i in 0 until n) {
        val bx = w * (i + 0.5f) / n
        val by = h * 0.97f
        val lean = sin((beats + (i % 2) * 0.5) * PI).toFloat() * 22f
        val col = if (i % 3 == 0) Color(0xFF39C5BB) else if (i % 3 == 1) Color(0xFFFF4FA3) else accent
        rotate(lean, pivot = Offset(bx, by)) {
            drawCircle(col.copy(alpha = 0.16f + 0.18f * beatPulse), 16f, Offset(bx, by - 52f))
            drawLine(col.copy(alpha = 0.85f), Offset(bx, by), Offset(bx, by - 58f), strokeWidth = 5f, cap = StrokeCap.Round)
            drawLine(Color.White.copy(alpha = 0.55f), Offset(bx, by - 30f), Offset(bx, by - 56f), strokeWidth = 1.6f, cap = StrokeCap.Round)
        }
    }
    // A flash on the downbeat-ish (every fourth pulse), honestly just "every fourth beat".
    if (hasTempo && (kotlin.math.floor(beats).toLong() % 4L == 0L)) {
        drawRect(Color.White.copy(alpha = 0.05f * beatPulse), size = size)
    }
}
