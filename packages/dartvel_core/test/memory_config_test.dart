// dartvel.memory: defaults and per-target ceilings that DV.Memory.allocate
// applies to every arena it creates.
//
// Silent failures here are a configured number that is accepted and then
// ignored -- a ceiling for a 128MB television that the factory never applies,
// or a device profile override that loses to the target it was written to
// override -- and a registry that reports an arena nobody holds any more.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVMemoryConfig parse(
  Map<String, Object?> memory, {
  Map<String, Object?>? deviceProfiles,
}) => DVMemoryConfig.parse(<String, Object?>{
  'memory': memory,
  if (deviceProfiles != null) 'deviceProfiles': deviceProfiles,
});

void main() {
  tearDown(DVMemory.debugReset);

  group('parsing dartvel.memory', () {
    test('the specification example reads as written', () {
      final DVMemoryConfig c = parse(<String, Object?>{
        'budget': '4GB',
        'segment': '256MB',
        'touchPages': 'desktop',
        'targets': <String, Object?>{
          'web': <String, Object?>{'budget': '512MB', 'segment': '128MB'},
          'android': <String, Object?>{'budget': '512MB', 'segment': '64MB'},
          'tizen': <String, Object?>{'budget': '128MB', 'segment': '32MB'},
          'sony-elinux': <String, Object?>{
            'budget': '256MB',
            'segment': '32MB',
          },
        },
      });
      expect(c.problems, isEmpty);

      final DVMemorySettings linux = c.resolve(DVMemoryTarget.linux);
      expect(linux.budget, const DVSize.gb(4));
      expect(linux.segment, const DVSize.mb(256));
      expect(linux.ceiling, isNull);
      expect(linux.touchPages, isTrue);

      final DVMemorySettings tizen = c.resolve(DVMemoryTarget.tizen);
      expect(tizen.budget, const DVSize.mb(128));
      expect(tizen.segment, const DVSize.mb(32));
      expect(tizen.ceiling, const DVSize.mb(128));
      expect(tizen.touchPages, isFalse);

      // `web` covers both compilers.
      expect(c.resolve(DVMemoryTarget.webJs).ceiling, const DVSize.mb(512));
      expect(c.resolve(DVMemoryTarget.webWasm).segment, const DVSize.mb(128));
      expect(c.resolve(DVMemoryTarget.sonyElinux).budget, const DVSize.mb(256));
    });

    test('nothing configured falls back to the profile defaults', () {
      final DVMemoryConfig c = DVMemoryConfig.parse(null);
      expect(c.problems, isEmpty);
      expect(c.resolve(DVMemoryTarget.android).segment, const DVSize.mb(64));
      expect(c.resolve(DVMemoryTarget.webos).segment, const DVSize.mb(32));
      expect(c.resolve(DVMemoryTarget.macos).segment, const DVSize.mb(256));
      expect(c.resolve(DVMemoryTarget.webJs).segment, const DVSize.mb(128));
      expect(c.resolve(DVMemoryTarget.macos).budget, isNull);
    });

    test('top-level values apply to every target; the profile default only '
        'where nothing is configured', () {
      final DVMemoryConfig c = parse(<String, Object?>{'segment': '16MB'});
      expect(c.resolve(DVMemoryTarget.tizen).segment, const DVSize.mb(16));
      expect(c.resolve(DVMemoryTarget.linux).segment, const DVSize.mb(16));
      expect(c.resolve(DVMemoryTarget.linux).segmentConfigured, isTrue);
      expect(
        DVMemoryConfig.parse(
          null,
        ).resolve(DVMemoryTarget.linux).segmentConfigured,
        isFalse,
      );
    });

    test('touchPages: true is still never honoured on mobile or embedded', () {
      final DVMemoryConfig c = parse(<String, Object?>{'touchPages': true});
      expect(c.resolve(DVMemoryTarget.linux).touchPages, isTrue);
      expect(c.resolve(DVMemoryTarget.ios).touchPages, isFalse);
      expect(c.resolve(DVMemoryTarget.webos).touchPages, isFalse);
      expect(c.resolve(DVMemoryTarget.webJs).touchPages, isFalse);
      expect(c.touchPagesRefusedOn(DVMemoryTarget.ios), isTrue);
      expect(c.touchPagesRefusedOn(DVMemoryTarget.linux), isFalse);
    });

    test('touchPages: desktop is not a refusal on mobile', () {
      final DVMemoryConfig c = parse(<String, Object?>{
        'touchPages': 'desktop',
      });
      expect(c.touchPagesRefusedOn(DVMemoryTarget.android), isFalse);
    });

    test('mistakes are problems, not silent defaults', () {
      final DVMemoryConfig c = parse(<String, Object?>{
        'budget': 'plenty',
        'segment': '100MB',
        'touchPages': 'sometimes',
        'targets': <String, Object?>{
          'playstation': <String, Object?>{'budget': '1GB'},
        },
      });
      expect(c.problems, hasLength(4));
      expect(c.problems.join('\n'), contains('memory.budget'));
      expect(c.problems.join('\n'), contains('power of two'));
      expect(c.problems.join('\n'), contains('touchPages'));
      expect(c.problems.join('\n'), contains('playstation'));
    });
  });

  group('device profiles', () {
    test('a profile override wins over the target it runs on', () {
      final DVMemoryConfig c = parse(
        <String, Object?>{
          'targets': <String, Object?>{
            'sony-elinux': <String, Object?>{'budget': '256MB'},
          },
        },
        deviceProfiles: <String, Object?>{
          'lobby-display': <String, Object?>{
            'platform': 'sony-elinux',
            'ram': '1GB',
            'memory': <String, Object?>{'budget': '64MB', 'segment': '16MB'},
          },
        },
      );
      final DVMemorySettings s = c.resolve(
        DVMemoryTarget.sonyElinux,
        deviceProfile: 'lobby-display',
      );
      expect(s.budget, const DVSize.mb(64));
      expect(s.ceiling, const DVSize.mb(64));
      expect(s.segment, const DVSize.mb(16));
      expect(c.resolve(DVMemoryTarget.sonyElinux).budget, const DVSize.mb(256));
      expect(c.profileRam('lobby-display'), const DVSize.gb(1));
    });

    test('a profile naming nothing about memory changes nothing', () {
      final DVMemoryConfig c = parse(
        <String, Object?>{'budget': '1GB'},
        deviceProfiles: <String, Object?>{
          'kiosk': <String, Object?>{'platform': 'tizen'},
        },
      );
      expect(
        c.resolve(DVMemoryTarget.tizen, deviceProfile: 'kiosk').budget,
        const DVSize.gb(1),
      );
    });
  });

  group('DV.Memory.allocate', () {
    test('every call is an independent arena', () {
      const DVMemory memory = DVMemory();
      final DVPlatformMemory a = memory.allocate(
        megabytes: 1,
        segment: const DVSize.kb(64),
      );
      final DVPlatformMemory b = memory.allocate(
        megabytes: 1,
        segment: const DVSize.kb(64),
      );
      final MemorySlice<int> kept = b.uint8(4)..fill(7);
      a.uint8(1000 * 1024);
      a.reset();
      expect(kept[0], 7, reason: 'resetting one arena leaves the other alone');
      a.dispose();
      expect(b.isDisposed, isFalse);
      expect(kept[3], 7);
    });

    test('applies the configured budget when allocate names no size', () {
      DVMemory.configure(
        parse(<String, Object?>{'budget': '2MB', 'segment': '64KB'}),
        target: DVMemoryTarget.linux,
      );
      final DVPlatformMemory m = const DVMemory().allocate();
      expect(m.securedBytes, 2 * 1024 * 1024);
      expect(m.segmentBytes, 64 * 1024);
    });

    test('applies the target ceiling and says the arena was capped', () {
      DVMemory.configure(
        parse(<String, Object?>{
          'targets': <String, Object?>{
            'tizen': <String, Object?>{'budget': '1MB', 'segment': '64KB'},
          },
        }),
        target: DVMemoryTarget.tizen,
      );
      final DVPlatformMemory m = const DVMemory().allocate(megabytes: 4);
      expect(m.securedBytes, 1024 * 1024);
      expect(m.diagnostics.single.code, 'DV-MEMORY-001');
      expect(m.diagnostics.single.message, contains('asked 4MB'));
      expect(m.diagnostics.single.message, contains('ceiling'));
    });

    test('the device profile the build selected is applied', () {
      DVMemory.configure(
        parse(
          <String, Object?>{'budget': '4MB', 'segment': '64KB'},
          deviceProfiles: <String, Object?>{
            'small': <String, Object?>{
              'memory': <String, Object?>{'budget': '1MB'},
            },
          },
        ),
        target: DVMemoryTarget.sonyElinux,
        deviceProfile: 'small',
      );
      expect(const DVMemory().allocate().securedBytes, 1024 * 1024);
    });

    test('an explicit segment beats the configured one', () {
      DVMemory.configure(
        parse(<String, Object?>{'budget': '1MB', 'segment': '64KB'}),
        target: DVMemoryTarget.linux,
      );
      expect(
        const DVMemory().allocate(segment: const DVSize.kb(256)).segmentBytes,
        256 * 1024,
      );
    });

    test(
      'registers live arenas, in creation order, and forgets disposed ones',
      () {
        const DVMemory memory = DVMemory();
        final DVPlatformMemory a = memory.allocate(
          megabytes: 1,
          segment: const DVSize.kb(64),
        );
        final DVPlatformMemory b = memory.allocate(
          megabytes: 2,
          segment: const DVSize.kb(64),
        );
        // Constructed directly: not the instrumented path.
        DVPlatformMemory(megabytes: 1, segment: const DVSize.kb(64));
        expect(memory.arenas, <DVPlatformMemory>[a, b]);
        expect(a.id, lessThan(b.id));

        a.uint8(100 * 1024);
        b.uint8(300 * 1024);
        b.reset();
        b.uint8(10 * 1024);

        final DVMemoryUsage usage = memory.usage;
        expect(usage.arenas, 2);
        expect(usage.securedBytes, 3 * 1024 * 1024);
        expect(usage.usedBytes, 110 * 1024);
        expect(usage.highWaterBytes, 400 * 1024);
        expect(usage.resets, 1);

        a.dispose();
        expect(memory.arenas, <DVPlatformMemory>[b]);
        expect(memory.usage.securedBytes, 2 * 1024 * 1024);
      },
    );
  });
}
