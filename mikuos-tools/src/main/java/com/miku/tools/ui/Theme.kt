package com.miku.tools.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Same palette MikuOS Settings and the launcher use (#39C5BB teal, diva pink, obsidian). Copied,
// not shared through a library module, because every other MikuOS module also carries its own
// copy and a cross-module dependency would couple build orders for three colors.
object Miku {
    val Teal = Color(0xFF39C5BB)
    val TealBright = Color(0xFF00F5D4)
    val TealGlow = Color(0xFF56F0E0)
    val Cyan = Color(0xFF00E5FF)
    val Pink = Color(0xFFFF2A85)
    val PinkSoft = Color(0xFFFF4081)
    val Purple = Color(0xFFB388FF)
    val Gold = Color(0xFFFFD54F)
    val Red = Color(0xFFFF5370)

    val Bg = Color(0xFF06090B)
    val BgDeep = Color(0xFF030506)
    val Surface = Color(0xFF0D1417)
    val Surface2 = Color(0xFF131E22)
    val Card = Color(0xFF0E191D)

    val Text = Color(0xFFF0FDFE)
    val TextDim = Color(0xFFB4CBD0)
    val Muted = Color(0xFF7E9AA0)
    val Faint = Color(0xFF4A5E63)

    /** Glass fill: mostly-transparent white over the dark backdrop reads as frosted without
     *  paying for a real backdrop blur, which this GPU cannot afford per frame. */
    val GlassTop = Color(0x1FFFFFFF)
    val GlassBottom = Color(0x0AFFFFFF)
    val GlassEdge = Color(0x3339C5BB)
}

/** Monospace for digits: the launcher's Audiowide/Orbitron are aliased to monospace too, and
 *  fixed-width numerals stop a running stopwatch from jittering sideways. */
val MikuMono = FontFamily.Monospace

private val MikuTypography = Typography().let { t ->
    t.copy(
        displayLarge = t.displayLarge.copy(fontFamily = MikuMono, fontWeight = FontWeight.Light),
        displayMedium = t.displayMedium.copy(fontFamily = MikuMono, fontWeight = FontWeight.Light),
        headlineMedium = t.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
        titleLarge = t.titleLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
        titleMedium = t.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        bodyLarge = t.bodyLarge.copy(fontSize = 17.sp),
        labelLarge = t.labelLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 15.sp),
    )
}

private val MikuColors = darkColorScheme(
    primary = Miku.Teal,
    onPrimary = Color(0xFF00201D),
    primaryContainer = Color(0xFF0F3A37),
    onPrimaryContainer = Miku.TealGlow,
    secondary = Miku.PinkSoft,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFF4A0F2A),
    onSecondaryContainer = Color(0xFFFFD9E6),
    tertiary = Miku.Purple,
    background = Miku.Bg,
    onBackground = Miku.Text,
    surface = Miku.Surface,
    onSurface = Miku.Text,
    surfaceVariant = Miku.Surface2,
    onSurfaceVariant = Miku.TextDim,
    surfaceContainer = Miku.Surface,
    surfaceContainerHigh = Miku.Surface2,
    surfaceContainerHighest = Color(0xFF1A282D),
    surfaceContainerLow = Miku.Surface,
    surfaceContainerLowest = Miku.BgDeep,
    outline = Miku.Faint,
    outlineVariant = Color(0xFF253438),
    error = Miku.Red,
)

@Composable
fun MikuTheme(content: @Composable () -> Unit) {
    // MikuOS is dark-only; ignore the system setting on purpose.
    MaterialTheme(colorScheme = MikuColors, typography = MikuTypography, content = content)
}

val NumberStyle = TextStyle(fontFamily = MikuMono, fontWeight = FontWeight.Light)
