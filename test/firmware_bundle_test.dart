import 'dart:typed_data';

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

    test('a file that is not a zip is refused', () {
      expect(() => FirmwareBundle.open(Uint8List(100), keys: [signer.key]),
          throwsA(isA<BundleException>()));
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
