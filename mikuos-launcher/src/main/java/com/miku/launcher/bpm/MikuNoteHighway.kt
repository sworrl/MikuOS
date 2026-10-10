package com.miku.launcher.bpm

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.android.awaitFrame
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * The thing you actually tap against.
 *
 * WHAT WAS MISSING. The game told you how you did AFTER the fact: a judgment word and a deviation
 * bar that moved once per tap. There was nothing to aim AT. Every rhythm game solves this the same
 * way and has since Guitar Hero's calibration screen: notes travel toward a fixed hit line, and you
 * tap when a note reaches it. Your eye leads the note in, so you are anticipating a moment instead
 * of reacting to a sound, which is the difference between guessing and playing.
 *
 * HOW IT IS DRIVEN. Entirely by the real beat clock. `lastPulseEpochMs` is the (phase-locked) last
 * beat the detector actually heard; `beatIntervalMs` is the locked tempo. Note n sits at
 * `lastPulse + n * period`, and its position on screen is how far away that time is. Nothing here
 * invents a beat: with no pulse and no lock the highway draws an empty lane and says so, the same
 * way the scoring refuses to judge a tap without one.
 *
 * WHAT MAKES IT A SHOW, not a metronome:
 *  - Colour comes from the album playing (two accents), walking along the run of notes, and goes
 *    rainbow during Fever.
 *  - Every note has the SKIN's silhouette (hex notes for Cyber Mirai, hearts for Hologram 39…)
 *    and the lane itself has the skin's texture, scrolling at exactly note speed, so the whole
 *    strip moves with the music rather than a few dots sliding over a static trough.
 *  - Lucky notes are gold. Hit one GREAT or better for a surprise (see MikuBeatClickerEngine.luckyNote).
 *  - The lane flashes on every beat and its rails brighten with the combo rung.
 *  - Chaos mutators are real here: SILENT DISCO fogs notes out before they arrive, MIRROR STAGE
 *    sends them from the other side, DOUBLE TIME makes them fly twice as fast.
 *
 * The calibration offset is applied to the HIT LINE, not to the notes, so what you see and what
 * you are judged against are the same number.
 *
 * COST. One Canvas, invalidated per frame through float/long state read only in the draw lambda,
 * so nothing around it recomposes. Note shapes are unit Paths built once per skin and drawn with
 * translate+scale, so a frame allocates nothing.
 */
