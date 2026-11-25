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
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.model.AppRepository
import com.fyrde.fyrandroid.model.HomeItem
import com.fyrde.fyrandroid.theme.FyrThemeManager
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * Fyr Home Screen Layout with FyrDE glass aesthetic:
 * - Smooth horizontal slide-animated 4x5 paged icon grid with persistent per-page views
 * - Long-press & drag to reorder icons across cells/pages, or drop onto another icon/folder to group
 * - Stationary long-press opens the app/folder context menu
 * - Page indicator dots + translucent frosted-glass 4-icon bottom Dock (`28dp` corner radius)
 * - Swipe UP anywhere -> FyrSearch, Swipe DOWN anywhere -> Fyr Quick Settings
 */
@SuppressLint("ViewConstructor")
class FyrHomeGridView(
    context: Context,
    private val repo: AppRepository,
    private val onLaunchApp: (AppEntry) -> Unit,
    private val onOpenFolder: (HomeItem.Folder) -> Unit,
    private val onAppLongPressMenu: (View, AppEntry) -> Unit,
    private val onFolderLongPressMenu: (View, HomeItem.Folder) -> Unit,
    private val onMoveHomeItem: (Int, Int) -> Unit,
    private val onGroupHomeItems: (Int, Int) -> Unit,
    private val onSwipeUpSearch: () -> Unit,
    private val onSwipeDownQuickSettings: () -> Unit
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(value: Float): Int = (value * density).toInt()

    private val columns = 4
    private val rows = 5
    private val itemsPerPage = columns * rows

    private var allHomeItems: List<HomeItem> = emptyList()
    private var pages: List<List<HomeItem>> = emptyList()
    private val pageGrids = ArrayList<GridLayout>()
    private var currentPage = 0

    private val pagerViewport: FrameLayout
    private val dropIndicatorView: View
    private val pageDotsContainer: LinearLayout
    private val dockContainer: LinearLayout
    private val dockBackground = GradientDrawable()

    // Interactive horizontal slide & vertical swipe tracking
    private enum class SwipeMode { NONE, HORIZONTAL, VERTICAL }
    private var swipeMode = SwipeMode.NONE
    private var touchDownX = 0f
    private var touchDownY = 0f
    private var lastRawX = 0f
    private var lastRawY = 0f
    private var swipeTargetPage = -1
    private var isPageAnimating = false
    private var velocityTracker: VelocityTracker? = null

    // Drag-and-drop reorder / folder grouping state
    private enum class DropMode { NONE, MOVE, GROUP }
    private var isDraggingItem = false
    private var dragMoved = false
    private var dragSourceIndex = -1
    private var dragSourceItem: HomeItem? = null
    private var dragSourceView: View? = null
    private var dragStartRawX = 0f
    private var dragStartRawY = 0f
    private var dragGhostView: View? = null
    private var dragTargetIndex = -1
    private var dragDropMode = DropMode.NONE
    private var pendingEdgeFlipDir = 0
    private val edgeFlipRunnable = Runnable {
        if (!isDraggingItem || pendingEdgeFlipDir == 0) return@Runnable
        val next = currentPage + pendingEdgeFlipDir
        if (next in pages.indices) {
            setCurrentPage(next, animate = true)
        }
        pendingEdgeFlipDir = 0
    }

    init {
        val rootColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(18f), dp(42f), dp(18f), dp(20f))
        }

        // Slide-animated multi-page Pager Viewport (keeps all page grids alive so icons never reload on swipe)
        pagerViewport = FrameLayout(context).apply {
            clipChildren = true
            clipToPadding = true
        }
        dropIndicatorView = View(context).apply {
            visibility = View.GONE
        }

        pagerViewport.addView(
            dropIndicatorView,
            LayoutParams(dp(70f), dp(70f))
        )
        rootColumn.addView(
            pagerViewport,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f)
        )

        // Page indicator dots above the dock
        pageDotsContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(8f), 0, dp(12f))
        }
        rootColumn.addView(pageDotsContainer)

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

        applyTheme()
    }

    private fun createPageGrid(): GridLayout = GridLayout(context).apply {
        columnCount = columns
        rowCount = rows
    }

    private fun invalidateViewTree(view: View) {
        view.invalidate()
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                invalidateViewTree(view.getChildAt(i))
            }
        }
    }

    fun applyTheme() {
        dockBackground.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(28f).toFloat()
            setColor(FyrThemeManager.panelBgColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.accentWithAlpha(0.35f))
        }
        updatePageDots()
        for (grid in pageGrids) {
            invalidateViewTree(grid)
        }
        invalidate()
    }

    fun bindLayout(homeItems: List<HomeItem>, dockApps: List<AppEntry>) {
        allHomeItems = homeItems
        val totalPages = max(1, ceil(homeItems.size / itemsPerPage.toDouble()).toInt())
        val paged = ArrayList<List<HomeItem>>(totalPages)
        for (p in 0 until totalPages) {
            val start = p * itemsPerPage
            val end = min(homeItems.size, start + itemsPerPage)
            paged.add(if (start < end) homeItems.subList(start, end) else emptyList())
        }
        pages = paged
        currentPage = currentPage.coerceIn(0, pages.size - 1)
        isPageAnimating = false
        swipeTargetPage = -1

        for (grid in pageGrids) {
            grid.animate().cancel()
            pagerViewport.removeView(grid)
        }
        pageGrids.clear()

        for (p in pages.indices) {
            val grid = createPageGrid()
            populateGrid(grid, p)
            grid.translationX = 0f
            grid.visibility = if (p == currentPage) View.VISIBLE else View.GONE
            pageGrids.add(grid)
            pagerViewport.addView(
                grid,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            )
        }

        updatePageDots()
        renderDock(dockApps)
    }

    fun setCurrentPage(pageIndex: Int, animate: Boolean = true) {
        if (pages.isEmpty() || pageGrids.isEmpty()) return
        val clamped = pageIndex.coerceIn(0, pages.size - 1)
        if (clamped == currentPage) return

        val activeGrid = pageGrids.getOrNull(currentPage) ?: return
        val targetGrid = pageGrids.getOrNull(clamped) ?: return

        val vpWidth = pagerViewport.width.toFloat()
        if (!animate || vpWidth <= 0f) {
            activeGrid.animate().cancel()
            targetGrid.animate().cancel()
            activeGrid.visibility = View.GONE
            activeGrid.translationX = 0f
            targetGrid.visibility = View.VISIBLE
            targetGrid.translationX = 0f
            currentPage = clamped
            isPageAnimating = false
            updatePageDots()
            return
        }

        val direction = if (clamped > currentPage) 1 else -1
        isPageAnimating = true
        activeGrid.animate().cancel()
        targetGrid.animate().cancel()
        targetGrid.visibility = View.VISIBLE
        targetGrid.translationX = direction * vpWidth
        activeGrid.translationX = 0f

        val interp = DecelerateInterpolator(1.8f)
        activeGrid.animate()
            .translationX(-direction * vpWidth)
            .setDuration(220L)
            .setInterpolator(interp)
            .start()
        targetGrid.animate()
            .translationX(0f)
            .setDuration(220L)
            .setInterpolator(interp)
            .withEndAction {
                commitSwappedPage(oldPage = currentPage, newPage = clamped)
            }
            .start()
    }

    private fun commitSwappedPage(oldPage: Int, newPage: Int) {
        pageGrids.getOrNull(oldPage)?.apply {
            visibility = View.GONE
            translationX = 0f
        }
        currentPage = newPage
        pageGrids.getOrNull(newPage)?.apply {
            visibility = View.VISIBLE
            translationX = 0f
        }
        isPageAnimating = false
        updatePageDots()
    }

    private fun populateGrid(grid: GridLayout, pageIdx: Int) {
        grid.removeAllViews()
        val pageItems = pages.getOrNull(pageIdx) ?: emptyList()
        val pageOffset = pageIdx * itemsPerPage

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
            val item = pageItems.getOrNull(i)
            val cell = if (item != null) {
                createHomeItemTile(item, globalIndex = pageOffset + i)
            } else {
                View(context)
            }
            grid.addView(cell, lp)
        }
    }

    private fun renderDock(dockApps: List<AppEntry>) {
        dockContainer.removeAllViews()
        for (app in dockApps) {
            val tile = createDockAppTile(app)
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

    private fun createHomeItemTile(item: HomeItem, globalIndex: Int): View {
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(4f), dp(6f), dp(4f), dp(6f))
        }

        val iconView: View = when (item) {
            is HomeItem.App -> SquircleIconView(context, item.entry, repo)
            is HomeItem.Folder -> FolderIconView(context, item, repo)
        }
        box.addView(iconView, LinearLayout.LayoutParams(dp(58f), dp(58f)))

        val labelView = TextView(context).apply {
            text = item.label
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

        box.setOnClickListener {
            if (isDraggingItem) return@setOnClickListener
            when (item) {
                is HomeItem.App -> onLaunchApp(item.entry)
                is HomeItem.Folder -> onOpenFolder(item)
            }
        }
        box.setOnLongClickListener { v ->
            v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            startItemDrag(v, item, globalIndex)
            true
        }
        return box
    }

    private fun createDockAppTile(app: AppEntry): View {
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(4f), dp(6f), dp(4f), dp(6f))
        }
        val iconView = SquircleIconView(context, app, repo)
        box.addView(iconView, LinearLayout.LayoutParams(dp(58f), dp(58f)))

        box.setOnClickListener { onLaunchApp(app) }
        box.setOnLongClickListener { v ->
            v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            onAppLongPressMenu(v, app)
            true
        }
        return box
    }

    // =========================================================================
    // Drag-and-Drop Reordering & Folder Grouping
    // =========================================================================

    private fun startItemDrag(sourceView: View, item: HomeItem, globalIndex: Int) {
        if (isDraggingItem) return
        isDraggingItem = true
        dragMoved = false
        dragSourceIndex = globalIndex
        dragSourceItem = item
        dragSourceView = sourceView
        dragStartRawX = lastRawX
        dragStartRawY = lastRawY
        dragTargetIndex = globalIndex
        dragDropMode = DropMode.NONE
        swipeMode = SwipeMode.NONE

        sourceView.alpha = 0.22f

        val ghost = FrameLayout(context).apply {
            val icon: View = when (item) {
                is HomeItem.App -> SquircleIconView(context, item.entry, repo)
                is HomeItem.Folder -> FolderIconView(context, item, repo)
            }
            addView(icon, LayoutParams(dp(64f), dp(64f), Gravity.CENTER))
            scaleX = 1.12f
            scaleY = 1.12f
            alpha = 0.94f
            elevation = dp(14f).toFloat()
        }
        dragGhostView = ghost
        addView(ghost, LayoutParams(dp(72f), dp(72f)))
        positionGhostAtRaw(lastRawX, lastRawY)
    }

    private fun positionGhostAtRaw(rawX: Float, rawY: Float) {
        val ghost = dragGhostView ?: return
        val loc = IntArray(2)
        getLocationOnScreen(loc)
        ghost.x = (rawX - loc[0]) - dp(36f)
        ghost.y = (rawY - loc[1]) - dp(42f)
    }

    private fun updateDragHover(rawX: Float, rawY: Float) {
        positionGhostAtRaw(rawX, rawY)

        val selfLoc = IntArray(2)
        getLocationOnScreen(selfLoc)
        val localX = rawX - selfLoc[0]

        // Edge auto-page-turn while dragging across pages
        val edgeZone = dp(36f).toFloat()
        val desiredDir = when {
            localX < edgeZone && currentPage > 0 -> -1
            localX > width - edgeZone && currentPage < pages.lastIndex -> 1
            else -> 0
        }
        if (desiredDir != pendingEdgeFlipDir) {
            removeCallbacks(edgeFlipRunnable)
            pendingEdgeFlipDir = desiredDir
            if (desiredDir != 0) {
                postDelayed(edgeFlipRunnable, 420L)
            }
        }

        // Compute hovered cell in pagerViewport
        val vpLoc = IntArray(2)
        pagerViewport.getLocationOnScreen(vpLoc)
        val vpX = rawX - vpLoc[0]
        val vpY = rawY - vpLoc[1]
        val vpW = pagerViewport.width.toFloat()
        val vpH = pagerViewport.height.toFloat()
        if (vpW <= 0f || vpH <= 0f || vpY < 0f || vpY > vpH) {
            dropIndicatorView.visibility = View.GONE
            dragTargetIndex = -1
            dragDropMode = DropMode.NONE
            return
        }

        val cellW = vpW / columns.toFloat()
        val cellH = vpH / rows.toFloat()
        val col = (vpX / cellW).toInt().coerceIn(0, columns - 1)
        val row = (vpY / cellH).toInt().coerceIn(0, rows - 1)
        val slotInPage = row * columns + col
        val targetGlobal = currentPage * itemsPerPage + slotInPage

        val cellCenterX = (col + 0.5f) * cellW
        val cellCenterY = (row + 0.5f) * cellH
        val distRatioX = abs(vpX - cellCenterX) / (cellW * 0.5f)
        val distRatioY = abs(vpY - cellCenterY) / (cellH * 0.5f)
        val isOverCenter = distRatioX < 0.58f && distRatioY < 0.58f

        val targetExists = targetGlobal in allHomeItems.indices && targetGlobal != dragSourceIndex
        dragTargetIndex = targetGlobal
        dragDropMode = if (targetExists && isOverCenter) DropMode.GROUP else DropMode.MOVE

        // Render crisp visual cue: glowing purple circle for folder grouping vs soft rounded frame for reorder
        val indSize = if (dragDropMode == DropMode.GROUP) dp(72f) else dp(66f)
        val lp = dropIndicatorView.layoutParams as LayoutParams
        if (lp.width != indSize || lp.height != indSize) {
            lp.width = indSize
            lp.height = indSize
            dropIndicatorView.layoutParams = lp
        }
        dropIndicatorView.x = cellCenterX - indSize / 2f
        dropIndicatorView.y = cellCenterY - indSize / 2f - dp(8f)
        dropIndicatorView.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = if (dragDropMode == DropMode.GROUP) dp(22f).toFloat() else dp(18f).toFloat()
            if (dragDropMode == DropMode.GROUP) {
                setColor(FyrThemeManager.accentWithAlpha(0.28f))
                setStroke(max(2, dp(2f)), FyrThemeManager.accentColor)
            } else {
                setColor(0x22FFFFFF)
                setStroke(max(1, dp(1.5f)), 0x66FFFFFF)
            }
        }
        dropIndicatorView.visibility = if (targetGlobal == dragSourceIndex) View.GONE else View.VISIBLE
    }

    private fun finishItemDrag(commitDrop: Boolean) {
        removeCallbacks(edgeFlipRunnable)
        pendingEdgeFlipDir = 0
        dropIndicatorView.visibility = View.GONE

        val sourceIdx = dragSourceIndex
        val sourceItem = dragSourceItem
        val sourceView = dragSourceView
        val moved = dragMoved
        val targetIdx = dragTargetIndex
        val mode = dragDropMode

        dragGhostView?.let { removeView(it) }
        dragGhostView = null
        sourceView?.alpha = 1f

        isDraggingItem = false
        dragMoved = false
        dragSourceIndex = -1
        dragSourceItem = null
        dragSourceView = null
        dragTargetIndex = -1
        dragDropMode = DropMode.NONE

        if (!moved) {
            // Stationary long-press opens the app or folder context menu
            if (sourceView != null && sourceItem != null) {
                when (sourceItem) {
                    is HomeItem.App -> onAppLongPressMenu(sourceView, sourceItem.entry)
                    is HomeItem.Folder -> onFolderLongPressMenu(sourceView, sourceItem)
                }
            }
            return
        }

        if (!commitDrop || sourceIdx < 0 || targetIdx < 0 || targetIdx == sourceIdx) return

        if (mode == DropMode.GROUP && targetIdx in allHomeItems.indices) {
            onGroupHomeItems(sourceIdx, targetIdx)
        } else if (allHomeItems.isNotEmpty()) {
            onMoveHomeItem(sourceIdx, targetIdx.coerceIn(0, allHomeItems.lastIndex))
        }
    }

    // =========================================================================
    // Unified Touch Handling: Drag-and-Drop + Interactive Horizontal Slide + Vertical Swipes
    // =========================================================================

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        lastRawX = ev.rawX
        lastRawY = ev.rawY

        if (isDraggingItem) {
            when (ev.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    if (!dragMoved &&
                        (abs(ev.rawX - dragStartRawX) > dp(12f) ||
                            abs(ev.rawY - dragStartRawY) > dp(12f))
                    ) {
                        dragMoved = true
                    }
                    updateDragHover(ev.rawX, ev.rawY)
                }
                MotionEvent.ACTION_UP -> finishItemDrag(commitDrop = true)
                MotionEvent.ACTION_CANCEL -> finishItemDrag(commitDrop = false)
            }
            return true
        }

        return super.dispatchTouchEvent(ev)
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (isPageAnimating) return true
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchDownX = ev.rawX
                touchDownY = ev.rawY
                swipeMode = SwipeMode.NONE
                swipeTargetPage = -1
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain().apply { addMovement(ev) }
            }
            MotionEvent.ACTION_MOVE -> {
                velocityTracker?.addMovement(ev)
                val dx = ev.rawX - touchDownX
                val dy = ev.rawY - touchDownY
                if (abs(dx) > dp(14f) && abs(dx) > abs(dy) * 1.15f) {
                    swipeMode = SwipeMode.HORIZONTAL
                    return true
                }
                if (abs(dy) > dp(16f) && abs(dy) > abs(dx) * 1.15f) {
                    swipeMode = SwipeMode.VERTICAL
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                velocityTracker?.recycle()
                velocityTracker = null
                swipeMode = SwipeMode.NONE
            }
        }
        return super.onInterceptTouchEvent(ev)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (isPageAnimating) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchDownX = event.rawX
                touchDownY = event.rawY
                swipeMode = SwipeMode.NONE
                swipeTargetPage = -1
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain().apply { addMovement(event) }
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                velocityTracker?.addMovement(event)
                val dx = event.rawX - touchDownX
                val dy = event.rawY - touchDownY

                if (swipeMode == SwipeMode.NONE) {
                    if (abs(dx) > dp(14f) && abs(dx) > abs(dy) * 1.15f) {
                        swipeMode = SwipeMode.HORIZONTAL
                    } else if (abs(dy) > dp(16f) && abs(dy) > abs(dx) * 1.15f) {
                        swipeMode = SwipeMode.VERTICAL
                    }
                }

                if (swipeMode == SwipeMode.HORIZONTAL) {
                    updateHorizontalDrag(dx)
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val dx = event.rawX - touchDownX
                val dy = event.rawY - touchDownY
                var vx = 0f
                var vy = 0f
                velocityTracker?.let { vt ->
                    vt.addMovement(event)
                    vt.computeCurrentVelocity(1000)
                    vx = vt.xVelocity
                    vy = vt.yVelocity
                    vt.recycle()
                }
                velocityTracker = null

                when (swipeMode) {
                    SwipeMode.HORIZONTAL -> finishHorizontalDrag(dx, vx)
                    SwipeMode.VERTICAL -> {
                        if (dy < -dp(36f) || vy < -dp(360f)) {
                            onSwipeUpSearch()
                        } else if (dy > dp(36f) || vy > dp(360f)) {
                            onSwipeDownQuickSettings()
                        }
                    }
                    SwipeMode.NONE -> {}
                }
                swipeMode = SwipeMode.NONE
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun updateHorizontalDrag(dx: Float) {
        val vpWidth = pagerViewport.width.toFloat()
        if (vpWidth <= 0f) return
        val activeGrid = pageGrids.getOrNull(currentPage) ?: return

        val desiredTarget = when {
            dx < 0 && currentPage < pages.lastIndex -> currentPage + 1
            dx > 0 && currentPage > 0 -> currentPage - 1
            else -> -1
        }

        if (desiredTarget == -1) {
            // Soft rubber-band resistance at first/last page boundary
            if (swipeTargetPage != -1) {
                pageGrids.getOrNull(swipeTargetPage)?.apply {
                    visibility = View.GONE
                    translationX = 0f
                }
                swipeTargetPage = -1
            }
            activeGrid.translationX = dx * 0.25f
            return
        }

        if (desiredTarget != swipeTargetPage) {
            if (swipeTargetPage != -1) {
                pageGrids.getOrNull(swipeTargetPage)?.apply {
                    visibility = View.GONE
                    translationX = 0f
                }
            }
            swipeTargetPage = desiredTarget
            pageGrids.getOrNull(desiredTarget)?.visibility = View.VISIBLE
        }

        val dir = if (desiredTarget > currentPage) 1 else -1
        activeGrid.translationX = dx
        pageGrids.getOrNull(desiredTarget)?.translationX = dir * vpWidth + dx
    }

    private fun finishHorizontalDrag(dx: Float, velocityX: Float) {
        val vpWidth = pagerViewport.width.toFloat()
        val target = swipeTargetPage
        swipeTargetPage = -1

        if (vpWidth <= 0f) return
        val activeGrid = pageGrids.getOrNull(currentPage) ?: return
        val targetGrid = pageGrids.getOrNull(target)

        val shouldSwitch = target != -1 && targetGrid != null && (
            abs(dx) > vpWidth * 0.22f ||
                (target > currentPage && velocityX < -dp(420f)) ||
                (target < currentPage && velocityX > dp(420f))
            )

        val interp = DecelerateInterpolator(1.8f)
        if (shouldSwitch) {
            val dir = if (target > currentPage) 1 else -1
            val oldPage = currentPage
            isPageAnimating = true
            activeGrid.animate()
                .translationX(-dir * vpWidth)
                .setDuration(210L)
                .setInterpolator(interp)
                .start()
            targetGrid!!.animate()
                .translationX(0f)
                .setDuration(210L)
                .setInterpolator(interp)
                .withEndAction { commitSwappedPage(oldPage = oldPage, newPage = target) }
                .start()
        } else {
            val dir = if (target > currentPage) 1 else -1
            activeGrid.animate()
                .translationX(0f)
                .setDuration(180L)
                .setInterpolator(interp)
                .start()
            if (targetGrid != null) {
                targetGrid.animate()
                    .translationX(dir * vpWidth)
                    .setDuration(180L)
                    .setInterpolator(interp)
                    .withEndAction {
                        targetGrid.visibility = View.GONE
                        targetGrid.translationX = 0f
                    }
                    .start()
            }
        }
    }
}

