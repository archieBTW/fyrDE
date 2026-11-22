package com.fyrde.fyrandroid.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Clean Canvas-drawn vector icons matching fyrDE's Material icons across
 * `fyrtaskbar/lib/ui/quick_settings.dart` and `fyrsearch/lib/main.dart`,
 * avoiding platform emoji glyphs.
 */
enum class FyrIcon {
    WIFI,
    BLUETOOTH,
    AIRPLANE,
    NIGHT_LIGHT,
    FLASHLIGHT,
    ROTATE,
    DARK_MODE,
    LIGHT_MODE,
    DND,
    HOTSPOT,
    SUN,
    VOLUME,
    CHEVRON_RIGHT,
    SEARCH,
    CLOSE,
    PREV,
    PLAY,
    PAUSE,
    NEXT,
    MUSIC_NOTE
}

@SuppressLint("ViewConstructor")
class FyrIconView(
    context: Context,
    var icon: FyrIcon,
    tint: Int
) : View(context) {

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = tint
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = tint
        style = Paint.Style.FILL
    }

    private val path = Path()
    private val rect = RectF()

    fun setTint(color: Int) {
        strokePaint.color = color
        fillPaint.color = color
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = min(width, height).toFloat()
        if (size <= 0f) return
        val cx = width / 2f
        val cy = height / 2f
        val u = size / 24f // 24x24 Material viewport
        val ox = cx - 12f * u
        val oy = cy - 12f * u
        strokePaint.strokeWidth = 2.0f * u

        when (icon) {
            FyrIcon.WIFI -> {
                // Three clean concentric arcs + bottom dot
                val baseY = oy + 18.5f * u
                for (r in floatArrayOf(12f * u, 8.2f * u, 4.6f * u)) {
                    rect.set(cx - r, baseY - r, cx + r, baseY + r)
                    canvas.drawArc(rect, -135f, 90f, false, strokePaint)
                }
                canvas.drawCircle(cx, baseY, 1.5f * u, fillPaint)
            }

            FyrIcon.BLUETOOTH -> {
                path.reset()
                path.moveTo(ox + 7f * u, oy + 7.5f * u)
                path.lineTo(ox + 16.5f * u, oy + 16.5f * u)
                path.lineTo(ox + 12f * u, oy + 20.5f * u)
                path.lineTo(ox + 12f * u, oy + 3.5f * u)
                path.lineTo(ox + 16.5f * u, oy + 7.5f * u)
                path.lineTo(ox + 7f * u, oy + 16.5f * u)
                canvas.drawPath(path, strokePaint)
            }

            FyrIcon.AIRPLANE -> {
                path.reset()
                // Fuselage
                path.moveTo(cx, oy + 3.5f * u)
                path.lineTo(cx, oy + 20f * u)
                // Main swept wings
                path.moveTo(cx, oy + 9f * u)
                path.lineTo(ox + 4f * u, oy + 14.5f * u)
                path.moveTo(cx, oy + 9f * u)
                path.lineTo(ox + 20f * u, oy + 14.5f * u)
                // Tail stabilizer
                path.moveTo(ox + 9f * u, oy + 19.5f * u)
                path.lineTo(ox + 15f * u, oy + 19.5f * u)
                canvas.drawPath(path, strokePaint)
            }

            FyrIcon.NIGHT_LIGHT, FyrIcon.DARK_MODE -> {
                // Clean filled crescent moon matching Material `nightlight_round` / `dark_mode`
                path.reset()
                val r = 7.6f * u
                rect.set(cx - r, cy - r, cx + r, cy + r)
                path.addArc(rect, 40f, 235f)
                val inner = Path()
                inner.addCircle(cx + 3.4f * u, cy - 2.4f * u, 6.4f * u, Path.Direction.CW)
                path.op(inner, Path.Op.DIFFERENCE)
                canvas.drawPath(path, fillPaint)
            }

            FyrIcon.FLASHLIGHT -> {
                path.reset()
                path.moveTo(ox + 8f * u, oy + 4f * u)
                path.lineTo(ox + 16f * u, oy + 4f * u)
                path.lineTo(ox + 14.5f * u, oy + 9f * u)
                path.lineTo(ox + 14.5f * u, oy + 20f * u)
                path.lineTo(ox + 9.5f * u, oy + 20f * u)
                path.lineTo(ox + 9.5f * u, oy + 9f * u)
                path.close()
                canvas.drawPath(path, strokePaint)
                canvas.drawCircle(cx, oy + 13f * u, 1.1f * u, fillPaint)
            }

            FyrIcon.ROTATE -> {
                val r = 7.2f * u
                rect.set(cx - r, cy - r, cx + r, cy + r)
                canvas.drawArc(rect, -60f, 290f, false, strokePaint)
                path.reset()
                path.moveTo(cx + 3.5f * u, cy - 8.8f * u)
                path.lineTo(cx + 7.2f * u, cy - 5.2f * u)
                path.lineTo(cx + 2.5f * u, cy - 4.2f * u)
                canvas.drawPath(path, strokePaint)
            }

            FyrIcon.LIGHT_MODE, FyrIcon.SUN -> {
                canvas.drawCircle(cx, cy, 4.2f * u, strokePaint)
                for (i in 0 until 8) {
                    val angle = Math.toRadians(i * 45.0)
                    val r1 = 6.8f * u
                    val r2 = 9.4f * u
                    canvas.drawLine(
                        cx + (cos(angle) * r1).toFloat(),
                        cy + (sin(angle) * r1).toFloat(),
                        cx + (cos(angle) * r2).toFloat(),
                        cy + (sin(angle) * r2).toFloat(),
                        strokePaint
                    )
                }
            }

            FyrIcon.DND -> {
                val r = 7.8f * u
                canvas.drawCircle(cx, cy, r, strokePaint)
                canvas.drawLine(cx - 4.2f * u, cy, cx + 4.2f * u, cy, strokePaint)
            }

            FyrIcon.HOTSPOT -> {
                canvas.drawCircle(cx, cy, 1.6f * u, fillPaint)
                for (r in floatArrayOf(5.2f * u, 8.8f * u)) {
                    rect.set(cx - r, cy - r, cx + r, cy + r)
                    canvas.drawArc(rect, -40f, 80f, false, strokePaint)
                    canvas.drawArc(rect, 140f, 80f, false, strokePaint)
                }
            }

            FyrIcon.VOLUME -> {
                path.reset()
                path.moveTo(ox + 4.5f * u, oy + 9.5f * u)
                path.lineTo(ox + 8.5f * u, oy + 9.5f * u)
                path.lineTo(ox + 13.5f * u, oy + 5.5f * u)
                path.lineTo(ox + 13.5f * u, oy + 18.5f * u)
                path.lineTo(ox + 8.5f * u, oy + 14.5f * u)
                path.lineTo(ox + 4.5f * u, oy + 14.5f * u)
                path.close()
                canvas.drawPath(path, fillPaint)

                for (r in floatArrayOf(3.8f * u, 7.0f * u)) {
                    rect.set(ox + 13.5f * u - r, cy - r, ox + 13.5f * u + r, cy + r)
                    canvas.drawArc(rect, -42f, 84f, false, strokePaint)
                }
            }

            FyrIcon.CHEVRON_RIGHT -> {
                path.reset()
                path.moveTo(ox + 9.5f * u, oy + 6.5f * u)
                path.lineTo(ox + 15.0f * u, cy)
                path.lineTo(ox + 9.5f * u, oy + 17.5f * u)
                canvas.drawPath(path, strokePaint)
            }

            FyrIcon.SEARCH -> {
                val r = 6.2f * u
                val scx = ox + 10.5f * u
                val scy = oy + 10.5f * u
                canvas.drawCircle(scx, scy, r, strokePaint)
                canvas.drawLine(
                    scx + 4.5f * u,
                    scy + 4.5f * u,
                    ox + 19.5f * u,
                    oy + 19.5f * u,
                    strokePaint
                )
            }

            FyrIcon.CLOSE -> {
                canvas.drawLine(ox + 6.5f * u, oy + 6.5f * u, ox + 17.5f * u, oy + 17.5f * u, strokePaint)
                canvas.drawLine(ox + 17.5f * u, oy + 6.5f * u, ox + 6.5f * u, oy + 17.5f * u, strokePaint)
            }

            FyrIcon.PREV -> {
                canvas.drawLine(ox + 6.5f * u, oy + 6.5f * u, ox + 6.5f * u, oy + 17.5f * u, strokePaint)
                path.reset()
                path.moveTo(ox + 17.5f * u, oy + 6.5f * u)
                path.lineTo(ox + 9.5f * u, cy)
                path.lineTo(ox + 17.5f * u, oy + 17.5f * u)
                path.close()
                canvas.drawPath(path, fillPaint)
            }

            FyrIcon.NEXT -> {
                canvas.drawLine(ox + 17.5f * u, oy + 6.5f * u, ox + 17.5f * u, oy + 17.5f * u, strokePaint)
                path.reset()
                path.moveTo(ox + 6.5f * u, oy + 6.5f * u)
                path.lineTo(ox + 14.5f * u, cy)
                path.lineTo(ox + 6.5f * u, oy + 17.5f * u)
                path.close()
                canvas.drawPath(path, fillPaint)
            }

            FyrIcon.PLAY -> {
                path.reset()
                path.moveTo(ox + 8.5f * u, oy + 6f * u)
                path.lineTo(ox + 18f * u, cy)
                path.lineTo(ox + 8.5f * u, oy + 18f * u)
                path.close()
                canvas.drawPath(path, fillPaint)
            }

            FyrIcon.PAUSE -> {
                rect.set(ox + 7f * u, oy + 6f * u, ox + 10.5f * u, oy + 18f * u)
                canvas.drawRoundRect(rect, 1.2f * u, 1.2f * u, fillPaint)
                rect.set(ox + 13.5f * u, oy + 6f * u, ox + 17f * u, oy + 18f * u)
                canvas.drawRoundRect(rect, 1.2f * u, 1.2f * u, fillPaint)
            }

            FyrIcon.MUSIC_NOTE -> {
                path.reset()
                path.moveTo(ox + 11f * u, oy + 16f * u)
                path.lineTo(ox + 11f * u, oy + 6f * u)
                path.lineTo(ox + 18f * u, oy + 4.5f * u)
                path.lineTo(ox + 18f * u, oy + 14.5f * u)
                canvas.drawPath(path, strokePaint)
                canvas.drawCircle(ox + 8.5f * u, oy + 16.5f * u, 2.6f * u, fillPaint)
                canvas.drawCircle(ox + 15.5f * u, oy + 15f * u, 2.6f * u, fillPaint)
            }
        }
    }
}

