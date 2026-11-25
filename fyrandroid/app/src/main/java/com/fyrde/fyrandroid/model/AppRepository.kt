package com.fyrde.fyrandroid.model

import android.content.BroadcastReceiver
import android.content.ComponentCallbacks2
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.LauncherApps
import android.content.pm.ShortcutInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserHandle
import android.os.UserManager
import android.util.LruCache
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Low-memory, CPU-friendly repository for installed apps, pinned shortcuts (e.g. Firefox web/PWA
 * shortcuts), dock pins, and squircle icon bitmaps.
 *
 * - Uses a background worker for PackageManager/LauncherApps queries and a 2-thread icon pool.
 * - Pre-warms and caches pre-clipped squircle Bitmaps in a memory-bounded [LruCache].
 * - Responds to critical [onTrimMemory] signals without evicting cached icons on normal app switches.
 */
class AppRepository(private val context: Context) {
    private val prefs = context.getSharedPreferences("fyr_apps_prefs", Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val launcherApps =
        context.getSystemService(Context.LAUNCHER_APPS_SERVICE) as? LauncherApps

    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "fyr-app-loader").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val iconWorker = Executors.newFixedThreadPool(2) { r ->
        Thread(r, "fyr-icon-loader").apply { priority = Thread.NORM_PRIORITY - 1 }
    }

    private val iconSizePx: Int =
        (56f * context.resources.displayMetrics.density).toInt().coerceIn(72, 168)

