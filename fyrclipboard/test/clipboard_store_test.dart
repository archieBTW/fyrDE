import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrclipboard/clipboard_store.dart';

void main() {
  late Directory tempDir;
  late ClipboardStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fyrclipboard_test_');
    store = ClipboardStore(dataDir: tempDir.path);
    await store.init(startWatcher: false);
  });

  tearDown(() async {
    store.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('deduplicates text entries and preserves pin state', () async {
    final t1 = DateTime(2026, 1, 1, 10, 0, 0);
    final t2 = DateTime(2026, 1, 1, 10, 1, 0);
    final t3 = DateTime(2026, 1, 1, 10, 2, 0);

    await store.addText('hello world', now: t1);
    await store.addText('second item', now: t2);
    expect(store.entries.value.length, 2);
    expect(store.entries.value.first.text, 'second item');

    // Pin first item and re-copy it
    final helloId = store.entries.value.last.id;
    await store.togglePin(helloId);
    expect(store.entries.value.first.pinned, isTrue);

    await store.addText('hello world', now: t3);
    expect(store.entries.value.length, 2);
    expect(store.entries.value.first.pinned, isTrue);
    expect(store.entries.value.first.timestamp, t3);
  });

  test('clearUnpinned keeps pinned items and deletes unpinned images', () async {
    await store.addText('keep me');
    await store.togglePin(store.entries.value.first.id);

    final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
    await store.addImageBytes(png);
    final imgPath = store.entries.value
        .firstWhere((e) => e.type == ClipboardEntryType.image)
        .imagePath!;
    expect(File(imgPath).existsSync(), isTrue);

    await store.clearUnpinned();
    expect(store.entries.value.length, 1);
    expect(store.entries.value.first.text, 'keep me');
    expect(File(imgPath).existsSync(), isFalse);
  });

  test('persists and reloads history across store instances', () async {
    await store.addText('persisted snippet');
    final reloaded = ClipboardStore(dataDir: tempDir.path);
    await reloaded.init(startWatcher: false);
    expect(reloaded.entries.value.length, 1);
    expect(reloaded.entries.value.first.text, 'persisted snippet');
    reloaded.dispose();
  });
}
