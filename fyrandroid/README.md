# fyrAndroid — Native Kotlin Android Launcher with the FyrDE Aesthetic

`fyrAndroid` is an ultra-lightweight, memory- and CPU-friendly native Kotlin Android launcher that brings the FyrDE desktop aesthetic (`fyrsearch`, `fyrtaskbar` Quick Settings, and `FyrTheme`) to Android.

## Key Features

1. **Paged Home Grid + Frosted Dock (`FyrHomeGridView.kt`)**
   - Horizontal paged `4×5` squircle app grid with page indicator dots, Fyr clock/date header, and a translucent frosted-glass 4-app bottom Dock (`28dp` corner radius).
   - Long-press any app icon to pin/unpin from the Dock, open App Info, or uninstall.

2. **Swipe-Up `fyrsearch` Drawer with Immediate Autofocus (`FyrSearchOverlayView.kt`)**
   - Swiping upward anywhere on the home screen (or tapping the `⌕ Search` pill) slides up the custom FyrSearch overlay and immediately focuses the pill-shaped search bar and opens the soft keyboard.
   - Includes `FyrSearchEvaluator.kt` for fuzzy app filtering, inline math/calculator evaluation (`24 * 7`, `1920 / 16 * 9`, `sqrt(144)`), quick theme commands (`:dark`, `:light`, `:accent cyan`), and one-tap web search fallback.

3. **Swipe-Down Fyr Quick Settings + Top-Edge Interception (`FyrQuickSettingsSheet.kt` & `TopEdgeGestureService.kt`)**
   - Swiping downward anywhere on the home screen opens the Fyr Quick Settings menu styled after `fyrtaskbar`:
     - `2×4` circular frosted `QuickToggle` buttons: **Wi-Fi**, **Bluetooth**, **Airplane**, **Flashlight (Torch)**, **Auto-Rotate**, **Do Not Disturb**, **Dark/Light Mode**, and **Hotspot**.
     - **Fyr Media Controls Card** (`⏮`, `⏯`, `⏭`).
     - **Brightness** and **Volume** `SliderRow` controls with audio output switcher (`›`).
   - Optional **`TopEdgeGestureService`** (`AccessibilityService` with an invisible `18dp` top-edge overlay strip) intercepts downward swipes from the very top edge of the screen so top-bar downward swipes summon Fyr Quick Settings directly.

4. **Low-Memory & CPU-Friendly Architecture (`AppRepository.kt`)**
   - Pure native Android Views/Canvas (no heavy Compose runtime or third-party bloat).
   - Single background worker thread for `PackageManager` indexing and one-time squircle icon bitmap rasterization.
   - Strict memory-capped `LruCache<String, Bitmap>` that automatically trims or evicts cached bitmaps on `Activity.onTrimMemory`.
   - Zero background polling loops (clock updates strictly on Android's `ACTION_TIME_TICK` while the launcher is visible; app list updates strictly on `ACTION_PACKAGE_*` broadcasts).

5. **Live Light/Dark Mode & Fyr Accent Customization (`FyrThemeManager.kt`)**
   - Instant live switching between Dark Mode and Light Mode plus 8 signature FyrDE accent colors (`Fyr Purple #E040FB`, `Deep Violet #7C4DFF`, `Fyr Cyan #40C4FF`, `Emerald #00E676`, `Amber #FFD740`, `Coral #FF5252`, `Neon Rose #FF4081`, `Indigo #536DFE`).