/**
 * Frosted glass folder squircle showing a clean 2x2 preview of up to 4 apps inside the folder.
 */
@SuppressLint("ViewConstructor")
class FolderIconView(
    context: Context,
    folder: HomeItem.Folder,
    repo: AppRepository
) : View(context) {

    private val previewApps: List<AppEntry> = folder.apps.take(4)
    private val bitmaps = arrayOfNulls<Bitmap>(4)

    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.25f * resources.displayMetrics.density
    }
    private val fallbackPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val cellRect = RectF()

    init {
        previewApps.forEachIndexed { idx, app ->
            val cached = repo.getCachedIcon(app)
            if (cached != null) {
                bitmaps[idx] = cached
            } else {
                repo.loadIconAsync(app) { loaded ->
                    bitmaps[idx] = loaded
                    invalidate()
                }
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        val radius = w * 0.225f
        rect.set(0f, 0f, w, h)
        bgPaint.color = FyrThemeManager.panelBgColor
        borderPaint.color = FyrThemeManager.dividerColor
        canvas.drawRoundRect(rect, radius, radius, bgPaint)
        canvas.drawRoundRect(rect, radius, radius, borderPaint)

        val pad = w * 0.14f
        val gap = w * 0.08f
        val miniSize = (w - pad * 2f - gap) / 2f
        val miniRadius = miniSize * 0.24f

        for (i in previewApps.indices) {
            val r = i / 2
            val c = i % 2
            val x = pad + c * (miniSize + gap)
            val y = pad + r * (miniSize + gap)
            cellRect.set(x, y, x + miniSize, y + miniSize)
            val bmp = bitmaps[i]
            if (bmp != null && !bmp.isRecycled) {
                canvas.drawBitmap(bmp, null, cellRect, null)
            } else {
                fallbackPaint.color = FyrThemeManager.accentWithAlpha(0.35f)
                canvas.drawRoundRect(cellRect, miniRadius, miniRadius, fallbackPaint)
            }
        }
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
