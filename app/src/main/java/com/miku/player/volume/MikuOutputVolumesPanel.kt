package com.miku.player.volume

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CutCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.miku.player.AudiowideFont
import com.miku.player.MikuCyan

/**
 * A slider per output, beside the volume HUD, while playing to more than one.
 *
 * Shown and hidden with the HUD itself, so it appears on any volume change and gives the knob
 * and keys context: they move every row together (MikuOutputVolumes links them), and dragging a
 * row sets that output alone. Touching a slider keeps the HUD up. With one output it does not
 * exist; the HUD alone already says everything.
 */
@Composable
fun MikuOutputVolumesPanel(modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val outputs by MikuOutputVolumes.outputs.collectAsState()
    val hud by MikuVolumeManager.state.collectAsState()
    AnimatedVisibility(
        visible = hud.isHudVisible && outputs.size >= 2,
        enter = fadeIn(tween(140)) + slideInHorizontally(tween(160)) { it / 2 },
        exit = fadeOut(tween(220)) + slideOutHorizontally(tween(220)) { it / 2 },
        modifier = modifier,
    ) {
        Column(
            Modifier
                .width(176.dp)
                .background(Color(0xF0061A24), CutCornerShape(10.dp))
                .border(1.dp, MikuCyan.copy(alpha = 0.6f), CutCornerShape(10.dp))
                .padding(horizontal = 8.dp, vertical = 6.dp)
        ) {
            Text("OUTPUTS", color = MikuCyan, fontSize = 8.sp, fontFamily = AudiowideFont)
            for (o in outputs) {
                Spacer(Modifier.height(4.dp))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        o.label + if (o.primary) " ★" else "",
                        color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold,
                        maxLines = 1, modifier = Modifier.weight(1f)
                    )
                    Text("${o.pct}%", color = MikuCyan, fontSize = 9.sp, fontFamily = AudiowideFont)
                }
                if (MikuOutputVolumes.available) {
                    Slider(
                        value = o.index.toFloat(),
                        onValueChange = {
                            MikuOutputVolumes.setLevel(o.id, it.toInt())
                            MikuVolumeManager.triggerHud(ctx)          // keep the HUD up while dragging
                        },
                        valueRange = 0f..o.max.toFloat(),
                        steps = (o.max - 1).coerceAtLeast(0),
                        colors = SliderDefaults.colors(
                            thumbColor = MikuCyan, activeTrackColor = MikuCyan,
                            inactiveTrackColor = Color(0x334DD0E1),
                        ),
                        modifier = Modifier.height(22.dp),
                    )
                }
            }
            if (!MikuOutputVolumes.available) {
                Text(
                    "Per-output volume not permitted on this build",
                    color = Color(0xFFFF8A80), fontSize = 7.5.sp
                )
            }
        }
    }
}
