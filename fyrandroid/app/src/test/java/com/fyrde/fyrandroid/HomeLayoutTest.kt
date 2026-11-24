package com.fyrde.fyrandroid

import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.model.HomeItem
import com.fyrde.fyrandroid.model.HomeLayoutCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeLayoutTest {

    private val appA = AppEntry("Alpha", "com.example.a", ".Main")
    private val appB = AppEntry("Beta", "com.example.b", ".Main")
    private val appC = AppEntry("Gamma", "com.example.c", ".Main")
    private val appD = AppEntry("Delta", "com.example.d", ".Main")

    @Test
    fun moveItemReordersHomeItems() {
        val initial = listOf(HomeItem.App(appA), HomeItem.App(appB), HomeItem.App(appC))
        val reordered = HomeLayoutCodec.moveItem(initial, 2, 0)
        assertEquals(listOf("Alpha", "Beta", "Gamma"), initial.map { it.label })
        assertEquals(listOf("Gamma", "Alpha", "Beta"), reordered.map { it.label })
    }

    @Test
    fun groupItemsCreatesFolderAndAddsMoreApps() {
        val initial = listOf(HomeItem.App(appA), HomeItem.App(appB), HomeItem.App(appC))
        val grouped = HomeLayoutCodec.groupItems(initial, 1, 0, newFolderId = "f1")
        assertEquals(2, grouped.size)
        val folder = grouped[0] as HomeItem.Folder
        assertEquals("f1", folder.id)
        assertEquals(listOf(appA, appB), folder.apps)

        val withThird = HomeLayoutCodec.groupItems(grouped, 1, 0)
        assertEquals(1, withThird.size)
        assertEquals(listOf(appA, appB, appC), (withThird[0] as HomeItem.Folder).apps)
    }

    @Test
    fun removeAppFromFolderAutoDissolvesSingleAppFolder() {
        val folder = HomeItem.Folder("f1", "Work", listOf(appA, appB))
        val afterRemove = HomeLayoutCodec.removeAppFromFolder(listOf(folder), "f1", appB.componentKey)
        assertEquals(2, afterRemove.size)
        assertTrue(afterRemove[0] is HomeItem.App)
        assertEquals(appA, (afterRemove[0] as HomeItem.App).entry)
        assertEquals(appB, (afterRemove[1] as HomeItem.App).entry)
    }

    @Test
    fun renameAndUngroupFolderWorkCleanly() {
        val folder = HomeItem.Folder("f1", "Folder", listOf(appA, appB, appC))
        val renamed = HomeLayoutCodec.renameFolder(listOf(folder), "f1", "Tools")
        assertEquals("Tools", (renamed[0] as HomeItem.Folder).name)

        val ungrouped = HomeLayoutCodec.ungroupFolder(renamed, "f1")
        assertEquals(listOf("Alpha", "Beta", "Gamma"), ungrouped.map { it.label })
    }

    @Test
    fun serializeAndReconcilePreservesOrderFoldersAndAppendsNewApps() {
        val layout = listOf(
            HomeItem.App(appC),
            HomeItem.Folder("f1", "Social", listOf(appA, appB))
        )
        val json = HomeLayoutCodec.serialize(layout)
        // Reconcile with appD newly installed and appC still present
        val restored = HomeLayoutCodec.reconcile(json, listOf(appA, appB, appC, appD), emptyList())
        assertEquals(3, restored.size)
        assertEquals("Gamma", restored[0].label)
        assertEquals("Social", restored[1].label)
        assertEquals(listOf(appA, appB), (restored[1] as HomeItem.Folder).apps)
        assertEquals("Delta", restored[2].label)
    }
}
