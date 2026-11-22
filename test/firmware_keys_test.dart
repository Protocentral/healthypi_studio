import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/firmware/keys.dart';

// secp256r1 (NIST P-256): y² = x³ − 3x + b (mod p).
final _p = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16);
final _b = BigInt.parse(
    '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
    radix: 16);

bool _onP256(String hex) {
  final x = BigInt.parse(hex.substring(2, 66), radix: 16);
  final y = BigInt.parse(hex.substring(66), radix: 16);
  final lhs = (y * y) % _p;
  final rhs = (x * x * x - BigInt.from(3) * x + _b) % _p;
  return lhs == rhs;
}

void main() {
  test('release builds trust the two release keys and nothing else', () {
    expect(releaseFirmwareKeys, [releaseFirmwareKey, releaseBackupFirmwareKey]);
    expect(releaseFirmwareKeys.any((k) => k.development), isFalse);
  });

  test('the development key is trusted only in a debug build', () {
    // Tests run in debug mode, so here it is present; a release build drops
    // it through kDebugMode.
    expect(trustedFirmwareKeys, [...releaseFirmwareKeys, developmentFirmwareKey]);
    expect(developmentFirmwareKey.development, isTrue);
  });

  test('the release key points match healthypi-6-fw release_keys/', () {
    // Derived from the .pub.pem files with
    // openssl pkey -pubin -outform DER | tail -c 65 | xxd -p
    expect(
        releaseFirmwareKey.uncompressedPointHex,
        '04c16802580f9f6a9c2ac1c3377ab3c73a289acb1594f1ee8caf104c7d3e5b91388b'
        'f169338cfaefefdb0cced547f2ac8ec2952f2ddf479bf8540df4a500002dd0');
    expect(
        releaseBackupFirmwareKey.uncompressedPointHex,
        '043ff875a0e980848b650d1776ede95fd14d5a79e9e7e00d7295abd3c8e679532ad1'
        'a0532197c83374ac416837d7e8ac70f3abd916fa9e9a0e8f066abadfea077a');
  });

  for (final k in [...releaseFirmwareKeys, developmentFirmwareKey]) {
    test('${k.label} is an uncompressed point on P-256', () {
      expect(k.uncompressedPointHex, hasLength(130));
      expect(k.point, hasLength(65));
      expect(k.point.first, 0x04);
      expect(_onP256(k.uncompressedPointHex), isTrue);
    });
  }
}
