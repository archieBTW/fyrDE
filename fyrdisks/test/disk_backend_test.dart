import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrdisks/main.dart';
import 'package:fyrdisks/models/disk_models.dart';
import 'package:fyrdisks/services/disk_backend.dart';
import 'package:fyrdisks/widgets/disk_dialogs.dart';
import 'package:fyrdisks/widgets/iso_flasher_view.dart';

void main() {
  group('DiskBackend parsers', () {
    test('parseLsblkDisks classifies USB, LUKS encrypted, and system OS disks', () {
      final jsonText = jsonEncode({
        'blockdevices': [
          {
            'name': '/dev/sda',
            'kname': 'sda',
            'path': '/dev/sda',
            'type': 'disk',
            'size': 61933092864,
            'fstype': 'iso9660',
            'label': 'ARCH_202611',
            'rm': true,
            'hotplug': true,
            'ro': false,
            'model': 'Patriot Memory',
            'tran': 'usb',
            'children': [
              {
                'name': '/dev/sda1',
                'kname': 'sda1',
                'path': '/dev/sda1',
                'type': 'part',
                'partn': 1,
                'size': 1203208192,
                'fstype': 'iso9660',
                'label': 'ARCH_202611',
                'mountpoints': [],
              },
            ],
          },
          {
            'name': '/dev/sdb',
            'kname': 'sdb',
            'path': '/dev/sdb',
            'type': 'disk',
            'size': 1000204886016,
            'pttype': 'gpt',
            'rm': false,
            'hotplug': true,
            'model': 'TOSHIBA MQ01UBD100',
            'tran': 'usb',
            'children': [
              {
                'name': '/dev/sdb1',
                'kname': 'sdb1',
                'path': '/dev/sdb1',
                'type': 'part',
                'partn': 1,
                'size': 1000203837440,
                'fstype': 'crypto_LUKS',
                'mountpoints': [],
                'children': [
                  {
                    'name': '/dev/mapper/luks-123',
                    'kname': 'dm-0',
                    'path': '/dev/mapper/luks-123',
                    'type': 'crypt',
                    'size': 1000187060224,
                    'fstype': 'ext4',
                    'label': 'archie-ext',
                    'mountpoints': ['/run/media/archer/archie-ext'],
                  },
                ],
              },
            ],
          },
          {
            'name': '/dev/nvme0n1',
            'kname': 'nvme0n1',
            'path': '/dev/nvme0n1',
            'type': 'disk',
            'size': 256060514304,
            'pttype': 'gpt',
            'rm': false,
            'hotplug': false,
            'model': 'Samsung NVMe',
            'tran': 'nvme',
            'children': [
              {
                'name': '/dev/nvme0n1p1',
                'kname': 'nvme0n1p1',
                'path': '/dev/nvme0n1p1',
                'type': 'part',
                'partn': 1,
                'size': 254984323072,
                'fstype': 'btrfs',
                'mountpoints': ['/', '/home'],
              },
            ],
          },
          {
            'name': '/dev/zram0',
            'kname': 'zram0',
            'path': '/dev/zram0',
            'type': 'disk',
            'size': 4294967296,
            'fstype': 'swap',
            'mountpoints': ['[SWAP]'],
          },
        ],
      });

      final disks = DiskBackend.parseLsblkDisks(jsonText);
      expect(disks.length, 3); // zram0 excluded

      expect(disks[0].devicePath, '/dev/sda');
      expect(disks[0].isExternal, isTrue);
      expect(disks[0].isSystemDisk, isFalse);

      expect(disks[1].devicePath, '/dev/sdb');
      expect(disks[1].hasAnyEncryptedPartition, isTrue);
      expect(disks[1].partitions.single.isUnlocked, isTrue);
      expect(disks[1].partitions.single.displayLabel, 'archie-ext');
      expect(disks[1].partitions.single.mountPoints, ['/run/media/archer/archie-ext']);

      expect(disks[2].devicePath, '/dev/nvme0n1');
      expect(disks[2].isSystemDisk, isTrue);
      expect(disks[2].partitions.single.isSystemCritical, isTrue);
    });

    test('parsePartedFreeRegions extracts free space gaps >= 4 MiB', () {
      const sample = '''
BYT;
/dev/sda:61933092864B:scsi:512:512:gpt:Patriot Memory:;
1:17408B:1048575B:1031168B:free;
1:1048576B:10737418239B:10736369664B:ext4:data:;
2:10737418240B:61933075455B:51195657216B:free;
''';
      final regions = DiskBackend.parsePartedFreeRegions(sample);
      expect(regions.length, 1);
      expect(regions.single.startBytes, 10737418240);
      expect(regions.single.sizeBytes, 51195657216);
    });

    test('parseDdProgressLine parses progress bytes and transfer speed', () {
      final p1 = DiskBackend.parseDdProgressLine(
        '536870912 bytes (537 MB, 512 MiB) copied, 5.0 s, 107 MB/s',
        1073741824,
      );
      expect(p1, isNotNull);
      expect(p1!.bytesWritten, 536870912);
      expect(p1.fraction, closeTo(0.5, 0.01));
      expect(p1.speedBytesPerSec, closeTo(107000000, 1.0));
    });
  });

  group('fyrDisks UI widgets', () {
    testWidgets('DisksShell renders external, encrypted, and protected OS disks cleanly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sampleDisks = [
        const BlockDisk(
          devicePath: '/dev/sdb',
          kname: 'sdb',
          sizeBytes: 1000204886016,
          model: 'TOSHIBA MQ01UBD100',
          transport: 'usb',
          partitionTable: 'gpt',
          isHotplug: true,
          partitions: [
            BlockPartition(
              devicePath: '/dev/sdb1',
              kname: 'sdb1',
              parentDiskPath: '/dev/sdb',
              partitionNumber: 1,
              sizeBytes: 1000203837440,
              fsType: 'crypto_LUKS',
              isEncrypted: true,
              isUnlocked: true,
              mapperPath: '/dev/mapper/luks-test',
              unlockedFsType: 'ext4',
              unlockedLabel: 'archie-ext',
              mountPoints: ['/run/media/archer/archie-ext'],
            ),
          ],
        ),
        const BlockDisk(
          devicePath: '/dev/nvme0n1',
          kname: 'nvme0n1',
          sizeBytes: 256060514304,
          model: 'Samsung NVMe',
          transport: 'nvme',
          partitionTable: 'gpt',
          isSystemDisk: true,
          partitions: [
            BlockPartition(
              devicePath: '/dev/nvme0n1p1',
              kname: 'nvme0n1p1',
              parentDiskPath: '/dev/nvme0n1',
              partitionNumber: 1,
              sizeBytes: 254984323072,
              fsType: 'btrfs',
              mountPoints: ['/'],
              isSystemCritical: true,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: DisksShell(
            autoLoad: false,
            initialDisks: sampleDisks,
            initialFilesystems: const [
              FilesystemOption(id: 'ext4', displayName: 'Linux ext4', toolBinary: 'mkfs.ext4', available: true),
              FilesystemOption(
                id: 'luks_ext4',
                displayName: 'Encrypted LUKS2 + ext4',
                toolBinary: 'cryptsetup',
                available: true,
                supportsEncryption: true,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('fyrDisks'), findsOneWidget);
      expect(find.text('archie-ext'), findsWidgets);
      expect(find.text('LUKS Unlocked'), findsOneWidget);
      expect(find.text('Lock LUKS'), findsOneWidget);
      expect(find.text('Flash ISO'), findsOneWidget);

      await tester.tap(find.text('Flash ISO'));
      await tester.pumpAndSettle();
      expect(find.text('Flash ISO / Disk Image'), findsOneWidget);
      expect(find.text('2. Target USB / Removable Drive'), findsOneWidget);
    });

    testWidgets('CreatePartitionTableDialog and IsoFlasherView enforce confirmation safely', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const usb = BlockDisk(
        devicePath: '/dev/sda',
        kname: 'sda',
        sizeBytes: 61933092864,
        model: 'Patriot Memory',
        isRemovable: true,
        transport: 'usb',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IsoFlasherView(
              disks: const [usb],
              onCompleted: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Patriot Memory'), findsWidgets);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog(context: ctx, builder: (_) => const CreatePartitionTableDialog(disk: usb));
                },
                child: const Text('OpenTbl'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OpenTbl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase & Create Table'));
      await tester.pump();
      expect(find.textContaining('Type "sda" exactly'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
