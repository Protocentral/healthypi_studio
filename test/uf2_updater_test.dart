// HealthyPi Core firmware update: reset_bootsel → picotool load -x → reconnect
// → fw_versions. Every board-facing step is a fake, and picotool is a fake
// process runner, so the control flow is tested without hardware.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/protocol/hpi_core.dart';
import 'package:healthypi_studio/services/firmware/firmware_updater.dart';
import 'package:healthypi_studio/services/firmware/picotool.dart';
import 'package:healthypi_studio/services/firmware/uf2.dart';
import 'package:healthypi_studio/services/firmware/uf2_updater.dart';
import 'package:healthypi_studio/services/smp_serial_client.dart';

/// A scripted board plus picotool, recording every step in [events].
class FakeCore {
  final events = <String>[];

  HpiFailure? resetRefusal;

  /// `picotool info` fails this many times before the boot ROM shows up;
  /// null means it never does.
  int? bootromAfter = 1;
  int _infoCalls = 0;

  int loadExit = 0;
  String loadStderr = '';

  /// Reattach fails this many times before the Core answers; null = never.
  int? appAfter = 0;
  int _attachCalls = 0;

  String? versionAfter = '0.2.0';

  Future<ProcessResult> run(String exe, List<String> args) async {
    events.add('picotool ${args.join(' ')}');
    if (args.first == 'info') {
      final ok = bootromAfter != null && _infoCalls++ >= bootromAfter!;
      return ProcessResult(0, ok ? 0 : 255, '',
          ok ? '' : 'No accessible RP-series devices in BOOTSEL mode were found.');
    }
    if (args.first == 'load') return ProcessResult(0, loadExit, '', loadStderr);
    return ProcessResult(0, 1, '', 'unexpected');
  }

  Uf2Updater updater({bool picotool = true}) => Uf2Updater(
        picotool: picotool ? Picotool('/fake/picotool', run: run) : null,
        resetBootsel: () async {
          events.add('reset_bootsel');
          return resetRefusal;
        },
        detach: () async => events.add('detach'),
        reattach: () async {
          events.add('reattach');
          return appAfter != null && _attachCalls++ >= appAfter!;
        },
        readVersion: () async {
          events.add('fw_versions');
          return versionAfter;
        },
        bootromWait: const Duration(milliseconds: 50),
        appReturn: const Duration(milliseconds: 50),
        poll: const Duration(milliseconds: 5),
      )..missingPicotool = 'picotool was not found.';
}

