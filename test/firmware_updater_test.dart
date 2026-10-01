// FirmwareUpdater against a fake board that behaves like firmware 1.0.x:
// overwrite-only MCUboot keyed by the SHA-256 TLV, the group-64 M4 update
// service, and the M4 missing its IPC bind after an M7 install.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/firmware/bundle.dart';
import 'package:healthypi_studio/services/firmware/firmware_updater.dart';
import 'package:healthypi_studio/services/smp_serial_client.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import 'support/fake_smp_device.dart';
import 'support/test_bundles.dart';

class _Board {
  _Board({required Uint8List runningM7})
      : slot0 = McuImageInfo.parse(runningM7).hash;

  String m7 = '1.0.1';
  String m4 = '1.0.1';
  Uint8List slot0;

  // MCUboot secondary slot
  final BytesBuilder _upload = BytesBuilder();
  Uint8List? slot1;
  String? slot1Version;
  bool pending = false;
  List<int>? markedWith;

  // M4 update service
  int m4State = 0;
  bool sigRequired = true;
  int? commitError;
  String? m4Incoming;
  List<int>? _m4Sha;
  final BytesBuilder _m4 = BytesBuilder();
  bool m4Bound = true;

  bool imgGroup = true;
  int resets = 0;
  final List<String> calls = [];

  void reset() {
    resets++;
    var m7Copied = false;
    if (pending && slot1 != null) {
      slot0 = slot1!;
      m7 = slot1Version!;
      slot1 = null;
      pending = false;
      m7Copied = true;
    }
    if (m4State == 3) {
      m4 = m4Incoming!;
      m4State = 0;
    }
    // MCUboot's copy delays the M7 past the M4's one-shot bind.
    m4Bound = !m7Copied;
  }

  Map<String, Object?>? handle(SmpMessage r) {
    final p = r.payload;
    if (r.group == 1 && r.id == 1) {
      calls.add('img upload');
      final off = p['off'] as int;
      if (off == 0) _upload.clear();
      final data = p['data'] as List<int>;
      _upload.add(data);
      final len = off == 0 ? p['len'] as int : null;
      if (len != null) _expected = len;
      if (_upload.length == _expected) {
        final bytes = _upload.toBytes();
        slot1 = McuImageInfo.parse(bytes).hash;
        slot1Version = McuImageInfo.parse(bytes).version.toString();
      }
      return {'off': off + data.length};
    }
    if (r.group == 1 && r.id == 0) {
      if (!imgGroup) return smpErr(8, group: 1);
      if (r.op == SmpOp.writeReq) {
        markedWith = p['hash'] as List<int>;
        calls.add('img test');
        if (slot1 == null || !_eq(markedWith!, slot1!)) {
          return smpErr(2, group: 1); // HASH_NOT_FOUND-ish
        }
        pending = true;
      }
      return {
        'images': [
          {'image': 0, 'slot': 0, 'version': m7, 'hash': slot0, 'active': true},
          if (slot1 != null)
            {
              'image': 0,
              'slot': 1,
              'version': slot1Version,
              'hash': slot1,
              'pending': pending,
            },
        ],
      };
    }
    if (r.group == 64) {
      switch (r.id) {
        case 0x21:
          calls.add('stream_stop');
          return {};
        case 0x31:
          return {'m7fw': m7, 'm4fw': m4Bound ? m4 : '', 'espfw': ''};
        case 0xA3:
          return {
            'st': m4State,
            'len': 0,
            'rx': _m4.length,
            'err': 0,
            'rst': false,
            'sig': sigRequired,
          };
        case 0xA4:
          calls.add('m4 abort');
          m4State = 0;
          _m4.clear();
          return {};
        case 0xA0:
          calls.add('m4 begin');
          if (m4State != 0) return smpErr(270);
          if (sigRequired && p['sig'] == null) return smpErr(268);
          m4State = 1;
          _m4.clear();
          _m4Sha = p['sha'] as List<int>;
          return {};
        case 0xA1:
          _m4.add(p['data'] as List<int>);
          return {'off': (p['off'] as int) + (p['data'] as List).length};
        case 0xA2:
          calls.add('m4 commit');
          if (commitError != null) {
            m4State = 4;
            return smpErr(commitError!);
          }
          if (!_eq(crypto.sha256.convert(_m4.toBytes()).bytes, _m4Sha!)) {
            m4State = 4;
            return smpErr(268);
          }
          m4State = 3;
          return {'rst': true};
      }
    }
    return smpErr(8, group: r.group);
  }

