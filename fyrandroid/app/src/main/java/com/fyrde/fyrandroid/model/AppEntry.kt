package com.fyrde.fyrandroid.model

import android.content.ComponentName
import android.content.Intent

/**
 * Lightweight immutable model representing a launchable Android application activity
 * or a pinned home screen shortcut (such as Firefox web/PWA shortcuts).
 */
data class AppEntry(
    val label: String,
    val packageName: String,
    val activityName: String,
    val isSystemApp: Boolean = false,
    val launchCount: Int = 0,
    val shortcutId: String? = null
) {
    val isShortcut: Boolean
        get() = shortcutId != null

    val componentKey: String
        get() = if (shortcutId != null) {
            "shortcut:$packageName/$shortcutId"
        } else {
            "$packageName/$activityName"
        }

    fun toLaunchIntent(): Intent = Intent(Intent.ACTION_MAIN).apply {
        addCategory(Intent.CATEGORY_LAUNCHER)
        component = ComponentName(packageName, activityName)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
    }
}
