import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/firmware/bundle.dart';
import 'package:healthypi_studio/services/firmware/firmware_updater.dart';

import 'support/test_bundles.dart';

void main() {
  final signer = TestSigner();
  final m4 = Uint8List.fromList(List<int>.generate(1000, (i) => i & 0xFF));
  final m7 = buildMcuImage();

  group('bundle', () {
    test('a correctly signed bundle opens, with every image', () {
      final b = FirmwareBundle.open(
        buildBundle(signer, {'m4': ('1.0.2', m4), 'm7': ('1.0.2', m7)}),
        keys: [signer.key],
      );
      expect(b.release, '1.0.2');
      expect(b.images.keys, containsAll(['m4', 'm7']));
      expect(b.images['m4']!.signature, hasLength(64));
      expect(b.images['m7']!.data, m7);
    });

    test('a bundle signed by an unknown key is refused', () {
      final other = TestSigner(2);
      expect(
        () => FirmwareBundle.open(buildBundle(other, {'m4': ('1.0.2', m4)}),
            keys: [signer.key]),
        throwsA(isA<BundleException>().having(
            (e) => e.message, 'message', contains('does not verify'))),
      );
    });

    test('one flipped byte in m4.bin is caught by its digest', () {
      final zip = buildBundle(signer, {'m4': ('1.0.2', m4)},
          mutate: (files) => files['m4.bin']![10] ^= 0x01);
      expect(
        () => FirmwareBundle.open(zip, keys: [signer.key]),
        throwsA(isA<BundleException>()
            .having((e) => e.message, 'message', contains('digest mismatch'))),
      );
    });

    test('an edited manifest no longer verifies', () {
      final zip = buildBundle(signer, {'m4': ('1.0.2', m4)}, mutate: (files) {
        final s = String.fromCharCodes(files['manifest.json']!)
            .replaceFirst('"release": "1.0.2"', '"release": "9.9.9"');
        files['manifest.json'] = Uint8List.fromList(s.codeUnits);
      });
      expect(() => FirmwareBundle.open(zip, keys: [signer.key]),
          throwsA(isA<BundleException>()));
    });

    test('an unsigned bundle is refused', () {
      final zip = buildBundle(signer, {'m4': ('1.0.2', m4)},
          mutate: (files) => files.remove('manifest.sig'));
      expect(
        () => FirmwareBundle.open(zip, keys: [signer.key]),
        throwsA(isA<BundleException>()
            .having((e) => e.message, 'message', contains('unsigned'))),
      );
    });

    test('bundles are recognised by content, not extension', () {
      final zip = buildBundle(signer, {'m4': ('1.0.2', m4)});
      expect(FirmwareBundle.looksLikeBundle(zip), isTrue);
      expect(FirmwareBundle.looksLikeBundle(m7), isFalse); // MCUboot image
    });

    test('a file that is not a zip is refused', () {
      expect(() => FirmwareBundle.open(Uint8List(100), keys: [signer.key]),
          throwsA(isA<BundleException>()));
    });
  });

  group('extracted folder', () {
    late Directory dir;

    /// Unzip a bundle the way a browser would.
    Directory extract(Uint8List zip) {
      final d = Directory.systemTemp.createTempSync('hpi_bundle_');
      for (final f in ZipDecoder().decodeBytes(zip)) {
        File('${d.path}/${f.name}').writeAsBytesSync(f.content);
      }
      return d;
    }

    setUp(() => dir = extract(
        buildBundle(signer, {'m4': ('1.0.2', m4), 'm7': ('1.0.2', m7)})));
    tearDown(() => dir.deleteSync(recursive: true));

    test('verifies exactly as the zip does', () {
      final b = FirmwareBundle.openDirectory(dir.path, keys: [signer.key]);
      expect(b.release, '1.0.2');
      expect(b.images['m7']!.data, m7);
    });

    test('a tampered image fails its digest', () {
      final f = File('${dir.path}/m4.bin');
      final bytes = f.readAsBytesSync()..[5] ^= 0x01;
      f.writeAsBytesSync(bytes);
      expect(
        () => FirmwareBundle.openDirectory(dir.path, keys: [signer.key]),
        throwsA(isA<BundleException>()
            .having((e) => e.message, 'message', contains('digest mismatch'))),
      );
    });

    test('a missing image is named', () {
      File('${dir.path}/m7.bin').deleteSync();
      expect(
        () => FirmwareBundle.openDirectory(dir.path, keys: [signer.key]),
        throwsA(isA<BundleException>()
            .having((e) => e.message, 'message', contains('missing'))),
      );
    });

    test('a manifest member outside the folder is refused', () {
      // Re-sign a manifest whose m4 entry points up and out of the folder.
      final manifest = jsonDecode(
          File('${dir.path}/manifest.json').readAsStringSync()) as Map;
      (manifest['images'] as Map)['m4']['file'] = '../m4.bin';
      final raw = utf8.encode(jsonEncode(manifest));
      File('${dir.path}/manifest.json').writeAsBytesSync(raw);
      File('${dir.path}/manifest.sig').writeAsBytesSync(signer.signDigest(
          crypto.sha256.convert(raw).bytes));
      expect(
        () => FirmwareBundle.openDirectory(dir.path, keys: [signer.key]),
        throwsA(isA<BundleException>()
            .having((e) => e.message, 'message', contains('outside'))),
      );
    });
  });

  group('versions', () {
    test('suffixes are a build flavour, not an ordering', () {
      expect(sameVersion('1.0.2-dev', '1.0.2'), isTrue);
      expect(sameVersion('1.0.2', '1.0.3'), isFalse);
      expect(sameVersion('', '1.0.2'), isFalse); // unknown always applies
    });

    test('an older M7 is refused before upload', () {
      expect(m7Downgrade('1.0.2', '1.0.1'), contains('older'));
      expect(m7Downgrade('1.0.2', '1.0.2'), isNull);
      expect(m7Downgrade('1.0.2', '1.1.0'), isNull);
      expect(m7Downgrade('', '1.0.0'), isNull); // unknown installed
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    });
  });
}