  int _expected = -1;

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

void main() {
  final signer = TestSigner();
  final m4Image = Uint8List.fromList(List<int>.generate(700, (i) => i * 7 & 0xFF));
  final oldM7 = buildMcuImage(version: (1, 0, 1), seed: 1);
  final newM7 = buildMcuImage(version: (1, 0, 2), seed: 2);

  late FakeSmpDevice device;
  late SmpSerialClient client;
  late _Board board;
  late List<String> log;

  FirmwareUpdater updater() => FirmwareUpdater(
        client: () => client,
        resetAndReconnect: () async {
          board.reset();
          return true;
        },
        log: log.add,
      );

  FirmwareBundle bundle(Map<String, (String, Uint8List)> images) =>
      FirmwareBundle.open(buildBundle(signer, images), keys: [signer.key]);

  setUp(() async {
    log = [];
    board = _Board(runningM7: oldM7);
    device = await FakeSmpDevice.bind();
    device.onRequest = (r) => board.handle(r);
    client = SmpSerialClient();
    expect(await client.openTcp('127.0.0.1', port: device.port), isTrue);
  });

  tearDown(() async {
    client.close();
    await device.close();
  });

  test('M4 + M7: stale upload aborted, TLV hash marked, second reset pairs the cores',
      () async {
    board.m4State = 1; // left behind by an interrupted run
    board.m4Incoming = '1.0.2';

    final out = await updater().applyBundle(
        bundle({'m4': ('1.0.2', m4Image), 'm7': ('1.0.2', newM7)}));

    expect(out.ok, isTrue, reason: log.join('\n'));
    expect(out.applied, ['m4', 'm7']);
    expect(out.versionsAfter['m7'], '1.0.2');
    expect(out.versionsAfter['m4'], '1.0.2');

    // The stale upload was cleared before begin, M4 before M7.
    final calls = board.calls;
    expect(calls.indexOf('stream_stop'), lessThan(calls.indexOf('m4 abort')));
    expect(calls.indexOf('m4 abort'), lessThan(calls.indexOf('m4 begin')));
    expect(calls.indexOf('m4 commit'), lessThan(calls.indexOf('img upload')));

    // Marked pending with the MCUboot hash, not the file's SHA-256.
    expect(board.markedWith, McuImageInfo.parse(newM7).hash);
    expect(board.markedWith, isNot(crypto.sha256.convert(newM7).bytes));

    // The M7 install unbinds the M4; a second reset is needed.
    expect(board.resets, 2);
  });

  test('M4 only: one reset, no second', () async {
    board.m4Incoming = '1.0.2';
    final out = await updater().applyBundle(bundle({'m4': ('1.0.2', m4Image)}));
    expect(out.ok, isTrue, reason: log.join('\n'));
    expect(board.resets, 1);
  });

  test('a commit the device refuses leaves bank 2 alone and does not reset',
      () async {
    board.commitError = 268;
    await expectLater(
      updater().applyBundle(bundle({'m4': ('1.0.2', m4Image)})),
      throwsA(isA<UpdateException>().having((e) => e.message, 'message',
          allOf(contains('IMAGE_INVALID'), contains('not modified')))),
    );
    expect(board.resets, 0);
    expect(board.m4, '1.0.1');
  });

  test('an older M7 is refused before anything is uploaded', () async {
    board.m7 = '1.0.2';
    await expectLater(
      updater().applyBundle(
          bundle({'m7': ('1.0.1', buildMcuImage(version: (1, 0, 1)))})),
      throwsA(isA<UpdateException>()
          .having((e) => e.message, 'message', contains('older'))),
    );
    expect(board.calls, isNot(contains('img upload')));
    expect(board.calls, isNot(contains('stream_stop')));
  });

  test('versions already installed: nothing applied, no reset', () async {
    final out = await updater().applyBundle(
        bundle({'m4': ('1.0.1', m4Image), 'm7': ('1.0.1', oldM7)}));
    expect(out.applied, isEmpty);
    expect(out.skipped, ['m4', 'm7']);
    expect(board.resets, 0);
  });

  test('a development build without the img group is named, not attempted',
      () async {
    board.imgGroup = false;
    await expectLater(
      updater().applyBundle(bundle({'m7': ('1.0.2', newM7)})),
      throwsA(isA<UpdateException>()
          .having((e) => e.message, 'message', contains('development build'))),
    );
    expect(board.calls, isNot(contains('img upload')));
  });

  test('a raw M7 image installs and is checked by its slot-0 hash', () async {
    final out = await updater().applyM7Image(newM7);
    expect(out.ok, isTrue, reason: log.join('\n'));
    expect(board.slot0, McuImageInfo.parse(newM7).hash);
  });
}