    private val iconCache: LruCache<String, Bitmap> = object : LruCache<String, Bitmap>(
        ((Runtime.getRuntime().maxMemory() / 1024L) / 8L).toInt().coerceIn(4096, 32768)
    ) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
    }

    private val inFlightIconCallbacks = HashMap<String, MutableList<(Bitmap) -> Unit>>()
    private val shortcutInfoMap = ConcurrentHashMap<String, ShortcutInfo>()

    @Volatile
    var allApps: List<AppEntry> = emptyList()
        private set

    @Volatile
    var homeItems: List<HomeItem> = emptyList()
        private set

    @Volatile
    var dockApps: List<AppEntry> = emptyList()
        private set

    private var onAppsUpdated: ((List<AppEntry>, List<HomeItem>, List<AppEntry>) -> Unit)? = null
    private var receiverRegistered = false
    private var launcherCallbackRegistered = false

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            reloadAppsAsync()
        }
    }

    private val launcherAppsCallback = object : LauncherApps.Callback() {
        override fun onPackageRemoved(packageName: String, user: UserHandle) {
            reloadAppsAsync()
        }

        override fun onPackageAdded(packageName: String, user: UserHandle) {
            reloadAppsAsync()
        }

        override fun onPackageChanged(packageName: String, user: UserHandle) {
            reloadAppsAsync()
        }

        override fun onPackagesAvailable(
            packageNames: Array<out String>,
            user: UserHandle,
            replacing: Boolean
        ) {
            reloadAppsAsync()
        }

        override fun onPackagesUnavailable(
            packageNames: Array<out String>,
            user: UserHandle,
            replacing: Boolean
        ) {
            reloadAppsAsync()
        }

        override fun onShortcutsChanged(
            packageName: String,
            shortcuts: MutableList<ShortcutInfo>,
            user: UserHandle
        ) {
            reloadAppsAsync()
        }
    }

    fun start(listener: (List<AppEntry>, List<HomeItem>, List<AppEntry>) -> Unit) {
        onAppsUpdated = listener
        if (!receiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_PACKAGE_ADDED)
                addAction(Intent.ACTION_PACKAGE_REMOVED)
                addAction(Intent.ACTION_PACKAGE_CHANGED)
                addDataScheme("package")
            }
            context.registerReceiver(packageReceiver, filter)
            receiverRegistered = true
        }
        if (!launcherCallbackRegistered && launcherApps != null) {
            try {
                launcherApps.registerCallback(launcherAppsCallback, mainHandler)
                launcherCallbackRegistered = true
            } catch (_: Exception) {
            }
        }
        reloadAppsAsync()
    }

    fun stop() {
        onAppsUpdated = null
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(packageReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
        if (launcherCallbackRegistered && launcherApps != null) {
            try {
                launcherApps.unregisterCallback(launcherAppsCallback)
            } catch (_: Exception) {
            }
            launcherCallbackRegistered = false
        }
    }

    private fun getHiddenShortcuts(): Set<String> {
        val raw = prefs.getString("hidden_shortcuts", null) ?: return emptySet()
        return raw.split("\n").filter { it.isNotEmpty() }.toSet()
    }

    private fun saveHiddenShortcuts(keys: Set<String>) {
        prefs.edit().putString("hidden_shortcuts", keys.joinToString("\n")).apply()
    }

    fun reloadAppsAsync() {
        worker.execute {
            val pm = context.packageManager
            val queryIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolveInfos = pm.queryIntentActivities(queryIntent, 0)
            val selfPkg = context.packageName
            val entries = ArrayList<AppEntry>(resolveInfos.size + 16)

            for (ri in resolveInfos) {
                val ai = ri.activityInfo ?: continue
                if (ai.packageName == selfPkg) continue
                val label = ri.loadLabel(pm)?.toString()?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: ai.packageName
                val isSys = (ai.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val key = "${ai.packageName}/${ai.name}"
                val count = prefs.getInt("launches_$key", 0)
                entries.add(
                    AppEntry(
                        label = label,
                        packageName = ai.packageName,
                        activityName = ai.name,
                        isSystemApp = isSys,
                        launchCount = count
                    )
                )
            }

            // Include pinned shortcuts (e.g. Firefox / Chrome / PWA home screen shortcuts)
            val newShortcutsMap = HashMap<String, ShortcutInfo>()
            val la = launcherApps
            if (la != null && la.hasShortcutHostPermission()) {
                val hiddenShortcuts = getHiddenShortcuts()
                val userManager = context.getSystemService(Context.USER_SERVICE) as? UserManager
                val profiles = userManager?.userProfiles ?: listOf(Process.myUserHandle())
                val queryFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED or
                        LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED_BY_ANY_LAUNCHER
                } else {
                    LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED
                }
                val query = LauncherApps.ShortcutQuery().setQueryFlags(queryFlags)
                val seenShortcutKeys = HashSet<String>()
                for (profile in profiles) {
                    val shortcuts = try {
                        la.getShortcuts(query, profile)
                    } catch (_: Exception) {
                        null
                    } ?: continue
                    for (info in shortcuts) {
                        if (!info.isEnabled) continue
                        val key = "shortcut:${info.`package`}/${info.id}"
                        if (key in hiddenShortcuts || !seenShortcutKeys.add(key)) continue
                        newShortcutsMap[key] = info
                        val label = info.shortLabel?.toString()?.trim()?.takeUnless { it.isEmpty() }
                            ?: info.longLabel?.toString()?.trim()?.takeUnless { it.isEmpty() }
                            ?: info.`package`
                        val count = prefs.getInt("launches_$key", 0)
                        entries.add(
                            AppEntry(
                                label = label,
                                packageName = info.`package`,
                                activityName = info.activity?.className ?: "",
                                isSystemApp = false,
                                launchCount = count,
                                shortcutId = info.id
                            )
                        )
                    }
                }
            }
            shortcutInfoMap.clear()
            shortcutInfoMap.putAll(newShortcutsMap)

            entries.sortWith(compareBy { it.label.lowercase(Locale.getDefault()) })
            val nextAllApps = entries
            val nextDockApps = resolveDockApps(nextAllApps)
            val nextHomeItems = HomeLayoutCodec.reconcile(
                prefs.getString("home_layout_v1", null),
                nextAllApps,
                nextDockApps
            )

            allApps = nextAllApps
            dockApps = nextDockApps
            homeItems = nextHomeItems

            mainHandler.post {
                onAppsUpdated?.invoke(nextAllApps, nextHomeItems, nextDockApps)
            }

            prewarmIcons(nextDockApps, nextHomeItems)
        }
    }

    private fun prewarmIcons(dock: List<AppEntry>, items: List<HomeItem>) {
        val ordered = LinkedHashSet<AppEntry>(dock.size + items.size)
        ordered.addAll(dock)
        for (item in items) {
            when (item) {
                is HomeItem.App -> ordered.add(item.entry)
                is HomeItem.Folder -> ordered.addAll(item.apps)
            }
        }
        for (app in ordered) {
            if (iconCache.get(app.componentKey) != null) continue
            iconWorker.execute {
                if (iconCache.get(app.componentKey) != null) return@execute
                val bmp = rasterizeSquircleIcon(app)
                if (bmp != null) {
                    iconCache.put(app.componentKey, bmp)
                }
            }
        }
    }

    fun onShortcutPinned(info: ShortcutInfo) {
        val key = "shortcut:${info.`package`}/${info.id}"
        val hidden = getHiddenShortcuts().toMutableSet()
        if (hidden.remove(key)) {
            saveHiddenShortcuts(hidden)
        }
        shortcutInfoMap[key] = info
        iconCache.remove(key)
        reloadAppsAsync()
    }

    fun removeShortcut(app: AppEntry) {
        if (!app.isShortcut) return
        val key = app.componentKey
        val hidden = getHiddenShortcuts().toMutableSet()
        hidden.add(key)
        saveHiddenShortcuts(hidden)

        // Unpin from dock if pinned there
        if (isPinnedToDock(app)) {
            val current = dockApps.map { it.componentKey }.toMutableList()
            current.remove(key)
            prefs.edit().putString("dock_pins", current.joinToString("|")).apply()
        }

        // Best-effort unpin from this launcher in the OS
        val info = shortcutInfoMap.remove(key)
        iconCache.remove(key)
        val la = launcherApps
        if (info != null && la != null && la.hasShortcutHostPermission()) {
            worker.execute {
                try {
                    val query = LauncherApps.ShortcutQuery()
                        .setPackage(info.`package`)
                        .setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED)
                    val remaining = la.getShortcuts(query, info.userHandle)
                        ?.map { it.id }
                        ?.filter { it != info.id }
                        ?: emptyList()
                    la.pinShortcuts(info.`package`, remaining, info.userHandle)
                } catch (_: Exception) {
                }
            }
        }
        reloadAppsAsync()
    }

    fun launchShortcut(app: AppEntry): Boolean {
        val la = launcherApps ?: return false
        val info = shortcutInfoMap[app.componentKey]
        return try {
            if (info != null) {
                la.startShortcut(info, null, null)
                true
            } else if (app.shortcutId != null) {
                la.startShortcut(app.packageName, app.shortcutId, null, null, Process.myUserHandle())
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun resolveDockApps(apps: List<AppEntry>): List<AppEntry> {
        if (apps.isEmpty()) return emptyList()
        val savedRaw = prefs.getString("dock_pins", null)
        if (!savedRaw.isNullOrBlank()) {
            val byKey = apps.associateBy { it.componentKey }
            val pinned = savedRaw.split("|").mapNotNull { byKey[it] }
            if (pinned.isNotEmpty()) return pinned.take(4)
        }

        // Default bottom dock: Phone, Messages, Browser, Settings/Camera (prefer real apps over shortcuts)
        val nonShortcuts = apps.filter { !it.isShortcut }.ifEmpty { apps }
        val keywords = listOf(
            listOf("phone", "dialer", "call"),
            listOf("messages", "messaging", "sms", "chat"),
            listOf("browser", "chrome", "firefox", "brave", "web"),
            listOf("camera", "photos", "settings")
        )
        val chosen = mutableListOf<AppEntry>()
        for (group in keywords) {
            val match = nonShortcuts.firstOrNull { app ->
                app !in chosen && group.any { kw ->
                    app.label.lowercase(Locale.getDefault()).contains(kw) ||
                        app.packageName.lowercase(Locale.getDefault()).contains(kw)
                }
            }
            if (match != null) chosen.add(match)
        }
        for (fallback in nonShortcuts) {
            if (chosen.size >= 4) break
            if (fallback !in chosen) chosen.add(fallback)
        }
        return chosen.take(4)
    }

    fun isPinnedToDock(app: AppEntry): Boolean =
        dockApps.any { it.componentKey == app.componentKey }

    fun toggleDockPin(app: AppEntry): Boolean {
        val current = dockApps.map { it.componentKey }.toMutableList()
        val added: Boolean
        if (current.contains(app.componentKey)) {
            current.remove(app.componentKey)
            added = false
        } else {
            if (current.size >= 4) current.removeAt(current.lastIndex)
            current.add(app.componentKey)
            added = true
        }
        prefs.edit().putString("dock_pins", current.joinToString("|")).apply()
        dockApps = resolveDockApps(allApps)
        homeItems = HomeLayoutCodec.reconcile(
            prefs.getString("home_layout_v1", null),
            allApps,
            dockApps
        )
        persistHomeLayout(homeItems)
        onAppsUpdated?.invoke(allApps, homeItems, dockApps)
        return added
    }

    private fun persistHomeLayout(items: List<HomeItem>) {
        prefs.edit().putString("home_layout_v1", HomeLayoutCodec.serialize(items)).apply()
    }

    private fun commitHomeLayout(next: List<HomeItem>) {
        homeItems = next
        persistHomeLayout(next)
        onAppsUpdated?.invoke(allApps, homeItems, dockApps)
    }

    fun moveHomeItem(fromIndex: Int, toIndex: Int) {
        val next = HomeLayoutCodec.moveItem(homeItems, fromIndex, toIndex)
        if (next != homeItems) commitHomeLayout(next)
    }

    fun groupHomeItems(sourceIndex: Int, targetIndex: Int) {
        val next = HomeLayoutCodec.groupItems(homeItems, sourceIndex, targetIndex)
        if (next != homeItems) commitHomeLayout(next)
    }

    fun addAppToFolder(appKey: String, folderId: String) {
        val srcIdx = homeItems.indexOfFirst { it is HomeItem.App && it.entry.componentKey == appKey }
        val dstIdx = homeItems.indexOfFirst { it is HomeItem.Folder && it.id == folderId }
        if (srcIdx >= 0 && dstIdx >= 0 && srcIdx != dstIdx) {
            groupHomeItems(srcIdx, dstIdx)
        }
    }

    fun renameFolder(folderId: String, newName: String) {
        val next = HomeLayoutCodec.renameFolder(homeItems, folderId, newName)
        if (next != homeItems) commitHomeLayout(next)
    }

    fun removeAppFromFolder(folderId: String, appKey: String) {
        val next = HomeLayoutCodec.removeAppFromFolder(homeItems, folderId, appKey)
        if (next != homeItems) commitHomeLayout(next)
    }

    fun ungroupFolder(folderId: String) {
        val next = HomeLayoutCodec.ungroupFolder(homeItems, folderId)
        if (next != homeItems) commitHomeLayout(next)
    }

    fun moveAppInFolder(folderId: String, fromIdx: Int, toIdx: Int) {
        val next = HomeLayoutCodec.moveAppInFolder(homeItems, folderId, fromIdx, toIdx)
        if (next != homeItems) commitHomeLayout(next)
    }

    fun getFolderById(folderId: String): HomeItem.Folder? =
        homeItems.firstOrNull { it is HomeItem.Folder && it.id == folderId } as? HomeItem.Folder

    fun recordLaunch(app: AppEntry) {
        val key = "launches_${app.componentKey}"
        val next = prefs.getInt(key, 0) + 1
        prefs.edit().putInt(key, next).apply()
    }

    fun getCachedIcon(app: AppEntry): Bitmap? = iconCache.get(app.componentKey)

    fun loadIconAsync(app: AppEntry, onLoaded: (Bitmap) -> Unit) {
        val key = app.componentKey
        val cached = iconCache.get(key)
        if (cached != null) {
            onLoaded(cached)
            return
        }
        val shouldStart: Boolean
        synchronized(inFlightIconCallbacks) {
            val existing = inFlightIconCallbacks[key]
            if (existing != null) {
                existing.add(onLoaded)
                shouldStart = false
            } else {
                inFlightIconCallbacks[key] = mutableListOf(onLoaded)
                shouldStart = true
            }
        }
        if (!shouldStart) return

        iconWorker.execute {
            val bmp = iconCache.get(key) ?: rasterizeSquircleIcon(app)?.also {
                iconCache.put(key, it)
            }
            val callbacks = synchronized(inFlightIconCallbacks) {
                inFlightIconCallbacks.remove(key)
            } ?: return@execute
            if (bmp != null) {
                mainHandler.post {
                    for (cb in callbacks) {
                        cb(bmp)
                    }
                }
            }
        }
    }

    private fun rasterizeSquircleIcon(app: AppEntry): Bitmap? {
        return try {
            val pm = context.packageManager
            val drawable: Drawable = if (app.isShortcut) {
                val info = shortcutInfoMap[app.componentKey]
                val densityDpi = context.resources.displayMetrics.densityDpi
                (if (info != null) {
                    launcherApps?.getShortcutIconDrawable(info, densityDpi)
                        ?: launcherApps?.getShortcutBadgedIconDrawable(info, densityDpi)
                } else {
                    null
                }) ?: pm.getApplicationIcon(app.packageName)
            } else {
                pm.getActivityIcon(
                    ComponentName(app.packageName, app.activityName)
                )
            }
            val size = iconSizePx
            val raw = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val rawCanvas = Canvas(raw)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(rawCanvas)

            val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val radius = size * 0.225f
            val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
            val clipPath = Path().apply {
                addRoundRect(rect, radius, radius, Path.Direction.CW)
            }
            canvas.drawPath(clipPath, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(raw, 0f, 0f, paint)
            raw.recycle()
            output
        } catch (_: Exception) {
            null
        }
    }

    fun trimMemory(level: Int) {
        when (level) {
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
                iconCache.trimToSize(iconCache.maxSize() / 4)
            }
            ComponentCallbacks2.TRIM_MEMORY_MODERATE -> {
                iconCache.trimToSize(iconCache.maxSize() / 2)
            }
        }
    }
}
