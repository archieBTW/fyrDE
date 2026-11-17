import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/panes/backup_pane.dart';
import 'package:fyrsettings/services/backup_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BackupService', () {
    test('discovers Fyr configs, tags, journal entries, and home folders cleanly', () async {
      final tmpHome = await Directory.systemTemp.createTemp('fyr_backup_home_');
      try {
        await Directory(p.join(tmpHome.path, '.config/fyr')).create(recursive: true);
        await Directory(p.join(tmpHome.path, '.config/sway/conf.d')).create(recursive: true);
        await Directory(p.join(tmpHome.path, '.config/fyrdock')).create(recursive: true);
        await Directory(p.join(tmpHome.path, '.fyr/files')).create(recursive: true);
        await Directory(p.join(tmpHome.path, 'Documents/fyrjournal')).create(recursive: true);
        await Directory(p.join(tmpHome.path, '.local/share/dev.fyrde.fyrdirector')).create(recursive: true);
        await Directory(p.join(tmpHome.path, 'Pictures')).create(recursive: true);

        await File(p.join(tmpHome.path, '.config/fyr/theme.txt')).writeAsString('FFBB86FC');
        await File(p.join(tmpHome.path, '.fyr/files/tags.json')).writeAsString('[{"filePath":"/a","tag":"green"}]');
        await File(p.join(tmpHome.path, 'Documents/fyrjournal/2026-11-17.txt')).writeAsString('Hello journal');

        final items = BackupService.discoverPaths(
          const BackupSelection(
            includeFyrConfigs: true,
            includeFyrData: true,
            includeHomeFolders: true,
            includeFullHome: false,
          ),
          homeOverride: tmpHome.path,
        );

        final rels = items.map((e) => e.relativePath).toSet();
        expect(rels, contains('.config/fyr'));
        expect(rels, contains('.config/sway'));
        expect(rels, contains('.config/fyrdock'));
        expect(rels, contains('.fyr'));
        expect(rels, contains('Documents/fyrjournal'));
        expect(rels, contains('.local/share/dev.fyrde.fyrdirector'));
        expect(rels, contains('Pictures'));
      } finally {
        await tmpHome.delete(recursive: true);
      }
    });

    test('round-trip creates, inspects, and restores plain & encrypted backups', () async {
      final tmpHome = await Directory.systemTemp.createTemp('fyr_backup_src_');
      final tmpDest = await Directory.systemTemp.createTemp('fyr_backup_dst_');
      try {
        await Directory(p.join(tmpHome.path, '.config/fyr')).create(recursive: true);
        await Directory(p.join(tmpHome.path, '.fyr/files')).create(recursive: true);
        await Directory(p.join(tmpHome.path, 'Documents/fyrjournal')).create(recursive: true);
        await Directory(p.join(tmpHome.path, '.cache/ignored')).create(recursive: true);

        await File(p.join(tmpHome.path, '.config/fyr/theme.txt')).writeAsString('FF123456');
        await File(p.join(tmpHome.path, '.fyr/files/tags.json')).writeAsString('[{"tag":"important"}]');
        await File(p.join(tmpHome.path, 'Documents/fyrjournal/entry1.txt')).writeAsString('Dear diary');
        await File(p.join(tmpHome.path, '.cache/ignored/junk.bin')).writeAsString('skip');

        const sel = BackupSelection(
          includeFyrConfigs: true,
          includeFyrData: true,
          includeHomeFolders: false,
        );

        // Plain tar.gz backup & restore
        final plainRes = await BackupService.createBackup(
          selection: sel,
          destinationDir: tmpDest.path,
          homeOverride: tmpHome.path,
        );
        expect(plainRes.ok, isTrue, reason: plainRes.message);
        expect(plainRes.archivePath, endsWith('.fyrbackup.tar.gz'));

        final manifest = await BackupService.inspectArchive(plainRes.archivePath!);
        expect(manifest, isNotNull);
        expect(manifest!.includedPaths, containsAll(['.config/fyr', '.fyr', 'Documents/fyrjournal']));

        // Delete sources and restore
        await Directory(p.join(tmpHome.path, 'Documents/fyrjournal')).delete(recursive: true);
        await Directory(p.join(tmpHome.path, '.fyr')).delete(recursive: true);

        final restorePlain = await BackupService.restoreArchive(
          archivePath: plainRes.archivePath!,
          targetHomeOverride: tmpHome.path,
        );
        expect(restorePlain.ok, isTrue, reason: restorePlain.message);
        expect(
          await File(p.join(tmpHome.path, 'Documents/fyrjournal/entry1.txt')).readAsString(),
          'Dear diary',
        );
        expect(
          await File(p.join(tmpHome.path, '.fyr/files/tags.json')).readAsString(),
          '[{"tag":"important"}]',
        );

        // Encrypted backup & restore
        final encRes = await BackupService.createBackup(
          selection: sel,
          destinationDir: tmpDest.path,
          encryptionPassphrase: 'backup-secret-password',
          homeOverride: tmpHome.path,
        );
        expect(encRes.ok, isTrue, reason: encRes.message);
        expect(encRes.archivePath, endsWith('.fyrbackup.tar.gz.gpg'));

        final listed = BackupService.listBackupsInDirectory(tmpDest.path);
        expect(listed.length, 2);

        final encManifestWrong = await BackupService.inspectArchive(
          encRes.archivePath!,
          passphrase: 'wrong',
        );
        expect(encManifestWrong, isNull);

        final encManifestRight = await BackupService.inspectArchive(
          encRes.archivePath!,
          passphrase: 'backup-secret-password',
        );
        expect(encManifestRight, isNotNull);
        expect(encManifestRight!.isEncrypted, isTrue);

        await File(p.join(tmpHome.path, 'Documents/fyrjournal/entry1.txt')).delete();
        final restoreEnc = await BackupService.restoreArchive(
          archivePath: encRes.archivePath!,
          passphrase: 'backup-secret-password',
          targetHomeOverride: tmpHome.path,
        );
        expect(restoreEnc.ok, isTrue, reason: restoreEnc.message);
        expect(
          await File(p.join(tmpHome.path, 'Documents/fyrjournal/entry1.txt')).readAsString(),
          'Dear diary',
        );
      } finally {
        await tmpHome.delete(recursive: true);
        await tmpDest.delete(recursive: true);
      }
    });
  });

  group('BackupPane widget', () {
    testWidgets('renders backup controls, external drive chips, and path preview', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BackupPane(
              autoLoad: false,
              initialConfig: const BackupSettingsConfig(destinationDir: '/tmp/backups'),
              initialMountedDrives: const ['/run/media/archer/archie-ext'],
              initialEstimatedBytes: 42 * 1000 * 1000,
              initialItems: const [
                BackupDiscoveredItem(
                  relativePath: '.config/fyr',
                  category: 'Fyr Configs',
                  description: 'Fyr settings',
                ),
                BackupDiscoveredItem(
                  relativePath: 'Documents/fyrjournal',
                  category: 'Fyr Data & Tags',
                  description: 'Journal entries',
                ),
              ],
              initialBackups: [
                BackupArchiveEntry(
                  path: '/tmp/backups/fyr-backup-20261117.fyrbackup.tar.gz.gpg',
                  name: 'fyr-backup-20261117.fyrbackup.tar.gz.gpg',
                  sizeBytes: 12500000,
                  modifiedAt: DateTime(2026, 11, 17, 14, 0),
                  isEncrypted: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Backup & Restore'), findsOneWidget);
      expect(find.text('archie-ext'), findsOneWidget);
      expect(find.textContaining('42 MB'), findsOneWidget);
      expect(find.text('fyr-backup-20261117.fyrbackup.tar.gz.gpg'), findsOneWidget);

      await tester.tap(find.text('archie-ext'));
      await tester.pump();
      expect(find.text('/run/media/archer/archie-ext/fyr-backups'), findsOneWidget);

      await tester.tap(find.textContaining('Preview Included Paths'));
      await tester.pump();
      expect(find.text('~/Documents/fyrjournal  —  Journal entries'), findsOneWidget);
    });
  });
}
