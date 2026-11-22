package com.fyrde.fyrandroid

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.RenderEffect
import android.graphics.Shader
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.FrameLayout
import android.widget.PopupMenu
import android.widget.Toast
import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.model.AppRepository
import com.fyrde.fyrandroid.theme.FyrThemeManager
import com.fyrde.fyrandroid.ui.FyrQuickSettingsSheet
import com.fyrde.fyrandroid.ui.FyrSearchOverlayView
import com.fyrde.fyrandroid.ui.FyrHomeGridView

/**
 * Main FyrDE Android Launcher Activity (`HOME` & `DEFAULT` intent category).
 *
 * Designed for ultra-low memory and CPU consumption:
 * - Zero polling timers (clock updates strictly on Android's `ACTION_TIME_TICK` while visible).
 * - Hardware-accelerated native View hierarchy with pre-clipped squircle icon bitmaps.
 * - Upward swipe -> FyrSearch drawer with immediate autofocus & soft keyboard.
 * - Downward swipe (or top-edge swipe via [com.fyrde.fyrandroid.service.TopEdgeGestureService])
 *   -> Fyr Quick Settings menu.
 */
class LauncherActivity : Activity() {

    companion object {
        const val ACTION_OPEN_QUICK_SETTINGS = "com.fyrde.fyrandroid.ACTION_OPEN_QUICK_SETTINGS"
    }

    private lateinit var repo: AppRepository
    private lateinit var homeGridView: FyrHomeGridView
    private lateinit var searchOverlay: FyrSearchOverlayView
    private lateinit var quickSettingsSheet: FyrQuickSettingsSheet

    private var timeTickRegistered = false
    private val timeTickReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            homeGridView.refreshClock()
        }
    }

    private val themeListener: () -> Unit = {
        runOnUiThread {
            homeGridView.applyTheme()
            searchOverlay.applyTheme()
            quickSettingsSheet.applyTheme()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FyrThemeManager.init(this)
        FyrThemeManager.addListener(themeListener)

        repo = AppRepository(this)

        val root = FrameLayout(this)

        homeGridView = FyrHomeGridView(
            context = this,
            repo = repo,
            onLaunchApp = { app -> launchApp(app) },
            onAppLongPressMenu = { anchor, app -> showAppContextMenu(anchor, app) },
            onSwipeUpSearch = { openSearchDrawer() },
            onSwipeDownQuickSettings = { openQuickSettings() }
        )

        searchOverlay = FyrSearchOverlayView(
            context = this,
            repo = repo,
            onLaunchApp = { app -> launchApp(app) },
            onAppLongPress = { anchor, app -> showAppContextMenu(anchor, app) },
            onThemeChanged = { themeListener() },
            onVisibilityChanged = { updateHomeBlur() }
        )

        quickSettingsSheet = FyrQuickSettingsSheet(
            context = this,
            onThemeChanged = { themeListener() },
            onAdjustWindowBrightness = { brightness ->
                val lp = window.attributes
                lp.screenBrightness = brightness.coerceIn(0.05f, 1.0f)
                window.attributes = lp
            },
            onVisibilityChanged = { updateHomeBlur() }
        )

        root.addView(
            homeGridView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        root.addView(
            searchOverlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        root.addView(
            quickSettingsSheet,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        setContentView(root)

        repo.start { allApps, dockApps ->
            homeGridView.bindApps(allApps, dockApps)
            searchOverlay.bindApps(allApps)
        }

        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent?.action == ACTION_OPEN_QUICK_SETTINGS) {
            if (searchOverlay.isOpen) searchOverlay.close()
            openQuickSettings()
            return
        }
        // Pressing Home closes open drawers or returns to the first home page
        when {
            quickSettingsSheet.isOpen -> quickSettingsSheet.close()
            searchOverlay.isOpen -> searchOverlay.close()
            else -> homeGridView.setCurrentPage(0)
        }
    }

    override fun onResume() {
        super.onResume()
        homeGridView.refreshClock()
        if (!timeTickRegistered) {
            registerReceiver(timeTickReceiver, IntentFilter(Intent.ACTION_TIME_TICK))
            timeTickRegistered = true
        }
    }

    override fun onPause() {
        if (timeTickRegistered) {
            try {
                unregisterReceiver(timeTickReceiver)
            } catch (_: Exception) {
            }
            timeTickRegistered = false
        }
        super.onPause()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        repo.trimMemory(level)
    }

    override fun onDestroy() {
        FyrThemeManager.removeListener(themeListener)
        repo.stop()
        super.onDestroy()
    }

    @Deprecated("Handled explicitly for Android launcher back button behavior")
    override fun onBackPressed() {
        when {
            quickSettingsSheet.isOpen -> quickSettingsSheet.close()
            searchOverlay.isOpen -> searchOverlay.close()
            else -> homeGridView.setCurrentPage(0)
        }
    }

    private fun openSearchDrawer() {
        if (quickSettingsSheet.isOpen) quickSettingsSheet.close()
        searchOverlay.openAndFocus()
    }

    private fun openQuickSettings() {
        if (searchOverlay.isOpen) searchOverlay.close()
        quickSettingsSheet.open()
    }

    private fun updateHomeBlur() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val shouldBlur = searchOverlay.isOpen || quickSettingsSheet.isOpen
            homeGridView.setRenderEffect(
                if (shouldBlur) RenderEffect.createBlurEffect(28f, 28f, Shader.TileMode.CLAMP)
                else null
            )
        }
    }

    private fun launchApp(app: AppEntry) {
        try {
            repo.recordLaunch(app)
            startActivity(app.toLaunchIntent())
        } catch (_: Exception) {
            Toast.makeText(this, "Unable to launch ${app.label}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun showAppContextMenu(anchor: View, app: AppEntry) {
        val popup = PopupMenu(this, anchor)
        val pinned = repo.isPinnedToDock(app)
        popup.menu.add(0, 1, 0, if (pinned) "Unpin from Dock" else "Pin to Dock")
        popup.menu.add(0, 2, 1, "App Info")
        if (!app.isSystemApp) {
            popup.menu.add(0, 3, 2, "Uninstall")
        }
        popup.menu.add(0, 4, 3, "Fyr Quick Settings & Theme")

        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> {
                    val nowPinned = repo.toggleDockPin(app)
                    Toast.makeText(
                        this,
                        if (nowPinned) "Pinned ${app.label} to Dock"
                        else "Unpinned ${app.label} from Dock",
                        Toast.LENGTH_SHORT
                    ).show()
                    true
                }
                2 -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:${app.packageName}")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                    )
                    true
                }
                3 -> {
                    startActivity(
                        Intent(
                            Intent.ACTION_DELETE,
                            Uri.parse("package:${app.packageName}")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                    )
                    true
                }
                4 -> {
                    openQuickSettings()
                    true
                }
                else -> false
            }
        }
        popup.show()
    }
}
