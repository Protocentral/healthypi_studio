import 'dart:async';
import 'package:flutter/foundation.dart';

import '../protocol/hp6_formats.dart';

/// OpenView packet constants - Dynamic packet structure with length autodetection
///
/// Supports two protocol versions:
///
/// v1 Format (46 bytes total, 39-byte payload):
/// - Bytes 0-1: Header [0x0A, 0xFA]
/// - Byte 2: Data length = 0x27 (39)
/// - Byte 3: Reserved = 0x00 (indicates v1)
/// - Byte 4: Type indicator (0x02)
/// - Bytes 5-43: Payload data (39 bytes)
/// - Bytes 44-45: Footer [0x00, 0x0B]
///
/// v2 Format (50 bytes total, 43-byte payload):
/// - Bytes 0-1: Header [0x0A, 0xFA]
/// - Byte 2: Data length = 0x2B (43)
/// - Byte 3: Version = 0x02 (indicates v2)
/// - Byte 4: Type indicator (0x02)
/// - Bytes 5-8: Sequence number (uint32_le)
/// - Bytes 9-47: Payload data (39 bytes, same as v1 but offset +4)
/// - Bytes 48-49: Footer [0x00, 0x0B]
class OpenViewConstants {
  static const int packetHeaderByte1 = 0x0A;
  static const int packetHeaderByte2 = 0xFA;
  static const int reservedByte = 0x00;
  static const int dataTypeIndicator = 0x02;
  static const List<int> packetFooter = [0x00, 0x0B];

  // Fixed header and footer sizes
  static const int packetHeaderLength = 5;
  static const int packetFooterLength = 2;

  // Data length byte position in packet header
  static const int dataLengthByteIndex = 2;

  // Version byte position (byte 3)
  static const int versionByteIndex = 3;

  // Protocol version identifiers
  static const int protocolV1Marker = 0x00;  // Byte 3 = 0x00 for v1
  static const int protocolV2Marker = 0x02;  // Byte 3 = 0x02 for v2

  // Payload lengths for each version
  static const int v1PayloadLength = 0x27;  // 39 bytes
  static const int v2PayloadLength = 0x2B;  // 43 bytes (39 + 4 for sequence)

  // Total packet lengths
  static const int v1PacketLength = 46;  // 5 + 39 + 2
  static const int v2PacketLength = 50;  // 5 + 43 + 2

  // Minimum packet: header(5) + length(1) + footer(2) = 8 bytes minimum
  static const int minPacketLength = 8;
  static const int maxPacketLength = 1024;

  // HRV packet constants (type 0x03)
  static const int hrvPacketType = 0x03;
  static const int hrvPayloadLength = 0x14;  // 20 bytes
  static const int hrvPacketLength = 27;      // 5 + 20 + 2

  // EEG packet constants (type 0x04)
  // NOTE: EEG packet format is different - length byte INCLUDES footer
  static const int eegPacketType = 0x04;
  static const int eegPayloadLength = 0x2E;  // 46 bytes (includes 2-byte footer in this count!)
  static const int eegPacketLength = 51;      // 5 + 46 = 51 (footer is part of payload length)
  static const int eegChannelCount = 8;
  static const int eegSamplingRate = 250;    // Hz

  /// Calculate total packet length given payload length
  /// For most packets: Total = header(5) + payload(N) + footer(2)
  /// For EEG packets: Total = header(5) + payload(N) where payload includes footer
  static int getTotalPacketLength(int payloadLength) {
    // EEG packets have footer included in the payload length byte
    if (payloadLength == eegPayloadLength) {
      return 5 + payloadLength; // 5 + 46 = 51
    }
    return 5 + payloadLength + 2;
  }

  /// Detect protocol version from packet bytes
  /// Returns 1 for v1, 2 for v2, or 0 if unknown
  static int detectProtocolVersion(List<int> packet) {
    if (packet.length < 4) return 0;

    final length = packet[dataLengthByteIndex];
    final version = packet[versionByteIndex];

    if (version == protocolV2Marker && length == v2PayloadLength) {
      return 2;  // v2 format (50 bytes)
    } else if (version == protocolV1Marker && length == v1PayloadLength) {
      return 1;  // v1 format (46 bytes)
    }

    // Fall back to length-based detection for legacy compatibility
    if (length == v1PayloadLength) return 1;
    if (length == v2PayloadLength) return 2;

    return 0;  // Unknown
  }
}

/// Data model for HealthyPi sensor readings (vitals only)
class HealthyPiData {
  final double heartRate;
  final double spo2;
  final double temperature;
  final double respirationRate;
  final DateTime timestamp;

  HealthyPiData({
    required this.heartRate,
    required this.spo2,
    required this.temperature,
    required this.respirationRate,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'HealthyPiData(HR: $heartRate bpm, SpO2: $spo2%, RR: $respirationRate brpm, Temp: $temperature°C)';
  }
}

/// OpenView packet data - supports v1 (46-byte) and v2 (50-byte) formats
class OpenViewData {
  final List<int> rawPayload;

  // Protocol version (1 or 2)
  final int protocolVersion;

  // Sequence number (v2 only, 0 for v1)
  final int sequenceNumber;

  // ECG signals (32-bit signed)
  final int ecg1;
  final int ecg2;
  final int ecg3;

  // Respiration/BioZ signal (32-bit signed)
  final int respiration;

  // PPG signals (32-bit signed)
  final int ppgRed;
  final int ppgIr;
  final bool ppgValid;

  // Vital signs
  final int heartRate;
  final int spo2;
  final int respirationRate;
  final double temperature;

  // ADC extension channels (32-bit signed)
  final int adcChannel1; // INP14/PA2
  final int adcChannel2; // INP15/PA3

  /// `hp6_vitals.flags` from the last VITALS block (`Hp6VitalsFlag`). 0 when
  /// the source does not report it.
  final int vitalsFlags;

  /// `hp6_ecg_sample.lead_off` for this sample (`Hp6LeadOff` electrode mask).
  final int ecgLeadOff;

  final DateTime timestamp;

