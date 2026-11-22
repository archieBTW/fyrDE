package com.fyrde.fyrandroid.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.GestureDetector
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.model.AppRepository
import com.fyrde.fyrandroid.theme.FyrThemeManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * Fyr Home Screen Layout with FyrDE glass aesthetic:
 * - Top Fyr status pill (clock, date, quick actions trigger)
 * - Horizontal paged 4x5 squircle icon grids with smooth gesture paging
 * - Page indicator dots + "Swipe up to search" pill
 * - Translucent frosted-glass 4-icon bottom Dock (`28dp` corner radius)
 * - Swipe UP anywhere on the home screen opens FyrSearch (`onSwipeUpSearch`)
 * - Swipe DOWN anywhere on the home screen opens Fyr Quick Settings (`onSwipeDownQuickSettings`)
 */
@SuppressLint("ViewConstructor")
class FyrHomeGridView(
    context: Context,
    private val repo: AppRepository,
    private val onLaunchApp: (AppEntry) -> Unit,
    private val onAppLongPressMenu: (View, AppEntry) -> Unit,
    private val onSwipeUpSearch: () -> Unit,
    private val onSwipeDownQuickSettings: () -> Unit
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(value: Float): Int = (value * density).toInt()

    private val columns = 4
    private val rows = 5
    private val itemsPerPage = columns * rows

    private var pages: List<List<AppEntry>> = emptyList()
    private var currentPage = 0

    private val headerTimeView: TextView
    private val headerDateView: TextView
    private val gridContainer: GridLayout
    private val pageDotsContainer: LinearLayout
    private val dockContainer: LinearLayout
    private val dockBackground = GradientDrawable()
    private val searchPillBackground = GradientDrawable()

    private val gestureDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true

            override fun onFling(
                e1: MotionEvent?,
                e2: MotionEvent,
                velocityX: Float,
                velocityY: Float
            ): Boolean {
                val start = e1 ?: return false
                val dx = e2.x - start.x
                val dy = e2.y - start.y

                // Prioritize vertical swipes (Up -> FyrSearch, Down -> Fyr Quick Settings)
                if (abs(dy) > abs(dx) * 1.15f && abs(dy) > dp(42f)) {
                    if (dy < 0) {
                        onSwipeUpSearch()
                    } else {
                        onSwipeDownQuickSettings()
                    }
                    return true
                }

                // Horizontal page switch
                if (abs(dx) > abs(dy) && abs(dx) > dp(48f)) {
                    if (dx < 0 && currentPage < pages.size - 1) {
                        setCurrentPage(currentPage + 1)
                        return true
                    } else if (dx > 0 && currentPage > 0) {
                        setCurrentPage(currentPage - 1)
                        return true
                    }
                }
                return false
            }
        }
    )

    private var interceptStartX = 0f
    private var interceptStartY = 0f

    init {
        val rootColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(18f), dp(42f), dp(18f), dp(20f))
        }

        // Top Fyr Header (Clock + Date + Quick Settings hint)
        val headerRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8f), dp(4f), dp(8f), dp(12f))
        }

        val clockCol = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
        }
        headerTimeView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            setTextColor(Color.WHITE)
            setShadowLayer(8f, 0f, 2f, 0x66000000)
        }
        headerDateView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(0xCCFFFFFF.toInt())
            setShadowLayer(6f, 0f, 1f, 0x55000000)
        }
        clockCol.addView(headerTimeView)
        clockCol.addView(headerDateView)

        val qsTrigger = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12f), dp(8f), dp(12f), dp(8f))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(50f).toFloat()
                setColor(0x55181620)
                setStroke(max(1, dp(1f)), 0x26FFFFFF)
            }
            setOnClickListener { onSwipeDownQuickSettings() }
        }
        qsTrigger.addView(
            FyrIconView(context, FyrIcon.WIFI, Color.WHITE),
            LinearLayout.LayoutParams(dp(15f), dp(15f)).apply { rightMargin = dp(8f) }
        )
        qsTrigger.addView(
            FyrIconView(context, FyrIcon.BLUETOOTH, 0xCCFFFFFF.toInt()),
            LinearLayout.LayoutParams(dp(15f), dp(15f))
        )

        headerRow.addView(
            clockCol,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        headerRow.addView(qsTrigger)
        rootColumn.addView(
            headerRow,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        )

        // Main 4x5 App Grid
        gridContainer = GridLayout(context).apply {
            columnCount = columns
            rowCount = rows
        }
        rootColumn.addView(
            gridContainer,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f)
        )

        // Page indicator dots + Fyr "Search" pill
        val bottomIndicatorCol = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(6f), 0, dp(10f))
        }

        pageDotsContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(8f))
        }

        val searchHintPill = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16f), dp(7f), dp(18f), dp(7f))
            background = searchPillBackground
            setOnClickListener { onSwipeUpSearch() }
        }
        searchHintPill.addView(
            FyrIconView(context, FyrIcon.SEARCH, 0xCCFFFFFF.toInt()),
            LinearLayout.LayoutParams(dp(14f), dp(14f)).apply { rightMargin = dp(7f) }
        )
        searchHintPill.addView(
            TextView(context).apply {
                text = "Search"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
                setTextColor(0xCCFFFFFF.toInt())
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            }
        )

        bottomIndicatorCol.addView(pageDotsContainer)
        bottomIndicatorCol.addView(searchHintPill)
        rootColumn.addView(bottomIndicatorCol)

        // Frosted Glass Bottom Dock (4 pinned apps)
        dockContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(12f), dp(12f), dp(12f), dp(12f))
            background = dockBackground
        }
        rootColumn.addView(
            dockContainer,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        )

        addView(
            rootColumn,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        )

        refreshClock()
        applyTheme()
    }

    fun refreshClock() {
        val now = Date()
        headerTimeView.text = SimpleDateFormat("h:mm", Locale.getDefault()).format(now)
        headerDateView.text = SimpleDateFormat("EEEE, MMMM d", Locale.getDefault()).format(now)
    }

    fun applyTheme() {
        dockBackground.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(28f).toFloat()
            setColor(FyrThemeManager.panelBgColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.accentWithAlpha(0.35f))
        }
        searchPillBackground.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(50f).toFloat()
            setColor(FyrThemeManager.panelBgColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.dividerColor)
        }
        updatePageDots()
        invalidate()
    }

    fun bindApps(allApps: List<AppEntry>, dockApps: List<AppEntry>) {
        val dockKeys = dockApps.map { it.componentKey }.toSet()
        val homeApps = allApps.filter { it.componentKey !in dockKeys }
        val totalPages = max(1, ceil(homeApps.size / itemsPerPage.toDouble()).toInt())
        val paged = ArrayList<List<AppEntry>>(totalPages)
        for (p in 0 until totalPages) {
            val start = p * itemsPerPage
            val end = min(homeApps.size, start + itemsPerPage)
            paged.add(if (start < end) homeApps.subList(start, end) else emptyList())
        }
        pages = paged
        currentPage = currentPage.coerceIn(0, pages.size - 1)
        renderCurrentPage()
        renderDock(dockApps)
    }

    fun setCurrentPage(pageIndex: Int) {
        if (pages.isEmpty()) return
        val clamped = pageIndex.coerceIn(0, pages.size - 1)
        if (clamped == currentPage && gridContainer.childCount > 0) return
        currentPage = clamped
        gridContainer.alpha = 0.4f
        renderCurrentPage()
        gridContainer.animate().alpha(1f).setDuration(140L).start()
    }

    private fun renderCurrentPage() {
        gridContainer.removeAllViews()
        val pageApps = pages.getOrNull(currentPage) ?: emptyList()

        for (i in 0 until itemsPerPage) {
            val row = i / columns
            val col = i % columns
            val lp = GridLayout.LayoutParams(
                GridLayout.spec(row, 1f),
                GridLayout.spec(col, 1f)
            ).apply {
                width = 0
                height = 0
            }
            val app = pageApps.getOrNull(i)
            val cell = if (app != null) createAppTile(app, showLabel = true) else View(context)
            gridContainer.addView(cell, lp)
        }
        updatePageDots()
    }

    private fun renderDock(dockApps: List<AppEntry>) {
        dockContainer.removeAllViews()
        for (app in dockApps) {
            val tile = createAppTile(app, showLabel = false)
            val lp = LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
            dockContainer.addView(tile, lp)
        }
    }

    private fun updatePageDots() {
        pageDotsContainer.removeAllViews()
        val count = max(1, pages.size)
        for (i in 0 until count) {
            val active = i == currentPage
            val dot = View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(4f).toFloat()
                    setColor(
                        if (active) FyrThemeManager.accentColor
                        else 0x55FFFFFF
                    )
                }
            }
            val lp = LinearLayout.LayoutParams(
                if (active) dp(18f) else dp(7f),
                dp(7f)
            ).apply {
                setMargins(dp(4f), 0, dp(4f), 0)
            }
            pageDotsContainer.addView(dot, lp)
        }
    }

    private fun createAppTile(app: AppEntry, showLabel: Boolean): View {
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(4f), dp(6f), dp(4f), dp(6f))
        }

        val iconView = SquircleIconView(context, app, repo)
        box.addView(iconView, LinearLayout.LayoutParams(dp(58f), dp(58f)))

        if (showLabel) {
            val labelView = TextView(context).apply {
                text = app.label
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                setTextColor(Color.WHITE)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER
                setPadding(dp(2f), dp(5f), dp(2f), 0)
                setShadowLayer(4f, 0f, 1f, 0x99000000.toInt())
            }
            box.addView(
                labelView,
                LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            )
        }

        box.setOnClickListener {
            onLaunchApp(app)
        }
        box.setOnLongClickListener { v ->
            v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            onAppLongPressMenu(v, app)
            true
        }
        return box
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        gestureDetector.onTouchEvent(ev)
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                interceptStartX = ev.x
                interceptStartY = ev.y
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = abs(ev.x - interceptStartX)
                val dy = abs(ev.y - interceptStartY)
                if (dx > dp(20f) || dy > dp(20f)) {
                    return true
                }
            }
        }
        return super.onInterceptTouchEvent(ev)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        return gestureDetector.onTouchEvent(event) || super.onTouchEvent(event)
    }
}

