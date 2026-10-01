/// `.HP6` DBLK wire constants, format `0x0300`.
///
/// Mirrors `app_m7/src/core/sample_formats.h` and `docs/HP6_DATA_FORMAT.md` in
/// the firmware repo. Hand-copied for now; the protocol generator replaces this
/// file once the firmware catalog can export struct layouts.
library;

/// DBLK frame: 28-byte header, payload, trailing CRC-32.
const int dblkHeaderLen = 28;
const int dblkCrcLen = 4;
const int dblkOverhead = dblkHeaderLen + dblkCrcLen;

/// DBLK channel ids (header byte 20).
abstract final class Hp6Channel {
  static const int ecg = 1;
  static const int ppg = 2;
  static const int resp = 3; // rides inside ECG; never sent as its own block
  static const int vitals = 4;
  static const int eeg = 5;
  static const int event = 6;
  static const int sync = 7; // files only
  static const int infer = 8;
}

/// Size in bytes of one sample struct per channel. A block whose payload does
/// not divide into these is rejected.
const Map<int, int> hp6SampleSize = {
  Hp6Channel.ecg: 20,
  Hp6Channel.ppg: 12,
  Hp6Channel.vitals: 16,
  Hp6Channel.eeg: 36,
  Hp6Channel.event: 8,
  Hp6Channel.sync: 40,
  Hp6Channel.infer: 16,
};

/// `hp6_ecg_sample.lead_off` — electrode terms, bit set = electrode off.
/// V1 is not detected on the current board.
abstract final class Hp6LeadOff {
  static const int ra = 0x01;
  static const int la = 0x02;
  static const int ll = 0x04;
  static const int v1 = 0x08;
}

/// `hp6_vitals.flags` — HR provenance and quality.
abstract final class Hp6VitalsFlag {
  /// `hr_bpm` is a PPG pulse rate. Never present it as an ECG heart rate.
  static const int hrFromPpg = 0x01;
  static const int ecgLeadOff = 0x02;
  static const int ppgWeak = 0x04;
  static const int motion = 0x08;
}

/// `hp6_infer_sample.flags`.
abstract final class Hp6InferFlag {
  /// Not a real inference. Never present as a result.
  static const int stub = 0x01;
  static const int lowConf = 0x02;
  static const int ecgSuspect = 0x04;
}