  OpenViewData({
    required this.rawPayload,
    this.protocolVersion = 1,
    this.sequenceNumber = 0,
    required this.ecg1,
    required this.ecg2,
    required this.ecg3,
    required this.respiration,
    required this.ppgRed,
    required this.ppgIr,
    required this.ppgValid,
    required this.heartRate,
    required this.spo2,
    required this.respirationRate,
    required this.temperature,
    required this.adcChannel1,
    required this.adcChannel2,
    this.vitalsFlags = 0,
    this.ecgLeadOff = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// The heart rate is a PPG pulse rate, not an ECG rate.
  bool get hrFromPpg => (vitalsFlags & Hp6VitalsFlag.hrFromPpg) != 0;

  /// At least one ECG electrode is off; the device gates the ECG heart rate.
  bool get ecgLeadsOff =>
      (vitalsFlags & Hp6VitalsFlag.ecgLeadOff) != 0 || ecgLeadOff != 0;

  /// Low PPG perfusion or finger off: SpO₂ and a PPG heart rate are provisional.
  bool get ppgWeak => (vitalsFlags & Hp6VitalsFlag.ppgWeak) != 0;

  /// Whether this packet has a valid sequence number (v2 only)
  bool get hasSequenceNumber => protocolVersion >= 2;

  /// Convert to vitals-only data for backward compatibility
  HealthyPiData toHealthyPiData() {
    return HealthyPiData(
      heartRate: heartRate.toDouble(),
      spo2: spo2.toDouble(),
      respirationRate: respirationRate.toDouble(),
      temperature: temperature,
      timestamp: timestamp,
    );
  }

  @override
  String toString() {
    final seqStr = hasSequenceNumber ? ', Seq: $sequenceNumber' : '';
    return 'OpenViewData(v$protocolVersion$seqStr, ECG1: $ecg1, ECG2: $ecg2, ECG3: $ecg3, '
           'Resp: $respiration, PPG: R=$ppgRed/IR=$ppgIr (valid=$ppgValid), '
           'HR: $heartRate bpm, SpO2: $spo2%, RR: $respirationRate brpm, Temp: $temperature°C)';
  }
}

/// HRV packet data from HealthyPi 6 (27-byte packets at ~0.2 Hz)
///
/// Contains pre-computed HRV metrics from the device:
/// - Time-domain metrics: SDNN, RMSSD, pNN50
/// - Heart rate and R-R interval data
/// - Signal quality and validity indicators
/// - Arrhythmia detection flags
class HRVPacketData {
  final List<int> rawPayload;

  /// Device uptime in milliseconds when HRV metrics were calculated
  final int timestampMs;

  /// Heart rate in BPM. Check [hrFromPpg]: the device may report a PPG pulse
  /// rate here, and that must not be presented as an ECG rate.
  final int heartRate;

  /// Most recent R-R interval in milliseconds. 0 = not reported; the `.HP6`
  /// VITALS block carries no beat-to-beat intervals.
  final int rrIntervalMs;

  /// Standard Deviation of NN intervals in milliseconds
  /// Interpretation: <50ms low, 50-100ms normal, >100ms high
  final int sdnnMs;

  /// Root Mean Square of Successive Differences in milliseconds
  /// Reflects parasympathetic activity: <20ms low, 20-50ms normal, >50ms high
  final int rmssdMs;

  /// Percentage of successive R-R intervals differing by >50ms (0-100)
  /// Interpretation: <3% low, 3-25% normal, >25% high
  final int pnn50;

  /// ECG signal quality indicator (0-100%)
  /// 0-30%: poor, 30-70%: acceptable, 70-100%: good
  final int signalQuality;

  /// Whether HRV data is valid (false = learning phase, insufficient R-R intervals)
  final bool hrvValid;

  /// Bit flags for detected arrhythmias
  /// Bit 3 (0x08): Bradycardia (HR < 60 BPM)
  /// Bit 4 (0x10): Tachycardia (HR > 100 BPM)
  final int arrhythmiaFlags;

  /// Mean R-R interval in milliseconds (from RR buffer, up to 64 samples)
  final int meanRrMs;

  /// LF/HF ratio × 10. 0 = not computed.
  final int lfHfX10;

  /// `hp6_vitals.flags` (`Hp6VitalsFlag`).
  final int vitalsFlags;

  /// Local timestamp when packet was received
  final DateTime timestamp;

  HRVPacketData({
    required this.rawPayload,
    required this.timestampMs,
    required this.heartRate,
    required this.rrIntervalMs,
    required this.sdnnMs,
    required this.rmssdMs,
    required this.pnn50,
    required this.signalQuality,
    required this.hrvValid,
    required this.arrhythmiaFlags,
    required this.meanRrMs,
    this.lfHfX10 = 0,
    this.vitalsFlags = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// LF/HF ratio, or null when the device has not computed it.
  double? get lfHf => lfHfX10 == 0 ? null : lfHfX10 / 10.0;

  bool get hrFromPpg => (vitalsFlags & Hp6VitalsFlag.hrFromPpg) != 0;
  bool get ecgLeadOff => (vitalsFlags & Hp6VitalsFlag.ecgLeadOff) != 0;
  bool get ppgWeak => (vitalsFlags & Hp6VitalsFlag.ppgWeak) != 0;
  bool get motion => (vitalsFlags & Hp6VitalsFlag.motion) != 0;

  /// Returns true if bradycardia (HR < 60 BPM) is detected
  bool get bradycardia => (arrhythmiaFlags & 0x08) != 0;

  /// Returns true if tachycardia (HR > 100 BPM) is detected
  bool get tachycardia => (arrhythmiaFlags & 0x10) != 0;

  /// Returns true if any arrhythmia is detected
  bool get hasArrhythmia => arrhythmiaFlags != 0;

  /// Get SDNN quality level: 'low', 'normal', or 'high'
  String get sdnnLevel {
    if (sdnnMs < 50) return 'low';
    if (sdnnMs <= 100) return 'normal';
    return 'high';
  }

  /// Get RMSSD quality level: 'low', 'normal', or 'high'
  String get rmssdLevel {
    if (rmssdMs < 20) return 'low';
    if (rmssdMs <= 50) return 'normal';
    return 'high';
  }

  /// Get pNN50 quality level: 'low', 'normal', or 'high'
  String get pnn50Level {
    if (pnn50 < 3) return 'low';
    if (pnn50 <= 25) return 'normal';
    return 'high';
  }

  /// Get signal quality level: 'poor', 'acceptable', or 'good'
  String get signalQualityLevel {
    if (signalQuality < 30) return 'poor';
    if (signalQuality < 70) return 'acceptable';
    return 'good';
  }

  @override
  String toString() {
    final validStr = hrvValid ? 'valid' : 'learning';
    final arrhythmiaStr = hasArrhythmia
        ? ' [${bradycardia ? "BRADY" : ""}${tachycardia ? "TACHY" : ""}]'
        : '';
    return 'HRVPacketData($validStr, HR: $heartRate bpm, RR: $rrIntervalMs ms, '
           'SDNN: $sdnnMs ms, RMSSD: $rmssdMs ms, pNN50: $pnn50%, '
           'Quality: $signalQuality%$arrhythmiaStr)';
  }
}

/// One classified beat from a HealthyLink compute module (DBLK channel 8,
/// `hp6_infer_sample`). Samples flagged `Hp6InferFlag.stub` are dropped by the
/// parser and never reach this type.
class InferSample {
  /// Device uptime in ms (not session-relative).
  final int tsMs;
  final int modelId;

  /// AAMI class: 0 N, 1 S, 2 V, 3 F, 4 Q.
  final int classId;

  /// 0..255, the winning score rescaled.
  final int confidence;
  final List<int> scores;
  final int flags;

  const InferSample({
    required this.tsMs,
    required this.modelId,
    required this.classId,
    required this.confidence,
    required this.scores,
    required this.flags,
  });

  bool get lowConfidence => (flags & Hp6InferFlag.lowConf) != 0;
  bool get ecgSuspect => (flags & Hp6InferFlag.ecgSuspect) != 0;
}

/// EEG packet data from HealthyPi (51-byte packets at 250 Hz)
///
/// Contains 8-channel EEG data from ADS1299 ADC:
/// - 8 channels of 24-bit resolution EEG data (stored as microvolts)
/// - Lead-off detection for electrode connection status
/// - Signal quality indicator
/// - Sequence number for packet loss detection
class EEGPacketData {
  final List<int> rawPayload;

  /// Monotonic packet counter for loss detection
  final int sequenceNumber;

  /// Device uptime in milliseconds
  final int timestampMs;

  /// EEG channel values in microvolts (8 channels)
  /// Index 0-7 corresponds to channels 1-8
  final List<int> channels;

  /// Positive electrode lead-off status (bitmask)
  /// Bit N = 1 means channel N+1 positive electrode is disconnected
  final int leadOffPositive;

  /// Negative electrode lead-off status (bitmask)
  /// Bit N = 1 means channel N+1 negative electrode is disconnected
  final int leadOffNegative;

  /// Signal quality indicator (0-100%)
  final int signalQuality;

  /// Local timestamp when packet was received
  final DateTime timestamp;

  EEGPacketData({
    required this.rawPayload,
    required this.sequenceNumber,
    required this.timestampMs,
    required this.channels,
    required this.leadOffPositive,
    required this.leadOffNegative,
    required this.signalQuality,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Check if a specific channel (0-7) has both electrodes connected
  bool isChannelConnected(int channel) {
    if (channel < 0 || channel > 7) return false;
    final mask = 1 << channel;
    return (leadOffPositive & mask) == 0 && (leadOffNegative & mask) == 0;
  }

  /// Get the number of connected channels
  int get connectedChannelCount {
    int count = 0;
    for (int i = 0; i < 8; i++) {
      if (isChannelConnected(i)) count++;
    }
    return count;
  }

  /// Get list of disconnected channel indices (0-7)
  List<int> get disconnectedChannels {
    final result = <int>[];
    for (int i = 0; i < 8; i++) {
      if (!isChannelConnected(i)) result.add(i);
    }
    return result;
  }

  /// Get signal quality level: 'poor', 'acceptable', or 'good'
  String get signalQualityLevel {
    if (signalQuality < 30) return 'poor';
    if (signalQuality < 70) return 'acceptable';
    return 'good';
  }

  /// Get channel value by index (0-7), returns 0 if invalid
  int getChannel(int index) {
    if (index < 0 || index >= channels.length) return 0;
    return channels[index];
  }

  @override
  String toString() {
    final connectedStr = '${connectedChannelCount}/8 connected';
    final disconnected = disconnectedChannels;
    final disconnectedStr = disconnected.isEmpty
        ? ''
        : ' [off: ${disconnected.map((i) => i + 1).join(',')}]';
    return 'EEGPacketData(seq: $sequenceNumber, $connectedStr$disconnectedStr, '
           'quality: $signalQuality%, ch1: ${channels.isNotEmpty ? channels[0] : 0} µV)';
  }
}

/// Service for parsing and managing HealthyPi variable-length OpenView binary protocol data
/// with 38-byte biosignal payload (ECG, PPG, Respiration, and Vitals)
class DataParser extends ChangeNotifier {
  final List<HealthyPiData> _dataHistory = [];
  HealthyPiData? _currentData;
  OpenViewData? _currentOpenViewData;

  // Stream for broadcasting each parsed waveform packet to subscribers
  // This ensures NO packets are lost - each packet is delivered individually
  final _packetStreamController = StreamController<OpenViewData>.broadcast();
  Stream<OpenViewData> get packetStream => _packetStreamController.stream;

  // Stream for broadcasting HRV packets (~0.2 Hz)
  final _hrvStreamController = StreamController<HRVPacketData>.broadcast();
  Stream<HRVPacketData> get hrvStream => _hrvStreamController.stream;
  HRVPacketData? _currentHrvData;
  int _hrvPacketsReceived = 0;

  // Stream for broadcasting EEG packets (250 Hz)
  final _eegStreamController = StreamController<EEGPacketData>.broadcast();
  Stream<EEGPacketData> get eegStream => _eegStreamController.stream;
  EEGPacketData? _currentEegData;
  int _eegPacketsReceived = 0;

  // Beat classifications from a HealthyLink compute module (DBLK channel 8).
  // Stub inferences are dropped before they reach this stream.
  final _inferStreamController = StreamController<InferSample>.broadcast();
  Stream<InferSample> get inferStream => _inferStreamController.stream;
  int _inferSamplesReceived = 0;
  int _inferStubsDropped = 0;
  int _eventsReceived = 0;
  int? _lastEegSequenceNumber;
  int _eegSequenceGaps = 0;
  int _eegMissingBySequence = 0;

  // Packet buffering for incomplete packets
  final List<int> _buffer = [];
  int _packetsReceived = 0;
  int _packetsDropped = 0; // Only actual packet parse failures, NOT sync bytes
  int _bytesSkippedDuringSync = 0; // Alignment bytes (not actual packet loss)

  // Ring buffer for storing recent packets (allows UI to retrieve ALL packets, not just latest)
  // Size: 500 packets = 1 second at 500Hz or 2 seconds at 250Hz
  static const int _packetRingBufferSize = 500;
  final List<OpenViewData?> _packetRingBuffer = List.filled(_packetRingBufferSize, null);
  int _packetRingWriteIndex = 0;
  int _packetRingReadIndex = 0;  // Last index read by consumer

  // Ring buffer for EEG packets (250 Hz)
  static const int _eegRingBufferSize = 250;  // 1 second at 250Hz
  final List<EEGPacketData?> _eegRingBuffer = List.filled(_eegRingBufferSize, null);
  int _eegRingWriteIndex = 0;
  int _eegRingReadIndex = 0;

  // Packet rate calculation
  DateTime _lastRateCalculation = DateTime.now();
  int _packetsAtLastCalculation = 0;
  double _packetsPerSecond = 0.0;

  // Throttle notifyListeners to reduce UI rebuilds (max ~30 Hz instead of 500 Hz)
  DateTime _lastNotifyTime = DateTime.now();
  static const int _notifyIntervalMs = 33; // ~30 Hz max notification rate

  // Expected rate tracking for sample loss calculation
  static const double expectedPacketsPerSecond = 500.0; // Device sends at 500 Hz
  DateTime? _streamStartTime;
  int _packetsAtStreamStart = 0;

  // Protocol version tracking
  int _currentProtocolVersion = 0;  // 0 = unknown, 1 = v1, 2 = v2

  // Sequence number tracking (v2 protocol only)
  int? _lastSequenceNumber;
  int _sequenceGaps = 0;        // Number of times a gap was detected
  int _missingBySequence = 0;   // Total missing packets based on sequence gaps
  int _v2PacketsReceived = 0;   // Count of v2 packets for accurate loss calculation

  List<HealthyPiData> get dataHistory => List.unmodifiable(_dataHistory);
  HealthyPiData? get currentData => _currentData;
  OpenViewData? get currentOpenViewData => _currentOpenViewData;
  HRVPacketData? get currentHrvData => _currentHrvData;
  EEGPacketData? get currentEegData => _currentEegData;
  int get packetsReceived => _packetsReceived;
  int get packetsDropped => _packetsDropped;
  int get hrvPacketsReceived => _hrvPacketsReceived;
  int get eegPacketsReceived => _eegPacketsReceived;
  int get inferSamplesReceived => _inferSamplesReceived;
  int get inferStubsDropped => _inferStubsDropped;
  int get eventsReceived => _eventsReceived;
  double get packetsPerSecond => _packetsPerSecond;

  // EEG sequence tracking getters
  int get eegSequenceGaps => _eegSequenceGaps;
  int get eegMissingBySequence => _eegMissingBySequence;
  int? get lastEegSequenceNumber => _lastEegSequenceNumber;

  // Protocol version getters
  int get protocolVersion => _currentProtocolVersion;
  String get protocolVersionString => _currentProtocolVersion == 0
      ? 'Unknown'
      : 'v$_currentProtocolVersion';

  // Sequence tracking getters (v2 only)
  int get sequenceGaps => _sequenceGaps;
  int get missingBySequence => _missingBySequence;
  int? get lastSequenceNumber => _lastSequenceNumber;

  /// True packet loss percentage based on sequence numbers (v2 only)
  /// More accurate than rate-based estimation
  double get sequenceBasedLossPercent {
    if (_currentProtocolVersion < 2 || _v2PacketsReceived == 0) return 0.0;
    final totalExpected = _v2PacketsReceived + _missingBySequence;
    if (totalExpected == 0) return 0.0;
    return (_missingBySequence / totalExpected * 100).clamp(0.0, 100.0);
  }

  /// Whether we have accurate sequence-based loss tracking available
  bool get hasSequenceTracking => _currentProtocolVersion >= 2;

  // ============= RING BUFFER API =============

  /// Get number of unread packets available in ring buffer
  int get availablePackets {
    if (_packetRingWriteIndex >= _packetRingReadIndex) {
      return _packetRingWriteIndex - _packetRingReadIndex;
    } else {
      // Handle wraparound
      return _packetRingBufferSize - _packetRingReadIndex + _packetRingWriteIndex;
    }
  }

  /// Consume all available packets from ring buffer
  /// Returns list of packets in order (oldest first)
  /// After calling this, availablePackets will be 0
  List<OpenViewData> consumePackets() {
    final packets = <OpenViewData>[];

    while (_packetRingReadIndex != _packetRingWriteIndex) {
      final packet = _packetRingBuffer[_packetRingReadIndex];
      if (packet != null) {
        packets.add(packet);
      }
      _packetRingReadIndex = (_packetRingReadIndex + 1) % _packetRingBufferSize;
    }

    return packets;
  }

  /// Add packet to ring buffer (called from parser)
  void _addToRingBuffer(OpenViewData packet) {
    _packetRingBuffer[_packetRingWriteIndex] = packet;
    _packetRingWriteIndex = (_packetRingWriteIndex + 1) % _packetRingBufferSize;

    // If write catches up to read, advance read (drop oldest packet)
    if (_packetRingWriteIndex == _packetRingReadIndex) {
      _packetRingReadIndex = (_packetRingReadIndex + 1) % _packetRingBufferSize;
    }
  }

  /// Get number of EEG packets available in ring buffer
  int get availableEegPackets {
    if (_eegRingWriteIndex >= _eegRingReadIndex) {
      return _eegRingWriteIndex - _eegRingReadIndex;
    } else {
      return _eegRingBufferSize - _eegRingReadIndex + _eegRingWriteIndex;
    }
  }

  /// Consume all available EEG packets from ring buffer
  /// Returns list of packets in order (oldest first)
  List<EEGPacketData> consumeEegPackets() {
    final packets = <EEGPacketData>[];

    while (_eegRingReadIndex != _eegRingWriteIndex) {
      final packet = _eegRingBuffer[_eegRingReadIndex];
      if (packet != null) {
        packets.add(packet);
      }
      _eegRingReadIndex = (_eegRingReadIndex + 1) % _eegRingBufferSize;
    }

    return packets;
  }

  /// Add EEG packet to ring buffer (called from parser)
  void _addEegToRingBuffer(EEGPacketData packet) {
    _eegRingBuffer[_eegRingWriteIndex] = packet;
    _eegRingWriteIndex = (_eegRingWriteIndex + 1) % _eegRingBufferSize;

    // If write catches up to read, advance read (drop oldest packet)
    if (_eegRingWriteIndex == _eegRingReadIndex) {
      _eegRingReadIndex = (_eegRingReadIndex + 1) % _eegRingBufferSize;
    }
  }

  /// Calculate sample loss rate based on expected 500 Hz vs actual received rate
  /// Returns percentage of samples lost (0.0 = no loss, 100.0 = total loss)
  double get sampleLossPercent {
    if (_streamStartTime == null || _packetsPerSecond <= 0) return 0.0;
    // Compare actual rate to expected rate
    final lossRate = 1.0 - (_packetsPerSecond / expectedPacketsPerSecond);
    return (lossRate * 100).clamp(0.0, 100.0);
  }

  /// Get elapsed time since stream started
  Duration get streamDuration {
    if (_streamStartTime == null) return Duration.zero;
    return DateTime.now().difference(_streamStartTime!);
  }

  /// Get expected packets based on elapsed time
  int get expectedPackets {
    if (_streamStartTime == null) return 0;
    final elapsedSeconds = streamDuration.inMilliseconds / 1000.0;
    return (elapsedSeconds * expectedPacketsPerSecond).round();
  }

  /// Get actual packets received since stream started
  int get actualPacketsSinceStart => _packetsReceived - _packetsAtStreamStart;

  /// Get absolute sample loss count (expected - actual)
  int get missedPackets {
    final missed = expectedPackets - actualPacketsSinceStart;
    return missed > 0 ? missed : 0;
  }

  /// Parse incoming fixed-format OpenView binary packets (38 bytes total)
  /// 
  /// Packet structure (38 bytes):
  /// - Byte 0: 0x0A (header byte 1)
  /// - Byte 1: 0xFA (header byte 2)
  /// - Byte 2: 0x1F (31 - data length)
  /// - Byte 3: 0x00 (reserved)
  /// - Byte 4: 0x02 (type indicator)
  /// - Bytes 5-35: Data payload (31 bytes)
  /// - Byte 36: 0x00 (footer byte 1)
  /// - Byte 37: 0x0B (footer byte 2)
  int _bytesReceivedTotal = 0;
  int _chunkCount = 0;
  
  void parseBinaryData(List<int> bytes) {
    try {
      _bytesReceivedTotal += bytes.length;
      _chunkCount++;
      
      _buffer.addAll(bytes);
      
      // Safety: Prevent buffer from growing too large (memory protection)
      if (_buffer.length > 100000) {
        final estimatedPackets = (_buffer.length / 45).round(); // 38-byte payload + 7-byte overhead
        debugPrint('⚠️ Buffer overflow protection: clearing ${_buffer.length} bytes (~$estimatedPackets packets)');
        _packetsDropped += estimatedPackets; // Estimate packets lost
        _buffer.clear();
        return;
      }
      
      // Log diagnostics every 100 chunks for debugging
      if (_chunkCount % 100 == 0) {
        final avgBytesPerChunk = (_bytesReceivedTotal / _chunkCount).toStringAsFixed(1);
        final totalPackets = _packetsReceived + _packetsDropped;
        final dropRate = totalPackets > 0 ? (_packetsDropped / totalPackets * 100).toStringAsFixed(2) : '0.00';
        
        if (_packetsDropped > 0) {
          debugPrint('📊 USB: $avgBytesPerChunk B/chunk | ${_packetsReceived} packets, ${_packetsDropped} dropped (${dropRate}%)');
        }
      }
      
      // .HP6 DBLK framing (Studio rewrite, 2026-06-08): the device streams
      // canonical .HP6 "DBLK" data blocks on CDC0, so one parser serves both
      // the live stream and recorded files.
      //
      // The variable-length OpenView wire parser that used to follow was
      // unreachable after this call and was deleted on 2026-08-31. The
      // OpenViewData model is still live — _drainDblkBlocks() emits it — but
      // nothing decodes the OpenView framing any more. Recover it from git
      // history if a legacy board ever needs to be supported again.
      _drainDblkBlocks();
    } catch (e) {
      debugPrint('❌ Critical error in parseBinaryData: $e');
      // Clear buffer to recover from error state
      _buffer.clear();
    }
  }

  // ====================================================================
  // .HP6 DBLK stream parsing (Studio rewrite for the firmware rewrite)
  // --------------------------------------------------------------------
  // DBLK block (little-endian, see firmware services/hp6_frame.h):
  //   0  4  magic "DBLK"        4   4  block_len (whole frame incl. crc)
  //   8  4  seq                 12  8  t_ms (device monotonic ms)
  //   20 1  channel (Hp6Channel)
  //   21 1  flags               22  2  sample_count   24 4 reserved
  //   28 N  samples (canonical structs)   28+N 4 crc32 (zlib/IEEE)
  // Format 0x0300. The sample size is derived from block_len / sample_count
  // and must equal the channel's struct size (hp6SampleSize), so a layout
  // change on the device shows up as dropped blocks, not misread fields.
  // ECG/PPG/VITALS arrive in separate batched blocks; we hold last-known
  // PPG + vitals and emit one OpenViewData per ECG sample so every existing
  // consumer (consumePackets / packetStream / screens) keeps working.
  // ====================================================================

  // Last-known cross-block state.
  int _lastPpgRed = 0;
  int _lastPpgIr = 0;
  bool _lastPpgValid = false;
  int _lastHr = 0;
  int _lastSpo2 = 0;
  int _lastRr = 0;
  double _lastTemp = 0.0;
  int _lastVitalsFlags = 0;
  int _lastStreamSeq = -1;

  // PPG real-sample FIFO. PPG (250 Hz) arrives in 16-sample blocks; ECG is
  // 500 Hz. We pop one real PPG sample every 2nd ECG sample (2:1 lock) so each
  // emitted OpenViewData carries the correct, distinct PPG sample — no
  // interpolation, no per-block plateau. FIFO absorbs block-boundary jitter.
  final List<int> _ppgFifoRed = [];
  final List<int> _ppgFifoIr = [];
  int _ecgPpgPhase = 0;
  static const int _ppgFifoMax = 512; // ~2 s; guards against drift/overflow

  static const int _dblkMagic0 = 0x44; // 'D'
  static const int _dblkMagic1 = 0x42; // 'B'
  static const int _dblkMagic2 = 0x4C; // 'L'
  static const int _dblkMagic3 = 0x4B; // 'K'
  static const int _dblkHdrLen = dblkHeaderLen;
  static const int _dblkCrcLen = dblkCrcLen;

  void _drainDblkBlocks() {
    bool produced = false;
    while (true) {
      // Find the "DBLK" magic.
      int idx = -1;
      for (int i = 0; i + 4 <= _buffer.length; i++) {
        if (_buffer[i] == _dblkMagic0 &&
            _buffer[i + 1] == _dblkMagic1 &&
            _buffer[i + 2] == _dblkMagic2 &&
            _buffer[i + 3] == _dblkMagic3) {
          idx = i;
          break;
        }
      }
      if (idx == -1) {
        // Keep the last 3 bytes (a magic may be split across chunks).
        if (_buffer.length > 3) {
          _bytesSkippedDuringSync += _buffer.length - 3;
          _buffer.removeRange(0, _buffer.length - 3);
        }
        break;
      }
      if (idx > 0) {
        _bytesSkippedDuringSync += idx;
        _buffer.removeRange(0, idx);
      }
      if (_buffer.length < _dblkHdrLen) break; // need the header
      final blockLen = _readUint32LE(_buffer, 4);
      if (blockLen < _dblkHdrLen + _dblkCrcLen || blockLen > 4096) {
        _buffer.removeRange(0, 4); // bogus length -> resync past this magic
        _packetsDropped++;
        continue;
      }
      if (_buffer.length < blockLen) break; // wait for the rest
      final block = _buffer.sublist(0, blockLen);
      final calc = _crc32(block, 0, blockLen - _dblkCrcLen);
      final got = _readUint32LE(block, blockLen - _dblkCrcLen);
      if (calc != got) {
        _packetsDropped++;
        _buffer.removeRange(0, 4); // corrupt -> resync
        continue;
      }
      try {
        final result = _decodeDblk(block);
        if (result == null) {
          _packetsDropped++;
        } else {
          produced = result || produced;
        }
      } catch (e) {
        debugPrint('❌ DBLK decode error: $e');
        _packetsDropped++;
      }
      _buffer.removeRange(0, blockLen);
    }

    if (produced) {
      final now = DateTime.now();
      if (now.difference(_lastNotifyTime).inMilliseconds >= _notifyIntervalMs) {
        _lastNotifyTime = now;
        notifyListeners();
      }
    }
  }

  /// Decode one validated DBLK block. Returns true if it produced waveform/vital
  /// data worth a UI notification, false for a block that is valid but not
  /// shown, and null for a block whose layout does not match format 0x0300.
  bool? _decodeDblk(List<int> b) {
    final seq = _readUint32LE(b, 8);
    final channel = b[20];
    final sampleCount = _readUint16LE(b, 22);
    const payloadOff = _dblkHdrLen;
    final payloadLen = b.length - _dblkHdrLen - _dblkCrcLen;

    if (_lastStreamSeq >= 0 && seq != ((_lastStreamSeq + 1) & 0xFFFFFFFF)) {
      _sequenceGaps++;
    }
    _lastStreamSeq = seq;
    _currentProtocolVersion = 2;

    final expected = hp6SampleSize[channel];
    if (expected == null) return false; // unknown channel: skip, not an error
    if (sampleCount == 0) return false;
    if (payloadLen % sampleCount != 0 || payloadLen ~/ sampleCount != expected) {
      debugPrint('⚠️ DBLK ch$channel: $payloadLen B for $sampleCount samples, '
          'expected $expected B each — dropped');
      return null;
    }

    switch (channel) {
      case Hp6Channel.ecg: // {resp,leadI,leadII,v1 (i32), lead_off,flags,pad}
        for (int s = 0; s < sampleCount; s++) {
          final o = payloadOff + s * expected;
          // Advance the PPG FIFO at the 2:1 ECG:PPG rate so each ECG sample
          // carries a real, distinct PPG sample (fixes the stepped PPG).
          _ecgPpgPhase++;
          if (_ecgPpgPhase >= 2) {
            _ecgPpgPhase = 0;
            if (_ppgFifoRed.isNotEmpty) {
              _lastPpgRed = _ppgFifoRed.removeAt(0);
              _lastPpgIr = _ppgFifoIr.removeAt(0);
              _lastPpgValid = true;
            }
          }
          final ov = OpenViewData(
            rawPayload: const [],
            protocolVersion: 2,
            sequenceNumber: seq,
            ecg1: _readInt32LE(b, o + 4),   // lead I
            ecg2: _readInt32LE(b, o + 8),   // lead II
            ecg3: _readInt32LE(b, o + 12),  // V1 / lead III
            respiration: _readInt32LE(b, o + 0),
            ppgRed: _lastPpgRed,
            ppgIr: _lastPpgIr,
            ppgValid: _lastPpgValid,
            heartRate: _lastHr,
            spo2: _lastSpo2,
            respirationRate: _lastRr,
            temperature: _lastTemp,
            adcChannel1: 0,
            adcChannel2: 0,
            vitalsFlags: _lastVitalsFlags,
            ecgLeadOff: b[o + 16],
          );
          _currentOpenViewData = ov;
          _currentData = ov.toHealthyPiData();
          _addToRingBuffer(ov);
          _packetStreamController.add(ov);
          _packetsReceived++;
        }
        _updatePacketRate();
        return true;

      case Hp6Channel.ppg: // {red,ir (i32), lead_off, pad[3]}
        for (int s = 0; s < sampleCount; s++) {
          final o = payloadOff + s * expected;
          _ppgFifoRed.add(_readInt32LE(b, o + 0));
          _ppgFifoIr.add(_readInt32LE(b, o + 4));
        }
        // Bound the FIFO: if ECG stalls or rates drift, drop oldest so we never
        // grow without bound (keeps latency low).
        while (_ppgFifoRed.length > _ppgFifoMax) {
          _ppgFifoRed.removeAt(0);
          _ppgFifoIr.removeAt(0);
        }
        return false; // consumed by the ECG cadence at 2:1

      case Hp6Channel.vitals:
        // 16 B: {hr, spo2_x10, rr (u16), temp_x100 (i16), sdnn, rmssd,
        // lf_hf_x10 (u16), flags (u8), pad}
        for (int s = 0; s < sampleCount; s++) {
          final o = payloadOff + s * expected;
          final hr = _readUint16LE(b, o + 0);
          final flags = b[o + 14];
          _lastHr = hr;
          _lastSpo2 = (_readUint16LE(b, o + 2) / 10).round();
          _lastRr = _readUint16LE(b, o + 4);
          _lastTemp = _readInt16LE(b, o + 6) / 100.0;
          _lastVitalsFlags = flags;
          final hrv = HRVPacketData(
            rawPayload: const [],
            timestampMs: _readUint32LE(b, 12), // low 32 bits of t_ms
            heartRate: hr,
            rrIntervalMs: 0, // not on the wire; never synthesize from HR
            sdnnMs: _readUint16LE(b, o + 8),
            rmssdMs: _readUint16LE(b, o + 10),
            pnn50: 0,
            signalQuality: 0,
            hrvValid: hr > 0,
            arrhythmiaFlags: 0,
            meanRrMs: 0,
            lfHfX10: _readUint16LE(b, o + 12),
            vitalsFlags: flags,
          );
          _currentHrvData = hrv;
          _hrvStreamController.add(hrv);
          _hrvPacketsReceived++;
        }
        return true;

      case Hp6Channel.eeg: // {ch[8] (i32, microvolts), lead_off, pad[3]}
        // HealthyLink EEG module (ADS1299, 8 channels, 250 Hz, batched 16
        // samples per block by the firmware's mod_eeg.c). The device publishes
        // this only when the module is attached and CONFIG_SENSOR_ADS1299 is
        // built in, so an absent module simply means no channel-5 blocks — not
        // an error.
        //
        // The firmware sends one lead_off byte per sample and does not
        // distinguish positive from negative electrodes, so the same mask is
        // reported for both and isChannelConnected() stays correct.
        for (int s = 0; s < sampleCount; s++) {
          final o = payloadOff + s * expected;
          final ch = <int>[
            for (int c = 0; c < 8; c++) _readInt32LE(b, o + c * 4),
          ];
          final leadOff = b[o + 32];
          final eeg = EEGPacketData(
            rawPayload: const [],
            sequenceNumber: seq,
            timestampMs: _readUint32LE(b, 12), // low 32 bits of t_ms
            channels: ch,
            leadOffPositive: leadOff,
            leadOffNegative: leadOff,
            signalQuality: 0, // not reported on the wire
          );
          _currentEegData = eeg;
          _addEegToRingBuffer(eeg);
          _eegStreamController.add(eeg);
          _eegPacketsReceived++;
        }
        return true;

      case Hp6Channel.infer: // {ts_ms u32, model u16, class u8, conf u8,
        // scores i8[5], flags u8, pad[2]}
        for (int s = 0; s < sampleCount; s++) {
          final o = payloadOff + s * expected;
          final flags = b[o + 13];
          if ((flags & Hp6InferFlag.stub) != 0) {
            _inferStubsDropped++;
            continue;
          }
          _inferStreamController.add(InferSample(
            tsMs: _readUint32LE(b, o),
            modelId: _readUint16LE(b, o + 4),
            classId: b[o + 6],
            confidence: b[o + 7],
            scores: [for (int k = 0; k < 5; k++) b[o + 8 + k].toSigned(8)],
            flags: flags,
          ));
          _inferSamplesReceived++;
        }
        return false;

      case Hp6Channel.event: // {ts_ms u32, type u16, seq u16}: counted only
        _eventsReceived += sampleCount;
        return false;

      default: // SYNC is file-only; nothing to show live
        return false;
    }
  }

  /// Read a signed 16-bit little-endian integer.
  int _readInt16LE(List<int> bytes, int offset) {
    return (bytes[offset] | (bytes[offset + 1] << 8)).toSigned(16);
  }

  /// CRC-32/ISO-HDLC (zlib) — matches the firmware's Zephyr crc32_ieee().
  static final List<int> _crc32Table = _buildCrc32Table();
  static List<int> _buildCrc32Table() {
    final t = List<int>.filled(256, 0);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[n] = c & 0xFFFFFFFF;
    }
    return t;
  }

  int _crc32(List<int> data, int start, int len) {
    int crc = 0xFFFFFFFF;
    for (int i = start; i < start + len; i++) {
      crc = (_crc32Table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8)) & 0xFFFFFFFF;
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }



  // Legacy OpenView EEG framing. Superseded by DBLK channel 5 in _decodeDblk(),
  // which is the path a real board now takes. Kept because the .HP6 format
  // documentation is written against this layout and it is the reference for
  // the field offsets; nothing calls it.
  // ignore: unused_element
  void _parseEEGPacket(List<int> payload) {
    if (payload.length < 44) {
      throw Exception('EEG payload too short: ${payload.length} bytes (expected 44)');
    }

    // Extract sequence number (first 4 bytes of payload, offset 5 in full packet)
    final sequenceNumber = _readUint32LE(payload, 0);

    // Extract timestamp (offset 4 in payload, offset 9 in full packet)
    final timestampMs = _readUint32LE(payload, 4);

    // Extract 8 EEG channels (int32_le, in microvolts) starting at offset 8 in payload
    final channels = <int>[
      _readInt32LE(payload, 8),   // Channel 1
      _readInt32LE(payload, 12),  // Channel 2
      _readInt32LE(payload, 16),  // Channel 3
      _readInt32LE(payload, 20),  // Channel 4
      _readInt32LE(payload, 24),  // Channel 5
      _readInt32LE(payload, 28),  // Channel 6
      _readInt32LE(payload, 32),  // Channel 7
      _readInt32LE(payload, 36),  // Channel 8
    ];

    // Extract lead-off status (offset 40-41 in payload)
    final leadOffPositive = payload[40];
    final leadOffNegative = payload[41];

    // Extract signal quality (offset 42 in payload)
    final signalQuality = payload[42];
    // Byte 43 is reserved

    // Track EEG sequence for gap detection
    _trackEegSequenceNumber(sequenceNumber);

    // Create EEG data object
    final eegData = EEGPacketData(
      rawPayload: payload,
      sequenceNumber: sequenceNumber,
      timestampMs: timestampMs,
      channels: channels,
      leadOffPositive: leadOffPositive,
      leadOffNegative: leadOffNegative,
      signalQuality: signalQuality,
    );

    _currentEegData = eegData;

    // Add to ring buffer for consumption by UI
    _addEegToRingBuffer(eegData);

    // Emit to EEG stream for subscribers
    _eegStreamController.add(eegData);
  }

  /// Track EEG sequence numbers and detect gaps
  void _trackEegSequenceNumber(int sequenceNumber) {
    if (_lastEegSequenceNumber != null) {
      // Calculate expected next sequence (with 32-bit wraparound)
      final expected = (_lastEegSequenceNumber! + 1) & 0xFFFFFFFF;

      if (sequenceNumber != expected) {
        // Gap detected - calculate how many packets were missed
        int gap;
        if (sequenceNumber > _lastEegSequenceNumber!) {
          gap = sequenceNumber - _lastEegSequenceNumber! - 1;
        } else {
          // Handle wraparound
          gap = (0xFFFFFFFF - _lastEegSequenceNumber! + sequenceNumber) & 0xFFFFFFFF;
        }

        // Sanity check - ignore unreasonable gaps (likely stream restart)
        if (gap > 0 && gap < 10000) {
          _eegSequenceGaps++;
          _eegMissingBySequence += gap;

          // Log significant gaps
          if (gap > 10) {
            debugPrint('⚠️ EEG Sequence gap: expected $expected, got $sequenceNumber (missing $gap packets)');
          }
        } else if (gap >= 10000) {
          // Likely a stream restart, reset tracking
          debugPrint('🧠 EEG Sequence jump detected (likely stream restart): $sequenceNumber');
        }
      }
    }

    _lastEegSequenceNumber = sequenceNumber;
  }


  /// Read 32-bit unsigned integer from bytes in little-endian format
  int _readUint32LE(List<int> bytes, int offset) {
    return bytes[offset] |
           (bytes[offset + 1] << 8) |
           (bytes[offset + 2] << 16) |
           (bytes[offset + 3] << 24);
  }
  
  /// Read 32-bit signed integer from bytes in little-endian format
  int _readInt32LE(List<int> bytes, int offset) {
    final value = bytes[offset] |
                 (bytes[offset + 1] << 8) |
                 (bytes[offset + 2] << 16) |
                 (bytes[offset + 3] << 24);
    // Convert to signed
    return value.toSigned(32);
  }
  
  /// Read 16-bit unsigned integer from bytes in little-endian format
  int _readUint16LE(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  /// Update packet rate calculation (called every packet)
  void _updatePacketRate() {
    final now = DateTime.now();

    // Initialize stream start time on first packet
    _streamStartTime ??= now;

    final elapsed = now.difference(_lastRateCalculation).inMilliseconds;

    // Update rate every second
    if (elapsed >= 1000) {
      final packetsSinceLastCalc = _packetsReceived - _packetsAtLastCalculation;
      _packetsPerSecond = (packetsSinceLastCalc / elapsed) * 1000;

      _lastRateCalculation = now;
      _packetsAtLastCalculation = _packetsReceived;
    }
  }

  /// Get statistics about packet reception
  Map<String, dynamic> getStats() {
    return {
      'packetsReceived': _packetsReceived,
      'packetsDropped': _packetsDropped,
      'bytesSkipped': _bytesSkippedDuringSync, // Alignment bytes (informational)
      'bufferSize': _buffer.length,
      'dropRate': _packetsReceived > 0
          ? (_packetsDropped / (_packetsReceived + _packetsDropped) * 100).toStringAsFixed(2)
          : '0.00',
      'packetsPerSecond': _packetsPerSecond.toStringAsFixed(1),
      // Rate-based sample loss metrics
      'expectedPackets': expectedPackets,
      'actualPackets': actualPacketsSinceStart,
      'missedPackets': missedPackets,
      'sampleLossPercent': sampleLossPercent.toStringAsFixed(1),
      'streamDurationSeconds': streamDuration.inSeconds,
      // Protocol version and sequence tracking (v2)
      'protocolVersion': _currentProtocolVersion,
      'sequenceGaps': _sequenceGaps,
      'missingBySequence': _missingBySequence,
      'sequenceBasedLossPercent': sequenceBasedLossPercent.toStringAsFixed(2),
      'v2PacketsReceived': _v2PacketsReceived,
      'lastSequenceNumber': _lastSequenceNumber ?? 0,
      // HRV packet tracking
      'hrvPacketsReceived': _hrvPacketsReceived,
      'hrvValid': _currentHrvData?.hrvValid ?? false,
      // EEG packet tracking
      'eegPacketsReceived': _eegPacketsReceived,
      'eegSequenceGaps': _eegSequenceGaps,
      'eegMissingBySequence': _eegMissingBySequence,
      'lastEegSequenceNumber': _lastEegSequenceNumber ?? 0,
      'eegConnectedChannels': _currentEegData?.connectedChannelCount ?? 0,
    };
  }

  /// Reset statistics and stream tracking
  void resetStats() {
    _packetsReceived = 0;
    _packetsDropped = 0;
    _bytesSkippedDuringSync = 0;
    _buffer.clear();
    _packetsPerSecond = 0.0;
    // Reset stream tracking
    _streamStartTime = null;
    _packetsAtStreamStart = 0;
    _lastRateCalculation = DateTime.now();
    _packetsAtLastCalculation = 0;
    // Reset sequence tracking
    _currentProtocolVersion = 0;
    _lastSequenceNumber = null;
    _sequenceGaps = 0;
    _missingBySequence = 0;
    _v2PacketsReceived = 0;
    // Reset HRV tracking
    _hrvPacketsReceived = 0;
    _currentHrvData = null;
    // Reset EEG tracking
    _eegPacketsReceived = 0;
    _currentEegData = null;
    _lastEegSequenceNumber = null;
    _eegSequenceGaps = 0;
    _eegMissingBySequence = 0;
    _inferSamplesReceived = 0;
    _inferStubsDropped = 0;
    _eventsReceived = 0;
    _lastStreamSeq = -1;
    _lastVitalsFlags = 0;
  }

  void clear() {
    _dataHistory.clear();
    _currentData = null;
    notifyListeners();
  }

  /// Dispose of resources
  @override
  void dispose() {
    _packetStreamController.close();
    _hrvStreamController.close();
    _eegStreamController.close();
    _inferStreamController.close();
    super.dispose();
  }
}
