package com.miku.update.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// MikuOS palette, same values as mikuos-settings' Theme.kt (#39C5BB teal, diva pink, carbon).
val MikuTeal = Color(0xFF39C5BB)
val MikuTealBright = Color(0xFF00F5D4)
val MikuPink = Color(0xFFFF2A85)
val MikuPinkBright = Color(0xFFFF4081)
val MikuGold = Color(0xFFFFD54F)
val MikuDarkBg = Color(0xFF070B0D)
val MikuSurface1 = Color(0xFF0D1417)
val MikuSurface2 = Color(0xFF131E22)
val MikuMuted = Color(0xFF7E9AA0)
val MikuWhite = Color(0xFFF0FDFE)

private val GlassFill = Brush.verticalGradient(listOf(Color(0xCC0E1D21), Color(0xCC081114)))
private val GlassEdge = Brush.linearGradient(listOf(MikuTeal.copy(alpha = 0.55f), MikuPink.copy(alpha = 0.30f)))
private val GlassEdgeHot = Brush.linearGradient(listOf(MikuPink.copy(alpha = 0.75f), MikuTealBright.copy(alpha = 0.45f)))

/** Subtle glass: translucent carbon, teal-to-pink hairline. [hot] swaps to the pink-first edge. */
fun Modifier.glassCard(hot: Boolean = false) = this
    .clip(RoundedCornerShape(16.dp))
    .background(GlassFill)
    .border(1.dp, if (hot) GlassEdgeHot else GlassEdge, RoundedCornerShape(16.dp))

@Composable
fun MikuTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = MikuTealBright,
            secondary = MikuPink,
            background = MikuDarkBg,
            surface = MikuSurface1,
            onPrimary = MikuDarkBg,
            onBackground = MikuWhite,
            onSurface = MikuWhite,
        ),
        content = content,
    )
}

@Composable
fun Section(title: String, note: String? = null, hot: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().glassCard(hot).padding(14.dp)) {
        Text(title.uppercase(), color = if (hot) MikuPinkBright else MikuTealBright, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        if (note != null) {
            Spacer(Modifier.height(2.dp))
            Text(note, color = MikuMuted, fontSize = 10.5.sp, lineHeight = 13.sp)
        }
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable
fun BodyText(text: String, color: Color = MikuMuted) {
    Text(text, color = color, fontSize = 11.5.sp, lineHeight = 15.sp)
}

@Composable
fun ActionButton(text: String, modifier: Modifier = Modifier, danger: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (danger) MikuPink.copy(alpha = 0.20f) else MikuTeal.copy(alpha = 0.22f),
            contentColor = if (danger) MikuPinkBright else MikuTealBright,
            disabledContainerColor = MikuSurface2,
            disabledContentColor = MikuMuted,
        ),
        shape = RoundedCornerShape(10.dp),
        modifier = modifier.height(38.dp),
    ) { Text(text, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
}

@Composable
fun ToggleRow(title: String, summary: String?, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
            if (summary != null) Text(summary, color = MikuMuted, fontSize = 11.sp, lineHeight = 14.sp)
        }
        Spacer(Modifier.width(10.dp))
        Switch(
            checked = checked,
            enabled = enabled,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = MikuTealBright, checkedTrackColor = Color(0xFF0F3238)),
        )
    }
}

@Composable
fun RadioRow(title: String, summary: String?, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
            .background(if (selected) MikuTealBright.copy(alpha = 0.10f) else Color.Transparent)
            .clickable(onClick = onClick).padding(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onClick, colors = RadioButtonDefaults.colors(selectedColor = MikuTealBright, unselectedColor = MikuMuted))
        Spacer(Modifier.width(4.dp))
        Column {
            Text(title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            if (summary != null) Text(summary, color = MikuMuted, fontSize = 11.sp, lineHeight = 14.sp)
        }
    }
}

@Composable
fun Chip(text: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        text,
        color = if (selected) MikuDarkBg else MikuTealBright,
        fontSize = 11.5.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(if (selected) MikuTealBright else MikuTeal.copy(alpha = 0.14f))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

@Composable
fun Badge(text: String, color: Color) {
    Text(
        text.uppercase(),
        color = color,
        fontSize = 9.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.8.sp,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(color.copy(alpha = 0.14f))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@Composable
fun ButtonRow(content: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        content()
    }
}

@Composable
fun MikuAlert(title: String, text: String, confirm: String, danger: Boolean = false, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = MikuSurface1,
        titleContentColor = Color.White,
        textContentColor = MikuMuted,
        title = { Text(title, fontWeight = FontWeight.Bold) },
        text = { Text(text) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirm, color = if (danger) MikuPinkBright else MikuTealBright, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", color = MikuMuted) } },
    )
}
