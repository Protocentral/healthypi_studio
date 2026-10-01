// Builds signed .hpifw bundles and imgtool-shaped MCUboot images for tests,
// with a throwaway P-256 key.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:healthypi_studio/services/firmware/keys.dart';
import 'package:pointycastle/export.dart';

class TestSigner {
  TestSigner([int seed = 1]) {
    final rnd = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(
          List<int>.generate(32, (i) => (i * 31 + seed) & 0xFF))));
    _random = rnd;
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
          ECKeyGeneratorParameters(ECDomainParameters('secp256r1')), rnd));
    final pair = gen.generateKeyPair();
    _private = pair.privateKey;
    final q = pair.publicKey.Q!;
    point = q.getEncoded(false);
  }

  late final SecureRandom _random;
  late final ECPrivateKey _private;
  late final Uint8List point;

  TrustedKey get key => TrustedKey('test key',
      point.map((b) => b.toRadixString(16).padLeft(2, '0')).join());

  /// Raw `r || s` over an already-computed digest.
  Uint8List signDigest(List<int> digest) {
    final signer = ECDSASigner()
      ..init(true, ParametersWithRandom(PrivateKeyParameter(_private), _random));
    final sig = signer.generateSignature(Uint8List.fromList(digest)) as ECSignature;
    Uint8List be(BigInt v) {
      final hex = v.toRadixString(16).padLeft(64, '0');
      return Uint8List.fromList([
        for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
    }

    return Uint8List.fromList([...be(sig.r), ...be(sig.s)]);
  }
}

/// A `.hpifw` zip. [images] maps name → (version, bytes); the M4 entry gets an
/// image signature. [mutate] may edit the archive files after signing.
Uint8List buildBundle(
  TestSigner signer,
  Map<String, (String, Uint8List)> images, {
  String release = '1.0.2',
  void Function(Map<String, Uint8List> files)? mutate,
}) {
  final manifestImages = <String, Object?>{};
  final files = <String, Uint8List>{};
  for (final e in images.entries) {
    final (version, data) = e.value;
    final digest = crypto.sha256.convert(data).bytes;
    manifestImages[e.key] = {
      'file': '${e.key}.bin',
      'sha256': crypto.sha256.convert(data).toString(),
      'size': data.length,
      'transport': e.key == 'm7' ? 'mcumgr-img' : 'hpi-g64',
      'version': version,
      if (e.key == 'm4')
        'sig': signer
            .signDigest(digest)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
    };
    files['${e.key}.bin'] = data;
  }
  final manifest = utf8.encode(const JsonEncoder.withIndent('  ').convert({
    'format': 1,
    'product': 'healthypi6',
    'release': release,
    'hw_rev': ['v5'],
    'images': manifestImages,
  }));
  files['manifest.json'] = Uint8List.fromList(manifest);
  files['manifest.sig'] =
      signer.signDigest(crypto.sha256.convert(manifest).bytes);
  mutate?.call(files);

  final archive = Archive();
  for (final f in files.entries) {
    archive.addFile(ArchiveFile.bytes(f.key, f.value));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// An imgtool-shaped MCUboot image with a SHA-256 TLV and a dummy signature.
Uint8List buildMcuImage({
  (int, int, int) version = (1, 0, 2),
  int payloadSize = 600,
  int seed = 0,
}) {
  const headerSize = 0x200;
  final rnd = Random(seed);
  final payload = List<int>.generate(payloadSize, (_) => rnd.nextInt(256));
  final hdr = ByteData(headerSize)
    ..setUint32(0, 0x96F3B83D, Endian.little)
    ..setUint16(8, headerSize, Endian.little)
    ..setUint32(12, payload.length, Endian.little)
    ..setUint8(20, version.$1)
    ..setUint8(21, version.$2)
    ..setUint16(22, version.$3, Endian.little);
  final body = BytesBuilder()
    ..add(hdr.buffer.asUint8List())
    ..add(payload);
  final hash = crypto.sha256.convert(body.toBytes()).bytes;
  Uint8List tlv(int type, List<int> v) {
    final b = ByteData(4 + v.length)
      ..setUint16(0, type, Endian.little)
      ..setUint16(2, v.length, Endian.little);
    final out = b.buffer.asUint8List();
    out.setRange(4, out.length, v);
    return out;
  }

  final entries = [tlv(0x10, hash), tlv(0x22, List<int>.filled(72, 1))];
  final total = 4 + entries.fold<int>(0, (n, e) => n + e.length);
  final info = ByteData(4)
    ..setUint16(0, 0x6907, Endian.little)
    ..setUint16(2, total, Endian.little);
  body.add(info.buffer.asUint8List());
  for (final e in entries) {
    body.add(e);
  }
  return body.toBytes();
}