@Composable
fun MikuNoteHighway(
    lastPulseEpochMs: Long,
    beatIntervalMs: Long,
    calibrationMs: Int,
    windows: MikuRhythmTiming.Windows,
    /** Last judged tap time, for the hit spark. 0 means no tap yet. */
    lastTapMs: Long,
    lastOffsetMs: Int,
    accent: Color,
    accent2: Color = accent,
    /** Height of the lane. Set to the tap node's size when the node sits on the hit line. */
    laneHeight: androidx.compose.ui.unit.Dp = 64.dp,
    /** Where the hit line sits across the lane, 0..1. 0.5 puts it under a centred tap node. */
    hitFraction: Float = 0.74f,
    modifier: Modifier = Modifier,
    skin: MikuBeatClickerEngine.BpmSkin = MikuBeatClickerEngine.BpmSkin.SAKURA_DREAM,
    fever: Boolean = false,
    chaos: MikuStagePerformance.Chaos = MikuStagePerformance.Chaos.NONE,
    /** 0..6, the combo rung reached. Brightens the rails. */
    comboRung: Int = 0,
    /** Tier of the last judged tap, for the spark colour. Null = free tap / none. */
    lastAccuracy: HitAccuracy? = null,
    /** Drawn ON the hit line, on top of the lane. This is where the tap node goes. */
    content: (@Composable androidx.compose.foundation.layout.BoxScope.() -> Unit)? = null
) {
    // Per-frame clock. Read ONLY in the draw lambda below.
    val now = remember { mutableLongStateOf(System.currentTimeMillis()) }
    val sparkAge = remember { mutableFloatStateOf(1f) }
    val lastSeenTap = remember { mutableLongStateOf(0L) }
    // Unit-radius silhouettes, built once per skin: drawing them is translate + scale, no Path per frame.
    val notePath = remember(skin.nodeShape) { unitShapePath(skin.nodeShape) }
    val hexPath = remember { unitShapePath(MikuBeatClickerEngine.NodeShape.HEX) }

    LaunchedEffect(Unit) {
        while (true) {
            awaitFrame()
            now.longValue = System.currentTimeMillis()
            if (lastSeenTap.longValue != lastTapMs) { lastSeenTap.longValue = lastTapMs; sparkAge.floatValue = 0f }
            if (sparkAge.floatValue < 1f) sparkAge.floatValue = (sparkAge.floatValue + 0.05f).coerceAtMost(1f)
        }
    }

    Box(modifier.fillMaxWidth().height(laneHeight), contentAlignment = androidx.compose.ui.Alignment.Center) {
        Canvas(Modifier.fillMaxWidth().height(laneHeight)) {
            val w = size.width
            val h = size.height
            // The hit line is wherever the caller put the thing you tap. With the beat node on it,
            // the note arrives UNDER YOUR THUMB: you are not looking at one place and tapping
            // another, which is the whole reason a note highway works.
            val hitX = w * hitFraction
            val period = beatIntervalMs.toFloat()
            val live = lastPulseEpochMs > 0L && beatIntervalMs in 60..3000
            // MIRROR STAGE: notes arrive from the other side. dir = +1 from the right, -1 from the left.
            val dir = if (chaos.mirrorsBar) -1f else 1f
            val runway = if (dir > 0f) (w - hitX) else hitX

            drawLane(h, w, accent, accent2, fever)

            if (!live) {
                // No tempo lock: draw the lane and nothing else. Never a fake note.
                drawHitLine(hitX, h, accent.copy(alpha = 0.35f), 0f)
                return@Canvas
            }

            // How many ms of future the lane shows. Two beats of run-up, clamped so a very slow or
            // very fast track still reads: at 60 BPM two beats is 2s, at 200 it is 600ms.
            // DOUBLE TIME halves the run-up: same beats, they just arrive at twice the speed.
            val speed = if (chaos == MikuStagePerformance.Chaos.DOUBLE_TIME) 0.5f else 1f
            val lookaheadMs = (period * 2f).coerceIn(700f, 2200f) * speed
            val pxPerMs = runway / lookaheadMs

            val t = now.longValue - calibrationMs
            val sinceLast = (t - lastPulseEpochMs).toFloat()
            val nextIdx = kotlin.math.ceil(sinceLast / period).toInt()

            // 0 at the beat, →1 just before the next. Drives the line's breathing and the lane flash.
            val phase = (sinceLast.mod(period)) / period
            val beat = (1f - phase).coerceIn(0f, 1f).let { it * it }

            // The lane texture scrolls at exactly note speed, so the whole strip moves as one.
            val scrollPx = (t.mod(60_000L)).toFloat() * pxPerMs * dir
            drawLaneTexture(skin.laneStyle, w, h, scrollPx, beat, accent, accent2, hexPath)

            // Beat flash across the whole lane, and rails that glow brighter the higher the rung.
            drawRect(accent.copy(alpha = 0.07f * beat + if (fever) 0.05f * beat else 0f), size = Size(w, h))
            val railA = 0.25f + 0.08f * comboRung.coerceIn(0, 6) + 0.25f * beat
            drawLine(accent.copy(alpha = railA.coerceAtMost(1f)), Offset(0f, h * 0.10f), Offset(w, h * 0.10f), strokeWidth = 1.5f + comboRung * 0.4f)
            drawLine(accent2.copy(alpha = railA.coerceAtMost(1f)), Offset(0f, h * 0.90f), Offset(w, h * 0.90f), strokeWidth = 1.5f + comboRung * 0.4f)

            // Windows as widths on the lane, so the player can SEE how much room each tier has.
            drawWindowBands(hitX, h, pxPerMs, windows, accent, accent2)
            drawHitLine(hitX, h, if (fever) Color.White else accent, phase)

            // Notes: the one just past the line (so a late tap still has something to point at),
            // and everything inside the lookahead.
            for (i in (nextIdx - 1)..(nextIdx + 10)) {
                val beatAt = lastPulseEpochMs + i.toLong() * beatIntervalMs
                val msAway = (beatAt - t).toFloat()
                if (msAway > lookaheadMs) break
                val x = hitX + msAway * pxPerMs * dir
                if (x < -30f || x > w + 30f) continue
                // A downbeat every fourth note, drawn bigger. The detector does not know the bar
                // line, so this is honestly just "every fourth pulse since the lock", a visual
                // rhythm aid and not a claim about the music's meter.
                val strong = (i.mod(4)) == 0
                val lucky = MikuRhythmTiming.isLuckyBeat(beatAt, beatIntervalMs)
                val noteColor = when {
                    lucky -> LUCKY_GOLD
                    fever -> Color.hsv(((i * 47f + t / 9f) % 360f + 360f) % 360f, 0.75f, 1f)
                    else -> lerpColor(accent, accent2, (i.mod(8)) / 8f)
                }
                // SILENT DISCO: a note fades into fog before it reaches the line. Go on feel.
                val fog = if (chaos.hidesBeat) ((msAway / lookaheadMs - 0.35f) / 0.25f).coerceIn(0f, 1f) else 1f
                if (fog <= 0f) continue
                drawNote(x, h, msAway, lookaheadMs, strong, noteColor, notePath, skin.nodeShape, dir, fog, lucky, t)
            }

            // Hit spark: where the last judged tap landed relative to the line, in the tier's colour.
            val age = sparkAge.floatValue
            if (lastTapMs > 0L && age < 1f) {
                val sparkX = hitX + lastOffsetMs * pxPerMs * dir
                val a = (1f - age)
                val c = sparkColor(lastAccuracy, accent)
                drawCircle(c.copy(alpha = 0.55f * a), radius = h * (0.18f + 0.5f * age), center = Offset(sparkX, h / 2f))
                drawLine(c.copy(alpha = a), Offset(sparkX, h * 0.1f), Offset(sparkX, h * 0.9f), strokeWidth = 2f)
                // The reward has to be visible in peripheral vision, because on a hit the eye is
                // already on the next note: a wider ring on GREAT+, a starburst on PERFECT.
                if (lastAccuracy?.isGreatOrBetter == true) {
                    drawCircle(
                        c.copy(alpha = 0.35f * a), radius = h * (0.3f + 0.9f * age),
                        center = Offset(sparkX, h / 2f), style = Stroke(width = 2f)
                    )
                }
                if (lastAccuracy == HitAccuracy.PERFECT) {
                    val r1 = h * (0.22f + 0.2f * age)
                    val r2 = r1 + h * 0.35f * a
                    for (k in 0 until 8) {
                        val ang = k * 0.785398f + age
                        drawLine(
                            Color.White.copy(alpha = 0.8f * a),
                            Offset(sparkX + cos(ang) * r1, h / 2f + sin(ang) * r1),
                            Offset(sparkX + cos(ang) * r2, h / 2f + sin(ang) * r2),
                            strokeWidth = 2f
                        )
                    }
                }
            }
        }
        // The tap node, sitting ON the hit line: the note lands under the thumb that taps it.
        if (content != null) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(laneHeight)
                    .layout { measurable, constraints ->
                        val p = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
                        // Centre the node on the hit line rather than on the lane.
                        val x = (constraints.maxWidth * hitFraction).toInt() - p.width / 2
                        val y = (constraints.maxHeight - p.height) / 2
                        layout(constraints.maxWidth, constraints.maxHeight) { p.place(x, y) }
                    },
                contentAlignment = androidx.compose.ui.Alignment.Center,
                content = content
            )
        }
    }
}