/**
 * Ultra-low-overhead custom View that renders an app's cached squircle bitmap or a clean monogram fallback.
 */
@SuppressLint("ViewConstructor")
class SquircleIconView(
    context: Context,
    private val app: AppEntry,
    repo: AppRepository
) : View(context) {

    private var bitmap: Bitmap? = repo.getCachedIcon(app)
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * resources.displayMetrics.density
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
    }
    private val rect = RectF()

    init {
        if (bitmap == null) {
            repo.loadIconAsync(app) { loaded ->
                bitmap = loaded
                invalidate()
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        rect.set(0f, 0f, w, h)
        val radius = w * 0.225f

        val bmp = bitmap
        if (bmp != null && !bmp.isRecycled) {
            canvas.drawBitmap(bmp, null, rect, null)
        } else {
            bgPaint.color = FyrThemeManager.accentWithAlpha(0.32f)
            borderPaint.color = FyrThemeManager.accentWithAlpha(0.65f)
            canvas.drawRoundRect(rect, radius, radius, bgPaint)
            canvas.drawRoundRect(rect, radius, radius, borderPaint)
            textPaint.textSize = w * 0.42f
            val initial = app.label.firstOrNull()?.uppercaseChar()?.toString() ?: "?"
            val yPos = h / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
            canvas.drawText(initial, w / 2f, yPos, textPaint)
        }
    }
}
