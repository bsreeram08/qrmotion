package io.github.bsreeram08.qrmotion.compose

import android.content.Context
import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import io.github.bsreeram08.qrmotion.Ecc
import io.github.bsreeram08.qrmotion.Effect
import io.github.bsreeram08.qrmotion.Effects
import io.github.bsreeram08.qrmotion.QrAnimation
import io.github.bsreeram08.qrmotion.RenderOptions
import io.github.bsreeram08.qrmotion.Rgb
import io.github.bsreeram08.qrmotion.encode

/**
 * An animated QR code where every frame still scans. Draws a static first frame when the system
 * animator duration scale is 0 (reduced motion). Throws [IllegalArgumentException] if [text] does
 * not fit or [ink] is not much darker than [paper].
 */
@Composable
public fun AnimatedQr(
    text: String,
    modifier: Modifier = Modifier,
    effect: Effect = Effects.Slide,
    ecc: Ecc = Ecc.Q,
    ink: Color = Color(0xFF17132A),
    paper: Color = Color(0xFFF5F2EA),
    durationMillis: Int = 2400,
) {
    val animation = remember(text, ecc, effect, ink, paper, durationMillis) {
        QrAnimation(
            encode(text, ecc),
            RenderOptions(effect = effect, ink = ink.toRgb(), paper = paper.toRgb(), duration = durationMillis / 1000.0),
        )
    }
    val context = LocalContext.current
    val reducedMotion = remember(context) { context.animationsDisabled() }
    val animated = !reducedMotion && effect !== Effects.None
    val cycleNanos = durationMillis * 1_000_000L

    // Only the draw phase reads this, so frames invalidate drawing, never composition.
    var elapsedNanos by remember { mutableLongStateOf(0L) }
    if (animated) {
        LaunchedEffect(cycleNanos) {
            val start = withFrameNanos { it }
            while (true) withFrameNanos { elapsedNanos = (it - start) % cycleNanos }
        }
    }

    Canvas(
        modifier
            .aspectRatio(1f)
            .semantics { contentDescription = "QR code: $text" },
    ) {
        val t = if (animated) elapsedNanos / 1e9 else 0.0
        drawFrame(animation, paper, t)
    }
}

private fun DrawScope.drawFrame(animation: QrAnimation, paper: Color, t: Double) {
    val scale = size.minDimension / animation.modules
    drawRect(paper, size = Size(animation.modules * scale, animation.modules * scale))
    for (s in animation.shapes(t)) {
        val w = (s.w * scale).toFloat()
        val h = (s.h * scale).toFloat()
        val r = minOf((s.r * scale).toFloat(), w / 2, h / 2)
        translate((s.cx * scale).toFloat(), (s.cy * scale).toFloat()) {
            rotate(s.rot.toFloat(), pivot = Offset.Zero) {
                drawRoundRect(
                    color = s.fill.toColor(),
                    topLeft = Offset(-w / 2, -h / 2),
                    size = Size(w, h),
                    cornerRadius = CornerRadius(r),
                )
            }
        }
    }
}

private fun Rgb.toColor(): Color = Color(channel(r), channel(g), channel(b))

private fun channel(v: Double): Float = (v / 255).toFloat().coerceIn(0f, 1f)

private fun Color.toRgb(): Rgb {
    val argb = toArgb()
    return Rgb(((argb shr 16) and 0xFF).toDouble(), ((argb shr 8) and 0xFF).toDouble(), (argb and 0xFF).toDouble())
}

private fun Context.animationsDisabled(): Boolean =
    Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