/// One 512-byte UF2 block for [family].
Uint8List uf2Block(int family, {int blockNo = 0, int blocks = 1, int size = 256}) {
  final b = ByteData(512);
  b.setUint32(0, Uf2Image.magicStart0, Endian.little);
  b.setUint32(4, Uf2Image.magicStart1, Endian.little);
  b.setUint32(8, Uf2Image.flagFamilyIdPresent, Endian.little);
  b.setUint32(12, 0x10000000 + blockNo * size, Endian.little);
  b.setUint32(16, size, Endian.little);
  b.setUint32(20, blockNo, Endian.little);
  b.setUint32(24, blocks, Endian.little);
  b.setUint32(28, family, Endian.little);
  b.setUint32(508, Uf2Image.magicEnd, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  group('Uf2Updater', () {
    test('happy path: reset, let go, wait for BOOTSEL, load -x, reconnect, '
        'read the version', () async {
      final core = FakeCore();
      final stages = <UpdateStage>[];
      final u = core.updater();
      final out = await Uf2Updater(
        picotool: u.picotool,
        resetBootsel: u.resetBootsel,
        detach: u.detach,
        reattach: u.reattach,
        readVersion: u.readVersion,
        onProgress: (p) => stages.add(p.stage),
        bootromWait: u.bootromWait,
        appReturn: u.appReturn,
        poll: u.poll,
      ).install('/fw/core.uf2', versionBefore: '0.1.0');

      expect(core.events, [
        'reset_bootsel',
        'detach',
        'picotool info', // not yet in BOOTSEL
        'picotool info',
        'picotool load -x /fw/core.uf2',
        'reattach',
        'fw_versions',
      ]);
      expect(out.ok, isTrue);
      expect(out.versionsAfter, {'fw': '0.2.0'});
      expect(stages, [
        UpdateStage.checking,
        UpdateStage.resetting,
        UpdateStage.waitingBootrom,
        UpdateStage.loadingUf2,
        UpdateStage.verifying,
        UpdateStage.done,
      ]);
    });

    test('without picotool, the board is never sent to BOOTSEL', () async {
      final core = FakeCore();
      await expectLater(core.updater(picotool: false).install('/fw/core.uf2'),
          throwsA(isA<UpdateException>().having(
              (e) => e.message, 'message', contains('picotool was not found'))));
      expect(core.events, isEmpty);
    });

    test('a refused reset_bootsel stops before letting go of the port',
        () async {
      final core = FakeCore()
        ..resetRefusal = HpiFailure.fromReply(HpiCore.resetBootsel, 8, 64);
      await expectLater(core.updater().install('/fw/core.uf2'),
          throwsA(isA<UpdateException>().having(
              (e) => e.message, 'message', contains('Nothing was changed'))));
      expect(core.events, ['reset_bootsel']);
    });

    test('no boot ROM: reported, and nothing is loaded', () async {
      final core = FakeCore()..bootromAfter = null;
      await expectLater(core.updater().install('/fw/core.uf2'),
          throwsA(isA<UpdateException>().having(
              (e) => e.message, 'message', contains('did not appear in BOOTSEL'))));
      expect(core.events.where((e) => e.startsWith('picotool load')), isEmpty);
      expect(core.events, isNot(contains('reattach')));
    });

    test('a failed load reports picotool\'s reason and does not reconnect',
        () async {
      final core = FakeCore()
        ..loadExit = 252
        ..loadStderr = 'ERROR: The file is not a valid UF2';
      await expectLater(
          core.updater().install('/fw/core.uf2'),
          throwsA(isA<UpdateException>().having((e) => e.message, 'message',
              allOf(contains('not a valid UF2'), contains('still in BOOTSEL')))));
      expect(core.events.last, 'picotool load -x /fw/core.uf2');
    });

    test('the Core not coming back is an error, not a success', () async {
      final core = FakeCore()..appAfter = null;
      await expectLater(core.updater().install('/fw/core.uf2'),
          throwsA(isA<UpdateException>().having(
              (e) => e.message, 'message', contains('did not come back'))));
      expect(core.events, isNot(contains('fw_versions')));
    });

    test('a slow re-enumeration is waited for', () async {
      final core = FakeCore()..appAfter = 3;
      final out = await core.updater().install('/fw/core.uf2');
      expect(out.ok, isTrue);
      expect(core.events.where((e) => e == 'reattach'), hasLength(4));
    });

    test('back, but no version: the outcome says so', () async {
      final core = FakeCore()..versionAfter = null;
      final out = await core.updater().install('/fw/core.uf2');
      expect(out.ok, isFalse);
      expect(out.versionsAfter, isEmpty);
    });

    test('a board already in BOOTSEL is loaded without a reset', () async {
      final core = FakeCore()..bootromAfter = 0;
      final out = await core
          .updater()
          .install('/fw/core.uf2', alreadyInBootsel: true);
      expect(out.ok, isTrue);
      expect(core.events, [
        'picotool info',
        'picotool load -x /fw/core.uf2',
        'reattach',
        'fw_versions',
      ]);
    });
  });

  group('Uf2Image', () {
    test('accepts an RP2350 image and totals its payload', () {
      final bytes = Uint8List.fromList([
        ...uf2Block(Uf2Image.familyRp2350ArmS, blockNo: 0, blocks: 2),
        ...uf2Block(Uf2Image.familyRp2350ArmS, blockNo: 1, blocks: 2),
      ]);
      expect(Uf2Image.looksLikeUf2(bytes), isTrue);
      final img = Uf2Image.parse(bytes);
      expect(img.blockCount, 2);
      expect(img.payloadBytes, 512);
      expect(img.isRp2350, isTrue);
    });

    test('refuses an RP2040 image before the board is touched', () {
      expect(
          () => Uf2Image.parse(uf2Block(Uf2Image.familyRp2040)),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('RP2040'))));
    });

    test('refuses a truncated file and a bad magic', () {
      expect(() => Uf2Image.parse(Uint8List(100)), throwsFormatException);
      final bad = uf2Block(Uf2Image.familyRp2350ArmS)..[508] = 0;
      expect(() => Uf2Image.parse(bad), throwsFormatException);
      expect(Uf2Image.looksLikeUf2([1, 2, 3]), isFalse);
    });
  });

  group('PicotoolLocator', () {
    PicotoolLocator locator(Set<String> files,
            {String? override, String path = '/usr/bin:/opt/tools'}) =>
        PicotoolLocator(
          override: override,
          environment: {'PATH': path},
          resolvedExecutable: '/Applications/Studio.app/Contents/MacOS/Studio',
          exists: files.contains,
          isWindows: false,
        );

    test('a chosen path wins, and a wrong one is reported, not replaced', () {
      expect(locator({'/x/picotool', '/usr/bin/picotool'}, override: '/x/picotool')
          .locate(), '/x/picotool');
      final wrong = locator({'/usr/bin/picotool'}, override: '/y/picotool');
      expect(wrong.locate(), isNull);
      expect(wrong.missingMessage, contains('/y/picotool'));
    });

    test('a bundled copy comes before PATH', () {
      const bundled = '/Applications/Studio.app/Contents/MacOS/../Resources/picotool';
      expect(locator({bundled, '/usr/bin/picotool'}).locate(), bundled);
    });

    test('PATH, then Homebrew (a GUI app does not inherit the shell PATH)', () {
      expect(locator({'/opt/tools/picotool'}).locate(), '/opt/tools/picotool');
      expect(locator({'/opt/homebrew/bin/picotool'}, path: '').locate(),
          '/opt/homebrew/bin/picotool');
    });

    test('nothing found: a clear message', () {
      final none = locator({});
      expect(none.locate(), isNull);
      expect(none.missingMessage, contains('picotool was not found'));
    });
  });
}
