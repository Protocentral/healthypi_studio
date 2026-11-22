/// Public keys Studio accepts as signers of a firmware bundle manifest.
///
/// One ECDSA-P256 keypair signs the M7 image (checked by MCUboot), the M4 image
/// (checked by the M7 at commit), the ESP32-C6 image (checked by the M7 at
/// `espfw_begin`) and the bundle manifest (checked here). Only the public half
/// belongs in Studio.
///
/// Release builds of Studio trust the two HealthyPi 6 release keys and nothing
/// else. They are the public keys in healthypi-6-fw
/// `tools/healthypi/src/healthypi/fw/release_keys/`, whose full SHA-256
/// fingerprints are in that repo's `.github/SECURITY.md`. Re-derive a point
/// with `openssl pkey -pubin -in <key>.pub.pem -outform DER | tail -c 65 | xxd -p`.
///
/// The backup key signs nothing today. It is trusted so that firmware releases
/// can move to it, if the primary is lost or revoked, without waiting for a
/// Studio release.
///
/// The development key (healthypi-6-fw `keys/hp6_dev_ec256.pem`) signs bench
/// bundles. It is trusted only in debug builds of Studio, never in a release
/// build, the same default as the `healthypi` CLI (which needs `--pubkey` for
/// a dev bundle).
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;

class TrustedKey {
  const TrustedKey(this.label, this.uncompressedPointHex,
      {this.development = false});

  final String label;

  /// `04 || X || Y`, 65 bytes, as hex.
  final String uncompressedPointHex;

  /// Signs bench and development builds, not releases.
  final bool development;

  Uint8List get point {
    final hex = uncompressedPointHex;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
}

/// Fingerprint `d57c8c67387cc57e`.
const TrustedKey releaseFirmwareKey = TrustedKey(
  'HealthyPi 6 release key',
  '04c16802580f9f6a9c2ac1c3377ab3c73a289acb1594f1ee8caf104c7d3e5b9138'
      '8bf169338cfaefefdb0cced547f2ac8ec2952f2ddf479bf8540df4a500002dd0',
);

/// Fingerprint `00ceeec92c5d119b`.
const TrustedKey releaseBackupFirmwareKey = TrustedKey(
  'HealthyPi 6 release key (backup)',
  '043ff875a0e980848b650d1776ede95fd14d5a79e9e7e00d7295abd3c8e679532a'
      'd1a0532197c83374ac416837d7e8ac70f3abd916fa9e9a0e8f066abadfea077a',
);

const TrustedKey developmentFirmwareKey = TrustedKey(
  'HealthyPi 6 development key',
  '0477ea47d0f2fab15370d2bb7ad68b38fbd52ee7def6fd992cb8a2388c30c1d6de'
      '735bc8f46d0d6d770cd47d3a3042ef748a51b18a92cdbb2cdb6b1c8efb952497',
  development: true,
);

/// The keys a release build trusts.
const List<TrustedKey> releaseFirmwareKeys = [
  releaseFirmwareKey,
  releaseBackupFirmwareKey,
];

/// The keys this build trusts: the release keys, plus the development key in
/// a debug build.
const List<TrustedKey> trustedFirmwareKeys = [
  ...releaseFirmwareKeys,
  if (kDebugMode) developmentFirmwareKey,
];