private val LUCKY_GOLD = Color(0xFFFFD700)

private fun sparkColor(a: HitAccuracy?, accent: Color): Color = when (a) {
    HitAccuracy.PERFECT -> Color(0xFFFF3385)
    HitAccuracy.GREAT -> accent
    HitAccuracy.GOOD -> Color(0xFF66E0D8)
    HitAccuracy.OK -> Color(0xFFFFD166)
    HitAccuracy.MISS -> Color(0xFFFF4D5E)
    null -> accent
}

private fun lerpColor(a: Color, b: Color, t: Float): Color = Color(
    red = a.red + (b.red - a.red) * t,
    green = a.green + (b.green - a.green) * t,
    blue = a.blue + (b.blue - a.blue) * t,
    alpha = 1f
)

/**
 * A unit-radius silhouette centred on the origin. Built once per skin; every note on the lane is
 * this path translated and scaled, so a skin's notes are recognisably its own shape.
 */
internal fun unitShapePath(shape: MikuBeatClickerEngine.NodeShape): Path {
    val p = Path()
    fun poly(sides: Int, rot: Double) {
        for (i in 0 until sides) {
            val a = Math.toRadians(rot + i * 360.0 / sides)
            val x = cos(a).toFloat(); val y = sin(a).toFloat()
            if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
        }
        p.close()
    }
    fun star(points: Int, inner: Float) {
        val steps = points * 2
        for (i in 0 until steps) {
            val r = if (i % 2 == 0) 1f else inner
            val a = Math.toRadians(-90.0 + i * 360.0 / steps)
            val x = (r * cos(a)).toFloat(); val y = (r * sin(a)).toFloat()
            if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
        }
        p.close()
    }
    when (shape) {
        MikuBeatClickerEngine.NodeShape.ORB -> p.addOval(androidx.compose.ui.geometry.Rect(-1f, -1f, 1f, 1f))
        MikuBeatClickerEngine.NodeShape.DIAMOND -> poly(4, -90.0)
        MikuBeatClickerEngine.NodeShape.HEX -> poly(6, -90.0)
        MikuBeatClickerEngine.NodeShape.STAR -> star(5, 0.46f)
        MikuBeatClickerEngine.NodeShape.SNOWFLAKE -> star(6, 0.55f)
        MikuBeatClickerEngine.NodeShape.HEART -> {
            p.moveTo(0f, 0.85f)
            p.cubicTo(-1.25f, 0.05f, -0.75f, -1.05f, 0f, -0.45f)
            p.cubicTo(0.75f, -1.05f, 1.25f, 0.05f, 0f, 0.85f)
            p.close()
        }
    }
    return p
}

