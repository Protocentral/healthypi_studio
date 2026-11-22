import 'dart:typed_data';

/// A UF2 firmware file, checked before anything is sent to the board.
///
/// UF2 is a sequence of 512-byte blocks, each carrying up to 476 payload bytes
/// with its target address and a family id. The HealthyPi Core is an RP2350,
/// whose boot ROM accepts the RP2350 families below; a file built for an
/// RP2040 (or another chip) is refused here rather than by the ROM after the
/// board has already been rebooted into BOOTSEL.
class Uf2Image {
  Uf2Image._(this.bytes, this.blockCount, this.payloadBytes, this.families);

  static const int blockSize = 512;
  static const int magicStart0 = 0x0A324655; // "UF2\n"
  static const int magicStart1 = 0x9E5D5157;
  static const int magicEnd = 0x0AB16F30;
  static const int flagFamilyIdPresent = 0x00002000;

  /// RP2350 family ids (pico-sdk `boot/uf2.h`). `absolute` is the family
  /// picotool uses for a raw image that must not be moved.
  static const int familyRp2040 = 0xE48BFF56;
  static const int familyAbsolute = 0xE48BFF57;
  static const int familyDataOnly = 0xE48BFF58;
  static const int familyRp2350ArmS = 0xE48BFF59;
  static const int familyRp2350RiscV = 0xE48BFF5A;
  static const int familyRp2350ArmNs = 0xE48BFF5B;

  static const Set<int> rp2350Families = {
    familyAbsolute,
    familyDataOnly,
    familyRp2350ArmS,
    familyRp2350RiscV,
    familyRp2350ArmNs,
  };

  final Uint8List bytes;
  final int blockCount;

  /// Bytes the file writes to flash.
  final int payloadBytes;

  /// Every family id the blocks declare.
  final Set<int> families;

  bool get isRp2350 => families.isNotEmpty && families.every(rp2350Families.contains);

  /// Quick sniff: does [bytes] start like a UF2 block?
  static bool looksLikeUf2(List<int> bytes) {
    if (bytes.length < 8) return false;
    final b = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 8)));
    return b.getUint32(0, Endian.little) == magicStart0 &&
        b.getUint32(4, Endian.little) == magicStart1;
  }

  /// Parse and check every block. Throws [FormatException] for a file that is
  /// not a well-formed UF2 or not built for an RP2350.
  static Uf2Image parse(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length % blockSize != 0) {
      throw const FormatException('not a UF2 file (length is not a multiple '
          'of 512 bytes)');
    }
    final data = ByteData.sublistView(bytes);
    final count = bytes.length ~/ blockSize;
    final families = <int>{};
    var payload = 0;
    for (var i = 0; i < count; i++) {
      final o = i * blockSize;
      if (data.getUint32(o, Endian.little) != magicStart0 ||
          data.getUint32(o + 4, Endian.little) != magicStart1 ||
          data.getUint32(o + 508, Endian.little) != magicEnd) {
        throw FormatException('not a UF2 file (block $i has a bad magic)');
      }
      final flags = data.getUint32(o + 8, Endian.little);
      final size = data.getUint32(o + 16, Endian.little);
      if (size > 476) {
        throw FormatException('block $i claims $size payload bytes (max 476)');
      }
      payload += size;
      if (flags & flagFamilyIdPresent != 0) {
        families.add(data.getUint32(o + 28, Endian.little));
      }
    }
    final img = Uf2Image._(bytes, count, payload, families);
    if (!img.isRp2350) {
      final named = families.isEmpty
          ? 'no family id'
          : families.map((f) => '0x${f.toRadixString(16)}').join(', ');
      throw FormatException(families.contains(familyRp2040)
          ? 'built for an RP2040, not the HealthyPi Core\'s RP2350'
          : 'not built for an RP2350 ($named)');
    }
    return img;
  }
}
