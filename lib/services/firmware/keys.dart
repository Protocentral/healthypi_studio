/// Public keys Studio accepts as signers of a firmware bundle manifest.
///
/// One ECDSA-P256 keypair signs the M7 image (checked by MCUboot), the M4 image
/// (checked by the M7 at commit) and the bundle manifest (checked here). Only
/// the public half belongs in Studio.
///
/// RELEASE BLOCKER: this list holds only the development key that signed the
/// bench bundles (healthypi-6-fw `keys/hp6_dev_ec256.pem`, which is generated
/// per build machine). Add the production key, as a 65-byte uncompressed
/// point, before a public release, and decide whether the dev key stays
/// trusted in release builds.
library;

import 'dart:typed_data';

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

const List<TrustedKey> trustedFirmwareKeys = [
  TrustedKey(
    'HealthyPi 6 development key',
    '0477ea47d0f2fab15370d2bb7ad68b38fbd52ee7def6fd992cb8a2388c30c1d6de'
        '735bc8f46d0d6d770cd47d3a3042ef748a51b18a92cdbb2cdb6b1c8efb952497',
    development: true,
  ),
];
