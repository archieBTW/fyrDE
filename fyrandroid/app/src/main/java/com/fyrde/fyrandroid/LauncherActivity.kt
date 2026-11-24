package com.fyrde.fyrandroid

import android.app.Activity
import android.app.AlertDialog
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
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.PopupMenu
import android.widget.Toast
import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.model.AppRepository
import com.fyrde.fyrandroid.model.HomeItem
import com.fyrde.fyrandroid.theme.FyrThemeManager
import com.fyrde.fyrandroid.ui.FyrFolderOverlayView
import com.fyrde.fyrandroid.ui.FyrHomeGridView
import com.fyrde.fyrandroid.ui.FyrQuickSettingsSheet
import com.fyrde.fyrandroid.ui.FyrSearchOverlayView

/**
 * Main FyrDE Android Launcher Activity (`HOME` & `DEFAULT` intent category).
 */
class LauncherActivity : Activity() {

    companion object {
        const val ACTION_OPEN_QUICK_SETTINGS = "com.fyrde.fyrandroid.ACTION_OPEN_QUICK_SETTINGS"
    }

    private lateinit var repo: AppRepository
    private lateinit var homeGridView: FyrHomeGridView
    private lateinit var folderOverlay: FyrFolderOverlayView
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
            folderOverlay.applyTheme()
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
            onOpenFolder = { folder -> openFolder(folder) },
            onAppLongPressMenu = { anchor, app -> showAppContextMenu(anchor, app) },
            onFolderLongPressMenu = { anchor, folder -> showFolderContextMenu(anchor, folder) },
            onMoveHomeItem = { fromIdx, toIdx -> repo.moveHomeItem(fromIdx, toIdx) },
            onGroupHomeItems = { srcIdx, dstIdx -> repo.groupHomeItems(srcIdx, dstIdx) },
            onSwipeUpSearch = { openSearchDrawer() },
            onSwipeDownQuickSettings = { openQuickSettings() }
        )

        folderOverlay = FyrFolderOverlayView(
            context = this,
            repo = repo,
            onLaunchApp = { app -> launchApp(app) },
            onAppActionMenu = { anchor, app -> showAppContextMenu(anchor, app) },
            onVisibilityChanged = { updateHomeBlur() }
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

        val matchParent = {
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        root.addView(homeGridView, matchParent())
        root.addView(folderOverlay, matchParent())
        root.addView(searchOverlay, matchParent())
        root.addView(quickSettingsSheet, matchParent())

        setContentView(root)

        repo.start { allApps, homeItems, dockApps ->
            homeGridView.bindLayout(homeItems, dockApps)
            searchOverlay.bindApps(allApps)
            folderOverlay.refreshIfOpen()
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
            if (folderOverlay.isOpen) folderOverlay.close()
            openQuickSettings()
            return
        }
        when {
            quickSettingsSheet.isOpen -> quickSettingsSheet.close()
            searchOverlay.isOpen -> searchOverlay.close()
            folderOverlay.isOpen -> folderOverlay.close()
            else -> homeGridView.setCurrentPage(0, animate = true)
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
            folderOverlay.isOpen -> folderOverlay.close()
            else -> homeGridView.setCurrentPage(0, animate = true)
        }
    }

    private fun openFolder(folder: HomeItem.Folder) {
        if (searchOverlay.isOpen) searchOverlay.close()
        if (quickSettingsSheet.isOpen) quickSettingsSheet.close()
        folderOverlay.open(folder)
    }

    private fun openSearchDrawer() {
        if (quickSettingsSheet.isOpen) quickSettingsSheet.close()
        if (folderOverlay.isOpen) folderOverlay.close()
        searchOverlay.openAndFocus()
    }

    private fun openQuickSettings() {
        if (searchOverlay.isOpen) searchOverlay.close()
        if (folderOverlay.isOpen) folderOverlay.close()
        quickSettingsSheet.open()
    }

    private fun updateHomeBlur() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val shouldBlur = searchOverlay.isOpen || quickSettingsSheet.isOpen || folderOverlay.isOpen
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

    private fun showFolderContextMenu(anchor: View, folder: HomeItem.Folder) {
        val popup = PopupMenu(this, anchor)
        popup.menu.add(0, 1, 0, "Open Folder")
        popup.menu.add(0, 2, 1, "Rename Folder")
        popup.menu.add(0, 3, 2, "Ungroup Folder")

        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> {
                    openFolder(folder)
                    true
                }
                2 -> {
                    showRenameFolderDialog(folder)
                    true
                }
                3 -> {
                    repo.ungroupFolder(folder.id)
                    true
                }
                else -> false
            }
        }
        popup.show()
    }

    private fun showRenameFolderDialog(folder: HomeItem.Folder) {
        val input = EditText(this).apply {
            setText(folder.name)
            setSelection(folder.name.length)
        }
        AlertDialog.Builder(this)
            .setTitle("Rename Folder")
            .setView(input)
            .setPositiveButton("Save") { _, _ ->
                repo.renameFolder(folder.id, input.text.toString())
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showAppContextMenu(anchor: View, app: AppEntry) {
        val popup = PopupMenu(this, anchor)
        val pinned = repo.isPinnedToDock(app)
        popup.menu.add(0, 1, 0, if (pinned) "Unpin from Dock" else "Pin to Dock")

        val existingFolders = repo.homeItems.filterIsInstance<HomeItem.Folder>()
        val isStandaloneOnHome = repo.homeItems.any {
            it is HomeItem.App && it.entry.componentKey == app.componentKey
        }
        if (isStandaloneOnHome && existingFolders.isNotEmpty()) {
            val sub = popup.menu.addSubMenu(0, 5, 1, "Add to Folder")
            existingFolders.forEachIndexed { idx, folder ->
                sub.add(1, 100 + idx, idx, folder.name)
            }
        }

        popup.menu.add(0, 2, 2, "App Info")
        if (!app.isSystemApp) {
            popup.menu.add(0, 3, 3, "Uninstall")
        }
        popup.menu.add(0, 4, 4, "Fyr Quick Settings")

        popup.setOnMenuItemClickListener { item ->
            if (item.groupId == 1 && item.itemId >= 100) {
                val folder = existingFolders.getOrNull(item.itemId - 100)
                if (folder != null) {
                    repo.addAppToFolder(app.componentKey, folder.id)
                }
                return@setOnMenuItemClickListener true
            }
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
