package com.fyrde.fyrandroid.theme

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Lightweight, zero-polling Fyr theme manager mirroring `packages/fyr_core/lib/fyr_theme.dart`.
 * Persists Light/Dark mode and Accent Color in SharedPreferences and notifies active views immediately.
 */
object FyrThemeManager {
    private const val PREFS_NAME = "fyr_launcher_prefs"
    private const val KEY_DARK_MODE = "is_dark_mode"
    private const val KEY_ACCENT_COLOR = "accent_color"

    const val DEFAULT_ACCENT: Int = 0xFFE040FB.toInt() // Fyr Purple

    data class AccentPreset(val name: String, val color: Int)

    val ACCENT_PRESETS: List<AccentPreset> = listOf(
        AccentPreset("Fyr Purple", 0xFFE040FB.toInt()),
        AccentPreset("Deep Violet", 0xFF7C4DFF.toInt()),
        AccentPreset("Fyr Cyan", 0xFF40C4FF.toInt()),
        AccentPreset("Emerald", 0xFF00E676.toInt()),
        AccentPreset("Amber", 0xFFFFD740.toInt()),
        AccentPreset("Coral", 0xFFFF5252.toInt()),
        AccentPreset("Neon Rose", 0xFFFF4081.toInt()),
        AccentPreset("Indigo", 0xFF536DFE.toInt())
    )

    private var prefs: SharedPreferences? = null
    private val listeners = CopyOnWriteArraySet<() -> Unit>()

    var isDark: Boolean = true
        private set

    var accentColor: Int = DEFAULT_ACCENT
        private set

    fun init(context: Context) {
        if (prefs != null) return
        val sp = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs = sp
        isDark = sp.getBoolean(KEY_DARK_MODE, true)
        accentColor = sp.getInt(KEY_ACCENT_COLOR, DEFAULT_ACCENT)
    }

    fun setDarkMode(dark: Boolean) {
        if (isDark == dark) return
        isDark = dark
        prefs?.edit()?.putBoolean(KEY_DARK_MODE, dark)?.apply()
        notifyListeners()
    }

    fun toggleThemeMode() {
        setDarkMode(!isDark)
    }

    fun setAccent(color: Int) {
        if (accentColor == color) return
        accentColor = color
        prefs?.edit()?.putInt(KEY_ACCENT_COLOR, color)?.apply()
        notifyListeners()
    }

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    private fun notifyListeners() {
        for (l in listeners) {
            l.invoke()
        }
    }

    // FyrDE semantic tokens matching `fyr_theme.dart`
    val bgColor: Int
        get() = if (isDark) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()

    val panelBgColor: Int
        get() = if (isDark) 0xD92A282C.toInt() else 0xEBFFFFFF.toInt()

    val searchBackdropColor: Int
        get() = if (isDark) 0xD8141318.toInt() else 0xE6F4F4F8.toInt()

    val surfaceColor: Int
        get() = if (isDark) 0xFF1A1A1A.toInt() else 0xFFFFFFFF.toInt()

    val cardColor: Int
        get() = if (isDark) 0x16FFFFFF else 0x12000000

    val hoverColor: Int
        get() = if (isDark) 0x24FFFFFF else 0x14000000

    val dividerColor: Int
        get() = if (isDark) 0x22FFFFFF else 0x18000000

    val textColor: Int
        get() = if (isDark) 0xFFFFFFFF.toInt() else 0xDE000000.toInt()

    val textColorMuted: Int
        get() = if (isDark) 0xB3FFFFFF.toInt() else 0x8A000000.toInt()

    fun accentWithAlpha(alphaFraction: Float): Int {
        val a = (alphaFraction.coerceIn(0f, 1f) * 255f).toInt()
        return Color.argb(
            a,
            Color.red(accentColor),
            Color.green(accentColor),
            Color.blue(accentColor)
        )
    }
}
