package com.fyrde.fyrandroid.service

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import com.fyrde.fyrandroid.LauncherActivity
import kotlin.math.abs

/**
 * Optional, zero-CPU top-edge downward swipe interceptor.
 *
 * When enabled in Android Accessibility Settings, places an invisible 18dp gesture strip
 * along the top edge of the screen (`TYPE_ACCESSIBILITY_OVERLAY`) so downward swipes from the
 * top of the screen immediately summon the Fyr Quick Settings menu.
 */
class TopEdgeGestureService : AccessibilityService() {

    private var windowManager: WindowManager? = null
    private var topStripView: View? = null
    private var downX = 0f
    private var downY = 0f
    private var triggered = false

    @SuppressLint("ClickableViewAccessibility")
    override fun onServiceConnected() {
        super.onServiceConnected()
        val wm = getSystemService(WINDOW_SERVICE) as? WindowManager ?: return
        windowManager = wm

        val density = resources.displayMetrics.density
        val stripHeight = (18f * density).toInt().coerceAtLeast(24)
        val swipeThreshold = 26f * density

        val strip = View(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        downX = event.rawX
                        downY = event.rawY
                        triggered = false
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dy = event.rawY - downY
                        val dx = event.rawX - downX
                        if (!triggered && dy > swipeThreshold && dy > abs(dx)) {
                            triggered = true
                            openFyrQuickSettings()
                        }
                        true
                    }
                    else -> false
                }
            }
        }

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            stripHeight,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        }

        try {
            wm.addView(strip, lp)
            topStripView = strip
        } catch (_: Exception) {
        }
    }

    private fun openFyrQuickSettings() {
        val intent = Intent(this, LauncherActivity::class.java).apply {
            action = LauncherActivity.ACTION_OPEN_QUICK_SETTINGS
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No event processing needed — zero background CPU overhead.
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        topStripView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
            }
        }
        topStripView = null
        super.onDestroy()
    }
}
