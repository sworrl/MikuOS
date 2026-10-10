package com.miku.tools.clock

import android.os.SystemClock
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Backspace
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Replay
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.miku.tools.ui.GlassButton
import com.miku.tools.ui.GlassIconButton
import com.miku.tools.ui.GlassTextButton
import com.miku.tools.ui.Miku
import com.miku.tools.ui.MikuMono
import com.miku.tools.ui.MikuTopBar
import com.miku.tools.ui.glass
import com.miku.tools.ui.pressable
import kotlinx.coroutines.delay

@Composable
fun TimerTab() {
    val ctx = LocalContext.current
    val rev = rememberClockRevision()
    val timers = remember(rev) { ClockStore.timers(ctx) }
    var creating by remember { mutableStateOf(false) }
    val showEntry = creating || timers.isEmpty()

    var nowE by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    val anyLive = timers.any { it.state == TimerState.RUNNING || it.state == TimerState.EXPIRED }
    LaunchedEffect(anyLive) { while (anyLive) { nowE = SystemClock.elapsedRealtime(); delay(100) } }

    Column(Modifier.fillMaxSize()) {
        MikuTopBar("Timer", actions = {
            if (!showEntry) GlassIconButton(Icons.Filled.Add, "New timer", { creating = true }, tint = Miku.PinkSoft)
            else if (timers.isNotEmpty()) GlassIconButton(Icons.Outlined.Close, "Cancel", { creating = false })
        })
        if (showEntry) {
            TimerEntry(onStart = { ms, label ->
                val t = ClockStore.addTimer(ctx, ms, label)
                TimerScheduler.start(ctx, t.id)
                creating = false
            })
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 14.dp, vertical = 4.dp)) {
                items(timers, key = { it.id }) { t -> TimerCard(t, nowE) }
            }
        }
    }
}

