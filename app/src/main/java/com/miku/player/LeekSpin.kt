package com.miku.player

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import com.miku.player.bpm.MikuBpmEngine
import kotlinx.coroutines.delay

/**
 * The secret leek (MikuUnlocksReader.SECRET_LEEK_SPIN): a small spring onion twirling in a corner
 * of the Now Playing stage, after the old leek-spin loop.
 *
 * TEMPO HONESTY. With a real tempo from MikuBpmEngine and the music playing, it turns once every
 * two beats. That matches the tempo, not the downbeat: the app has no beat phase to lock to, so it
 * does not claim one. With no tempo (0 = unknown) or while paused it does not spin at all; it
 * sways at a fixed slow rate, so it is never seen keeping time it does not have.
 *
 * COST. The angle lives in one float state that is read only inside graphicsLayer, so a frame
 * re-draws this layer and recomposes nothing. Paths and brushes are built in drawWithCache and
 * only rebuilt on a size change. The caller removes it entirely while the screen is idle, which
 * also ends the frame loop.
 */
@Composable
fun LeekSpin(playing: Boolean, modifier: Modifier = Modifier) {
    // currentBpm is a plain volatile, not Compose state. Sample it once a second; the state write
    // is a no-op (no recomposition) while the value stays the same.
    var bpm by remember { mutableFloatStateOf(MikuBpmEngine.currentBpm) }
    LaunchedEffect(Unit) {
        while (true) {
            bpm = MikuBpmEngine.currentBpm
            delay(1000)
        }
    }
    val playingNow by rememberUpdatedState(playing)
    val bpmNow by rememberUpdatedState(bpm)

    var angle by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        var spinPhase = 0f       // degrees, accumulated so a tempo change never makes it jump
        var swayT = 0f           // seconds of sway
        var last = 0L
        while (true) {
            val now = withFrameNanos { it }
            val dt = if (last == 0L) 0f else ((now - last) / 1_000_000_000f).coerceAtMost(0.1f)
            last = now
            val b = bpmNow
            if (b > 0f && playingNow) {
                // Coming out of a sway: pick the spin up from the current angle, not from zero.
                if (swayT > 0f) spinPhase = (angle % 360f + 360f) % 360f
                // 360 degrees per two beats = 180 degrees per beat.
                spinPhase = (spinPhase + dt * (b / 60f) * 180f) % 360f
                angle = spinPhase
                swayT = 0f
            } else {
                // Fixed, unhurried sway: a 3.2 s period, +-16 degrees, eased back from wherever the
                // spin stopped so it does not snap.
                swayT += dt
                val target = 16f * kotlin.math.sin(swayT * (2f * Math.PI.toFloat() / 3.2f))
                val from = if (spinPhase > 180f) spinPhase - 360f else spinPhase
                val ease = (swayT / 0.6f).coerceAtMost(1f)
                angle = from + (target - from) * ease
                if (ease >= 1f) spinPhase = 0f
            }
        }
    }

    Box(
        modifier
            .graphicsLayer { rotationZ = angle }
            .drawWithCache {
                // Drawn in a 100 x 100 unit box, leaves up, bulb down.
                val u = size.minDimension / 100f
                val ox = (size.width - 100f * u) / 2f
                val oy = (size.height - 100f * u) / 2f
                fun p(x: Float, y: Float) = Offset(ox + x * u, oy + y * u)

                val leafL = Path().apply {
                    moveTo(p(45f, 44f).x, p(45f, 44f).y)
                    quadraticBezierTo(p(30f, 24f).x, p(30f, 24f).y, p(18f, 4f).x, p(18f, 4f).y)
                    quadraticBezierTo(p(38f, 18f).x, p(38f, 18f).y, p(51f, 42f).x, p(51f, 42f).y)
                    close()
                }
                val leafC = Path().apply {
                    moveTo(p(46f, 44f).x, p(46f, 44f).y)
                    quadraticBezierTo(p(48f, 18f).x, p(48f, 18f).y, p(53f, 1f).x, p(53f, 1f).y)
                    quadraticBezierTo(p(57f, 20f).x, p(57f, 20f).y, p(55f, 44f).x, p(55f, 44f).y)
                    close()
                }
                val leafR = Path().apply {
                    moveTo(p(50f, 43f).x, p(50f, 43f).y)
                    quadraticBezierTo(p(66f, 22f).x, p(66f, 22f).y, p(84f, 8f).x, p(84f, 8f).y)
                    quadraticBezierTo(p(70f, 28f).x, p(70f, 28f).y, p(56f, 46f).x, p(56f, 46f).y)
                    close()
                }
                val stemTL = p(43f, 40f)
                val stemSize = Size(14f * u, 40f * u)
                val stemBrush = Brush.verticalGradient(
                    listOf(Color(0xFFB8E6A0), Color(0xFFEFFBE6), Color(0xFFFFFFFF)),
                    startY = stemTL.y, endY = stemTL.y + stemSize.height
                )
                val bulbTL = p(39f, 70f)
                val bulbSize = Size(22f * u, 22f * u)
                val leafGreen = Color(0xFF3FAE4A)
                val leafDark = Color(0xFF1E6B2A)
                val outline = Color(0xCC0B2A12)
                val line = Stroke(width = 1.6f * u)
                val rootColor = Color(0xFFD9CBA3)
                val rootW = 1.4f * u
                val r0 = p(50f, 91f); val rA = p(44f, 99f); val rB = p(50f, 100f); val rC = p(56f, 99f)

                onDrawBehind {
                    // Roots, bulb, stem, then the leaves over the top of the stem.
                    drawLine(rootColor, r0, rA, rootW, StrokeCap.Round)
                    drawLine(rootColor, r0, rB, rootW, StrokeCap.Round)
                    drawLine(rootColor, r0, rC, rootW, StrokeCap.Round)
                    drawOval(Color.White, topLeft = bulbTL, size = bulbSize)
                    drawOval(outline, topLeft = bulbTL, size = bulbSize, style = line)
                    drawRect(stemBrush, topLeft = stemTL, size = stemSize)
                    drawRect(outline, topLeft = stemTL, size = stemSize, style = line)
                    drawPath(leafL, leafDark)
                    drawPath(leafR, leafDark)
                    drawPath(leafC, leafGreen)
                    drawPath(leafL, outline, style = line)
                    drawPath(leafC, outline, style = line)
                    drawPath(leafR, outline, style = line)
                }
            }
    )
}