private fun DrawScope.drawLane(h: Float, w: Float, accent: Color, accent2: Color, fever: Boolean) {
    // The lane itself carries the album's two accents, darkened, so the whole strip belongs to
    // whatever is playing rather than being a grey trough with coloured dots on it. Fever lifts it.
    val lift = if (fever) 0.10f else 0f
    drawRect(
        brush = Brush.horizontalGradient(
            listOf(
                accent2.copy(alpha = 0.06f + lift),
                accent.copy(alpha = 0.18f + lift),
                accent2.copy(alpha = 0.28f + lift)
            )
        ),
        size = Size(w, h)
    )
}

/**
 * Per-skin lane texture, scrolling at note speed. Each style is a handful of primitive draws
 * (lines, circles, one reused hex path) — cheap enough for a 60 Hz lane on this GPU.
 */
private fun DrawScope.drawLaneTexture(
    style: MikuBeatClickerEngine.LaneStyle,
    w: Float, h: Float, scrollPx: Float, beat: Float,
    accent: Color, accent2: Color, hexPath: Path
) {
    when (style) {
        MikuBeatClickerEngine.LaneStyle.PETAL_STREAM -> {
            val spacing = w / 9f
            for (i in 0 until 11) {
                val x = ((i * spacing - scrollPx) % w + w) % w
                val y = h * (0.2f + 0.6f * (((i * 37) % 10) / 10f)) + sin((x / w) * 6.28f + i) * h * 0.05f
                drawCircle(accent.copy(alpha = 0.16f), radius = h * 0.035f, center = Offset(x, y))
                drawCircle(accent2.copy(alpha = 0.10f), radius = h * 0.06f, center = Offset(x + h * 0.03f, y))
            }
        }
        MikuBeatClickerEngine.LaneStyle.NEON_GRID -> {
            val spacing = h * 0.32f
            val n = (w / spacing).toInt() + 2
            val off = ((scrollPx % spacing) + spacing) % spacing
            for (i in 0..n) {
                val x = i * spacing - off
                drawLine(accent.copy(alpha = 0.10f + 0.12f * beat), Offset(x, h * 0.1f), Offset(x, h * 0.9f), strokeWidth = 1f)
            }
            for (j in 1..3) {
                val y = h * (0.1f + 0.2f * j)
                drawLine(accent2.copy(alpha = 0.08f), Offset(0f, y), Offset(w, y), strokeWidth = 1f)
            }
        }
        MikuBeatClickerEngine.LaneStyle.HONEYCOMB -> {
            val r = h * 0.13f
            val spacing = r * 1.8f
            val n = (w / spacing).toInt() + 2
            val off = ((scrollPx % spacing) + spacing) % spacing
            for (i in 0..n) {
                for (row in 0..1) {
                    val x = i * spacing - off + if (row == 1) spacing / 2f else 0f
                    val y = h * (0.33f + 0.34f * row)
                    translate(x, y) { scale(r, r, pivot = Offset.Zero) {
                        drawPath(hexPath, accent.copy(alpha = 0.09f + 0.06f * beat))
                    } }
                }
            }
        }
        MikuBeatClickerEngine.LaneStyle.VELVET_LACE -> {
            // A slow heartbeat swell and lace dots along both rails.
            drawRect(accent2.copy(alpha = 0.10f * beat), size = Size(w, h))
            val spacing = h * 0.14f
            val n = (w / spacing).toInt() + 2
            val off = ((scrollPx % spacing) + spacing) % spacing
            for (i in 0..n) {
                val x = i * spacing - off
                val big = i % 3 == 0
                drawCircle(accent.copy(alpha = if (big) 0.30f else 0.16f), radius = if (big) 2.6f else 1.6f, center = Offset(x, h * 0.16f))
                drawCircle(accent.copy(alpha = if (big) 0.30f else 0.16f), radius = if (big) 2.6f else 1.6f, center = Offset(x, h * 0.84f))
            }
        }
        MikuBeatClickerEngine.LaneStyle.FROST_STREAK -> {
            val spacing = w / 7f
            for (i in 0 until 9) {
                val x = ((i * spacing - scrollPx) % w + w) % w
                val y0 = h * (0.2f + 0.15f * (i % 4))
                drawLine(
                    Color.White.copy(alpha = 0.10f + 0.08f * beat),
                    Offset(x, y0), Offset(x + h * 0.45f, y0 + h * 0.18f),
                    strokeWidth = 1.2f
                )
                drawCircle(accent.copy(alpha = 0.18f), radius = 1.8f, center = Offset(x + h * 0.45f, y0 + h * 0.18f))
            }
        }
        MikuBeatClickerEngine.LaneStyle.HOLO_SCAN -> {
            // Interference bands rolling down the lane, and a glitch slice just after each beat.
            val band = h * 0.12f
            val roll = ((scrollPx * 0.15f) % (band * 2f) + band * 2f) % (band * 2f)
            var y = -band * 2f + roll
            while (y < h) {
                drawRect(accent.copy(alpha = 0.06f), topLeft = Offset(0f, y), size = Size(w, band))
                y += band * 2f
            }
            if (beat > 0.75f) {
                val gy = h * 0.42f
                drawRect(accent2.copy(alpha = 0.22f), topLeft = Offset(6f, gy), size = Size(w, h * 0.08f))
                drawRect(accent.copy(alpha = 0.18f), topLeft = Offset(-6f, gy + h * 0.1f), size = Size(w, h * 0.04f))
            }
        }
    }
}