/**
 * Custom slim slider matching `fyrtaskbar/lib/ui/slider_row.dart`:
 * - 6dp rounded track (`accentColor @ 50%` active, `hoverColor` inactive)
 * - 16dp circular white (`textColor`) thumb
 */
@SuppressLint("ViewConstructor")
class FyrSliderBar(
    context: Context,
    private val onValueChanged: (Float) -> Unit
) : View(context) {

    private val density = resources.displayMetrics.density
    private fun dp(v: Float): Float = v * density

    var value: Float = 0.5f
        set(v) {
            field = v.coerceIn(0f, 1f)
            invalidate()
        }

    var activeTrackColor: Int = 0x80E040FB.toInt()
        set(v) {
            field = v
            invalidate()
        }

    var inactiveTrackColor: Int = 0x24FFFFFF
        set(v) {
            field = v
            invalidate()
        }

    var thumbColor: Int = 0xFFFFFFFF.toInt()
        set(v) {
            field = v
            invalidate()
        }

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val desiredH = dp(32f).toInt()
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = resolveSize(desiredH, heightMeasureSpec)
        setMeasuredDimension(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val thumbR = dp(8f)
        val trackH = dp(6f)
        val startX = thumbR
        val endX = (width - thumbR).coerceAtLeast(startX + 1f)
        val cy = height / 2f
        val thumbX = startX + (endX - startX) * value

        // Inactive full track
        trackPaint.color = inactiveTrackColor
        rect.set(startX, cy - trackH / 2f, endX, cy + trackH / 2f)
        canvas.drawRoundRect(rect, trackH / 2f, trackH / 2f, trackPaint)

        // Active track
        trackPaint.color = activeTrackColor
        rect.set(startX, cy - trackH / 2f, thumbX, cy + trackH / 2f)
        canvas.drawRoundRect(rect, trackH / 2f, trackH / 2f, trackPaint)

        // Crisp circular thumb
        thumbPaint.color = thumbColor
        canvas.drawCircle(thumbX, cy, thumbR, thumbPaint)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val thumbR = dp(8f)
        val startX = thumbR
        val endX = (width - thumbR).coerceAtLeast(startX + 1f)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                val next = ((event.x - startX) / (endX - startX)).coerceIn(0f, 1f)
                if (next != value) {
                    value = next
                    onValueChanged(next)
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                parent?.requestDisallowInterceptTouchEvent(false)
                return true
            }
        }
        return super.onTouchEvent(event)
    }
}