@Composable
private fun TimerEntry(onStart: (Long, String) -> Unit) {
    // Digits shift in from the right like a microwave: typing 1 3 0 gives 1:30.
    var digits by remember { mutableStateOf("") }
    var label by remember { mutableStateOf("") }
    val padded = digits.padStart(6, '0')
    val h = padded.substring(0, 2).toInt(); val m = padded.substring(2, 4).toInt(); val s = padded.substring(4, 6).toInt()
    val ms = (h * 3600L + m * 60L + s) * 1000L

    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        val entered = digits.length
        Text(
            buildAnnotatedString {
                listOf(padded.substring(0, 2) to "h", padded.substring(2, 4) to "m", padded.substring(4, 6) to "s").forEachIndexed { gi, (num, unit) ->
                    num.forEachIndexed { ci, ch ->
                        val pos = gi * 2 + ci
                        withStyle(SpanStyle(color = if (pos >= 6 - entered) Miku.TealGlow else Miku.Faint)) { append(ch) }
                    }
                    withStyle(SpanStyle(color = Miku.Muted, fontSize = 20.sp)) { append(unit) }
                    if (gi < 2) append(" ")
                }
            },
            fontSize = 50.sp, fontFamily = MikuMono, fontWeight = FontWeight.Light,
            modifier = Modifier.padding(vertical = 6.dp)
        )
        // Presets for the common cases.
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(1, 3, 5, 10, 15, 30).forEach { min ->
                Box(
                    Modifier.pressable({ digits = (min * 100).toString() })
                        .glass(RoundedCornerShape(14.dp), rimAlpha = 0.3f).padding(horizontal = 14.dp, vertical = 8.dp)
                ) { Text("$min min", color = Miku.TextDim, fontSize = 14.sp) }
            }
        }
        Spacer(Modifier.height(8.dp))
        Column(Modifier.weight(1f).fillMaxWidth()) {
            val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("00", "0", "<"))
            rows.forEach { row ->
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    row.forEach { k ->
                        Box(
                            Modifier.weight(1f).fillMaxHeight().padding(4.dp)
                                .pressable({
                                    digits = when (k) {
                                        "<" -> digits.dropLast(1)
                                        else -> (digits + k).trimStart('0').take(6)
                                    }
                                })
                                .glass(RoundedCornerShape(18.dp)),
                            contentAlignment = Alignment.Center
                        ) {
                            if (k == "<") Icon(Icons.AutoMirrored.Outlined.Backspace, "Delete", tint = Miku.PinkSoft)
                            else Text(k, color = Miku.Text, fontSize = 26.sp)
                        }
                    }
                }
            }
        }
        OutlinedTextField(
            label, { label = it.take(40) }, Modifier.fillMaxWidth().padding(top = 6.dp), singleLine = true,
            placeholder = { Text("Label (optional)", color = Miku.Faint) },
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Miku.Teal, unfocusedBorderColor = Miku.Faint, cursorColor = Miku.Teal),
            shape = RoundedCornerShape(16.dp)
        )
        Spacer(Modifier.height(8.dp))
        GlassButton({ if (ms > 0) onStart(ms, label.trim()) }, Modifier.fillMaxWidth(), filled = true, enabled = ms > 0, minHeight = 60.dp) {
            Icon(Icons.Filled.PlayArrow, null, tint = Color(0xFF041513))
            Spacer(Modifier.width(8.dp))
            Text("Start", color = Color(0xFF041513), fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun TimerCard(t: ClockTimer, nowE: Long) {
    val ctx = LocalContext.current
    val remaining = t.remainingNow(nowE)
    val frac = (remaining.toFloat() / t.lengthMs.coerceAtLeast(1)).coerceIn(0f, 1f)
    val expired = t.state == TimerState.EXPIRED

    Column(
        Modifier.fillMaxWidth().padding(vertical = 6.dp).glass(RoundedCornerShape(26.dp), accent = if (expired) Miku.PinkSoft else Miku.Teal).padding(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(t.label.ifBlank { ClockFormat.duration(t.lengthMs) + " timer" }, color = Miku.TextDim, fontSize = 15.sp, modifier = Modifier.weight(1f))
            GlassIconButton(Icons.Outlined.Close, "Delete timer", { TimerScheduler.delete(ctx, t.id) }, plain = true, tint = Miku.Faint, size = 40.dp)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(150.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize().padding(6.dp)) {
                    val stroke = 9.dp.toPx()
                    drawArc(Color(0x22FFFFFF), 0f, 360f, false, style = Stroke(stroke))
                    drawArc(
                        Brush.sweepGradient(listOf(Miku.Teal, Miku.TealGlow, Miku.PinkSoft, Miku.Teal)),
                        -90f, 360f * frac, false, style = Stroke(stroke, cap = StrokeCap.Round)
                    )
                }
                Text(
                    ClockFormat.duration(remaining),
                    color = if (expired) Miku.PinkSoft else Miku.Text,
                    fontSize = if (remaining >= 3_600_000) 24.sp else 32.sp, fontFamily = MikuMono
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                when (t.state) {
                    TimerState.RUNNING -> GlassButton({ TimerScheduler.pause(ctx, t.id) }, Modifier.fillMaxWidth(), filled = true) {
                        Icon(Icons.Filled.Pause, "Pause", tint = Color(0xFF041513))
                    }
                    TimerState.EXPIRED -> GlassButton({ TimerScheduler.reset(ctx, t.id) }, Modifier.fillMaxWidth(), filled = true, accent = Miku.PinkSoft) {
                        Text("Stop", color = Color.White, fontWeight = FontWeight.SemiBold)
                    }
                    else -> GlassButton({ TimerScheduler.start(ctx, t.id) }, Modifier.fillMaxWidth(), filled = true) {
                        Icon(Icons.Filled.PlayArrow, "Start", tint = Color(0xFF041513))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    GlassTextButton("+1:00", { TimerScheduler.addMinute(ctx, t.id) }, Modifier.weight(1f))
                    GlassButton({ TimerScheduler.reset(ctx, t.id) }, Modifier.weight(1f), enabled = t.state != TimerState.RESET) {
                        Icon(Icons.Outlined.Replay, "Reset", tint = Miku.TealGlow)
                    }
                }
            }
        }
    }
}
