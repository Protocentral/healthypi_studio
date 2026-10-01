import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'keys.dart';

/// A `.hpifw` firmware bundle: one release for every processor on the board.
///
/// A zip of `manifest.json`, `manifest.sig` (raw 64-byte ECDSA-P256 `r || s`
/// over the SHA-256 of the manifest bytes exactly as stored) and one `.bin`
/// per image. Format reference: healthypi-6-fw `tools/healthypi/src/healthypi/
/// fw/bundle.py` and `docs/ARCHITECTURE.md` §10.
class FirmwareBundle {
  FirmwareBundle._({
    required this.manifest,
    required this.images,
    required this.signer,
  });

  /// Manifest `format` this reader understands.
  static const int formatVersion = 1;

  /// Order images are applied in. The C6 updates itself over Wi-Fi and is not
  /// applied by Studio.
  static const List<String> applyOrder = ['esp32c6', 'm4', 'm7'];

  final Map<String, dynamic> manifest;
  final Map<String, BundleImage> images;

  /// The key the manifest signature verified against.
  final TrustedKey signer;

  String get release => '${manifest['release'] ?? '?'}';
  String get product => '${manifest['product'] ?? '?'}';
  List<String> get hwRevisions =>
      (manifest['hw_rev'] as List?)?.map((e) => '$e').toList() ?? const [];

  /// Open and verify [zipBytes]: every image digest and size, then the
  /// manifest signature against [keys]. Throws [BundleException] on the first
  /// failure, saying what is wrong.
  static FirmwareBundle open(
    Uint8List zipBytes, {
    List<TrustedKey> keys = trustedFirmwareKeys,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    } catch (e) {
      throw BundleException('not a .hpifw bundle ($e)');
    }
    Uint8List? read(String name) {
      final f = archive.findFile(name);
      return f == null ? null : Uint8List.fromList(f.content);
    }

    final rawManifest = read('manifest.json');
    if (rawManifest == null) throw const BundleException('no manifest.json');
    final Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(rawManifest)) as Map<String, dynamic>;
    } catch (e) {
      throw BundleException('manifest.json is not valid JSON ($e)');
    }
    if (manifest['format'] != formatVersion) {
      throw BundleException('bundle format ${manifest['format']}; '
          'Studio understands $formatVersion');
    }
    if (manifest['product'] != 'healthypi6') {
      throw BundleException(
          'bundle is for "${manifest['product']}", not HealthyPi 6');
    }

    final images = <String, BundleImage>{};
    final entries = (manifest['images'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final e in entries.entries) {
      final m = (e.value as Map).cast<String, dynamic>();
      final data = read('${m['file']}');
      if (data == null) {
        throw BundleException('${e.key}: ${m['file']} is missing from the bundle');
      }
      final got = crypto.sha256.convert(data).toString();
      if (got != m['sha256']) {
        throw BundleException('${e.key}: digest mismatch — the bundle is corrupt');
      }
      if (data.length != m['size']) {
        throw BundleException('${e.key}: size mismatch — the bundle is corrupt');
      }
      final sigHex = m['sig'] as String?;
      images[e.key] = BundleImage(
        name: e.key,
        version: '${m['version']}',
        transport: '${m['transport']}',
        data: data,
        signature: sigHex == null ? null : _hex(sigHex),
      );
    }
    if (images.isEmpty) throw const BundleException('bundle has no images');

    final sig = read('manifest.sig');
    if (sig == null) throw const BundleException('bundle is unsigned');
    final digest =
        Uint8List.fromList(crypto.sha256.convert(rawManifest).bytes);
    final signer = keys.cast<TrustedKey?>().firstWhere(
          (k) => verifyP256(k!.point, digest, sig),
          orElse: () => null,
        );
    if (signer == null) {
      throw const BundleException(
          'manifest signature does not verify against any key Studio trusts');
    }
    return FirmwareBundle._(manifest: manifest, images: images, signer: signer);
  }
}

/// One processor's image inside a bundle.
class BundleImage {
  const BundleImage({
    required this.name,
    required this.version,
    required this.transport,
    required this.data,
    this.signature,
  });

  /// `m7`, `m4` or `esp32c6`.
  final String name;
  final String version;

  /// `mcumgr-img`, `hpi-g64` or `esp-ota-http`.
  final String transport;
  final Uint8List data;

  /// Raw 64-byte `r || s` over the image's SHA-256 (the M4 carries one).
  final Uint8List? signature;
}

class BundleException implements Exception {
  const BundleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// ECDSA-P256 verify of a raw `r || s` [signature] over an already-computed
/// SHA-256 [digest], against a 65-byte uncompressed [publicKey].
bool verifyP256(Uint8List publicKey, Uint8List digest, Uint8List signature) {
  if (signature.length != 64) return false;
  try {
    final domain = ECDomainParameters('secp256r1');
    final q = domain.curve.decodePoint(publicKey);
    if (q == null) return false;
    BigInt big(Uint8List b) =>
        BigInt.parse(b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
            radix: 16);
    // No digest on the signer: the message is already the SHA-256.
    final signer = ECDSASigner()
      ..init(false, PublicKeyParameter(ECPublicKey(q, domain)));
    return signer.verifySignature(
      digest,
      ECSignature(big(signature.sublist(0, 32)), big(signature.sublist(32))),
    );
  } catch (_) {
    return false;
  }
}

Uint8List _hex(String hex) => Uint8List.fromList([
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