/** The hit line: the moment. Everything else on the lane is relative to it. */
private fun DrawScope.drawHitLine(x: Float, h: Float, c: Color, phase: Float) {
    // Brightest AT the beat and decaying through it, so the target pulses on tempo.
    val beat = (1f - phase).coerceIn(0f, 1f).let { it * it }
    drawLine(c.copy(alpha = 0.55f + 0.45f * beat), Offset(x, 0f), Offset(x, h), strokeWidth = 3f + 2f * beat)
    drawCircle(c.copy(alpha = 0.10f + 0.30f * beat), radius = h * (0.30f + 0.22f * beat), center = Offset(x, h / 2f))
    // Catcher bracket, so the line reads as a target rather than a divider.
    val armW = h * (0.16f + 0.06f * beat)
    drawLine(c, Offset(x - armW, h * 0.06f), Offset(x + armW, h * 0.06f), strokeWidth = 2f)
    drawLine(c, Offset(x - armW, h * 0.94f), Offset(x + armW, h * 0.94f), strokeWidth = 2f)
}

/**
 * The real timing windows, drawn to scale either side of the hit line. These are the same numbers
 * the judgment uses, so a window that widens on an easier difficulty tier visibly widens here.
 */
private fun DrawScope.drawWindowBands(
    hitX: Float, h: Float, pxPerMs: Float,
    windows: MikuRhythmTiming.Windows, accent: Color, accent2: Color
) {
    // Widest band in the cooler accent, tightening toward the hotter one: the closer to perfect,
    // the hotter the colour, so the gradient itself teaches the scale.
    band(hitX, h, windows.okMs * pxPerMs, accent2.copy(alpha = 0.07f))
    band(hitX, h, windows.goodMs * pxPerMs, accent2.copy(alpha = 0.12f))
    band(hitX, h, windows.greatMs * pxPerMs, accent.copy(alpha = 0.20f))
    band(hitX, h, windows.perfectMs * pxPerMs, accent.copy(alpha = 0.34f))
}

