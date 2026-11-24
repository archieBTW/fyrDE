package com.fyrde.fyrandroid.model

/**
 * Represents a single tile on the Fyr home screen: either a standalone [App]
 * or a grouped [Folder] containing multiple apps.
 */
sealed class HomeItem {
    abstract val id: String
    abstract val label: String

    data class App(val entry: AppEntry) : HomeItem() {
        override val id: String get() = "app:${entry.componentKey}"
        override val label: String get() = entry.label
    }

    data class Folder(
        override val id: String,
        val name: String,
        val apps: List<AppEntry>
    ) : HomeItem() {
        override val label: String get() = name
    }
}

/**
 * Pure layout reconciliation, reordering, and folder grouping helpers
 * (platform-independent so they run identically on Android and JVM unit tests).
 */
object HomeLayoutCodec {

    private fun escape(s: String): String =
        s.replace("%", "%25").replace("\t", "%09").replace("\n", "%0A").replace("|", "%7C")

    private fun unescape(s: String): String {
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            if (s[i] == '%' && i + 2 < s.length) {
                val code = s.substring(i + 1, i + 3).toIntOrNull(16)
                if (code != null) {
                    out.append(code.toChar())
                    i += 3
                    continue
                }
            }
            out.append(s[i])
            i++
        }
        return out.toString()
    }

    fun serialize(items: List<HomeItem>): String {
        val sb = StringBuilder()
        for (item in items) {
            when (item) {
                is HomeItem.App -> {
                    sb.append("A\t").append(escape(item.entry.componentKey)).append('\n')
                }
                is HomeItem.Folder -> {
                    sb.append("F\t")
                        .append(escape(item.id)).append('\t')
                        .append(escape(item.name)).append('\t')
                        .append(item.apps.joinToString("|") { escape(it.componentKey) })
                        .append('\n')
                }
            }
        }
        return sb.toString()
    }

    /**
     * Reconciles a saved layout string against the current installed [allApps]
     * and pinned [dockApps]:
     * - Preserves custom ordering and folders
     * - Prunes uninstalled apps and dock-pinned apps
     * - Auto-dissolves folders that drop to 1 app
     * - Appends newly installed apps at the end
     */
    fun reconcile(
        savedRaw: String?,
        allApps: List<AppEntry>,
        dockApps: List<AppEntry>
    ): List<HomeItem> {
        val dockKeys = dockApps.map { it.componentKey }.toSet()
        val availableByKey = allApps
            .filter { it.componentKey !in dockKeys }
            .associateBy { it.componentKey }

        val placedKeys = HashSet<String>()
        val result = ArrayList<HomeItem>()

        if (!savedRaw.isNullOrBlank()) {
            val lines = savedRaw.split('\n')
            for ((idx, rawLine) in lines.withIndex()) {
                val line = rawLine.trimEnd('\r')
                if (line.isEmpty()) continue
                val parts = line.split('\t')
                when (parts.firstOrNull()) {
                    "A" -> {
                        if (parts.size < 2) continue
                        val key = unescape(parts[1])
                        val app = availableByKey[key]
                        if (app != null && placedKeys.add(key)) {
                            result.add(HomeItem.App(app))
                        }
                    }
                    "F" -> {
                        if (parts.size < 4) continue
                        val id = unescape(parts[1]).ifBlank { "folder_${System.nanoTime()}_$idx" }
                        val name = unescape(parts[2]).ifBlank { "Folder" }
                        val folderApps = ArrayList<AppEntry>()
                        for (rawKey in parts[3].split('|')) {
                            if (rawKey.isEmpty()) continue
                            val key = unescape(rawKey)
                            val app = availableByKey[key]
                            if (app != null && placedKeys.add(key)) {
                                folderApps.add(app)
                            }
                        }
                        when {
                            folderApps.size >= 2 -> result.add(HomeItem.Folder(id, name, folderApps))
                            folderApps.size == 1 -> result.add(HomeItem.App(folderApps[0]))
                        }
                    }
                }
            }
        }

        // Append any unplaced apps (newly installed or unpinned from dock)
        for (app in allApps) {
            if (app.componentKey !in dockKeys && placedKeys.add(app.componentKey)) {
                result.add(HomeItem.App(app))
            }
        }

        return result
    }

    fun moveItem(items: List<HomeItem>, fromIndex: Int, toIndex: Int): List<HomeItem> {
        if (fromIndex !in items.indices) return items
        val clampedTarget = toIndex.coerceIn(0, items.lastIndex)
        if (fromIndex == clampedTarget) return items
        val mutable = items.toMutableList()
        val moved = mutable.removeAt(fromIndex)
        mutable.add(clampedTarget, moved)
        return mutable
    }

    fun groupItems(
        items: List<HomeItem>,
        sourceIndex: Int,
        targetIndex: Int,
        newFolderId: String = "folder_${System.currentTimeMillis()}"
    ): List<HomeItem> {
        if (sourceIndex !in items.indices || targetIndex !in items.indices || sourceIndex == targetIndex) {
            return items
        }
        val source = items[sourceIndex]
        val target = items[targetIndex]

        val sourceApps = when (source) {
            is HomeItem.App -> listOf(source.entry)
            is HomeItem.Folder -> source.apps
        }
        val mergedFolder = when (target) {
            is HomeItem.App -> HomeItem.Folder(
                id = newFolderId,
                name = "Folder",
                apps = listOf(target.entry) + sourceApps
            )
            is HomeItem.Folder -> target.copy(
                apps = target.apps + sourceApps.filter { s ->
                    target.apps.none { it.componentKey == s.componentKey }
                }
            )
        }

        val mutable = items.toMutableList()
        mutable[targetIndex] = mergedFolder
        mutable.removeAt(sourceIndex)
        return mutable
    }

    fun renameFolder(items: List<HomeItem>, folderId: String, newName: String): List<HomeItem> {
        val cleaned = newName.trim().ifEmpty { "Folder" }
        return items.map { item ->
            if (item is HomeItem.Folder && item.id == folderId) item.copy(name = cleaned)
            else item
        }
    }

    fun removeAppFromFolder(items: List<HomeItem>, folderId: String, appKey: String): List<HomeItem> {
        val idx = items.indexOfFirst { it is HomeItem.Folder && it.id == folderId }
        if (idx < 0) return items
        val folder = items[idx] as HomeItem.Folder
        val removed = folder.apps.firstOrNull { it.componentKey == appKey } ?: return items
        val remaining = folder.apps.filter { it.componentKey != appKey }

        val mutable = items.toMutableList()
        when {
            remaining.isEmpty() -> mutable.removeAt(idx)
            remaining.size == 1 -> {
                mutable[idx] = HomeItem.App(remaining[0])
                mutable.add(idx + 1, HomeItem.App(removed))
            }
            else -> {
                mutable[idx] = folder.copy(apps = remaining)
                mutable.add(idx + 1, HomeItem.App(removed))
            }
        }
        return mutable
    }

    fun ungroupFolder(items: List<HomeItem>, folderId: String): List<HomeItem> {
        val idx = items.indexOfFirst { it is HomeItem.Folder && it.id == folderId }
        if (idx < 0) return items
        val folder = items[idx] as HomeItem.Folder
        val mutable = items.toMutableList()
        mutable.removeAt(idx)
        mutable.addAll(idx, folder.apps.map { HomeItem.App(it) })
        return mutable
    }

    fun moveAppInFolder(items: List<HomeItem>, folderId: String, fromIdx: Int, toIdx: Int): List<HomeItem> {
        return items.map { item ->
            if (item is HomeItem.Folder && item.id == folderId &&
                fromIdx in item.apps.indices && toIdx in item.apps.indices && fromIdx != toIdx
            ) {
                val mutable = item.apps.toMutableList()
                val moved = mutable.removeAt(fromIdx)
                mutable.add(toIdx, moved)
                item.copy(apps = mutable)
            } else {
                item
            }
        }
    }
}