private fun DrawScope.band(hitX: Float, h: Float, halfPx: Float, color: Color) {
    if (halfPx <= 0.5f) return
    drawRect(color = color, topLeft = Offset(hitX - halfPx, h * 0.12f), size = Size(halfPx * 2f, h * 0.76f))
}

/**
 * One note, approaching. It grows and brightens as it nears the line so the eye can lead it in,
 * and a note that has passed the line fades out rather than vanishing, which is what tells you you
 * were late.
 */
private fun DrawScope.drawNote(
    x: Float, h: Float, msAway: Float, lookaheadMs: Float,
    strong: Boolean, color: Color, unitPath: Path,
    shape: MikuBeatClickerEngine.NodeShape, dir: Float, fog: Float, lucky: Boolean, t: Long
) {
    // 0 at the far edge, 1 at the line.
    val near = (1f - (msAway / lookaheadMs)).coerceIn(0f, 1f)
    val past = msAway < 0f
    val fade = (if (past) (1f + msAway / 260f).coerceIn(0f, 1f) else 1f) * fog
    if (fade <= 0f) return

    val baseR = h * (if (strong || lucky) 0.27f else 0.19f)
    val r = baseR * (0.55f + 0.45f * near)
    val alpha = (0.25f + 0.75f * near) * fade
    val cy = h / 2f

    // Trail behind the note (on the side it came from), so motion is legible at 30 fps as well as 60.
    if (!past && near > 0.15f) {
        drawLine(
            color.copy(alpha = 0.20f * alpha),
            Offset(x + r * 2.4f * dir, cy), Offset(x, cy),
            strokeWidth = max(1f, r * 0.55f)
        )
    }
    drawCircle(color.copy(alpha = 0.22f * alpha), radius = r * 1.7f, center = Offset(x, cy))
    if (shape == MikuBeatClickerEngine.NodeShape.ORB) {
        drawCircle(color.copy(alpha = alpha), radius = r, center = Offset(x, cy))
    } else {
        translate(x, cy) { scale(r * 1.15f, r * 1.15f, pivot = Offset.Zero) {
            drawPath(unitPath, color.copy(alpha = alpha))
        } }
    }
    drawCircle(Color.White.copy(alpha = 0.7f * alpha * near), radius = r * 0.38f, center = Offset(x, cy))
    if (strong && !lucky) {
        drawCircle(color.copy(alpha = 0.5f * alpha), radius = r * 1.35f, center = Offset(x, cy), style = Stroke(width = 1.5f))
    }
    if (lucky) {
        // A slowly turning four-point sparkle, so gold reads as "special" and not just "yellow".
        val spin = (t % 2000L) / 2000f * 6.283f
        val r1 = r * 1.3f
        val r2 = r * 2.1f
        for (k in 0 until 4) {
            val a = spin + k * 1.5708f
            drawLine(
                Color.White.copy(alpha = 0.85f * alpha),
                Offset(x + cos(a) * r1, cy + sin(a) * r1), Offset(x + cos(a) * r2, cy + sin(a) * r2),
                strokeWidth = 2f
            )
        }
        drawCircle(LUCKY_GOLD.copy(alpha = 0.6f * alpha), radius = r * 1.55f, center = Offset(x, cy), style = Stroke(width = 2f))
    }
}
