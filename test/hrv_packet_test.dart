import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/data_parser.dart';

void main() {
  group('HRVPacketData', () {
    test('creates HRV packet with all fields', () {
      final packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 1234567890,
        heartRate: 72,
        rrIntervalMs: 833,
        sdnnMs: 65,
        rmssdMs: 42,
        pnn50: 15,
        signalQuality: 85,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 840,
      );

      expect(packet.heartRate, 72);
      expect(packet.rrIntervalMs, 833);
      expect(packet.sdnnMs, 65);
      expect(packet.rmssdMs, 42);
      expect(packet.pnn50, 15);
      expect(packet.signalQuality, 85);
      expect(packet.hrvValid, true);
      expect(packet.meanRrMs, 840);
    });

    test('detects bradycardia flag', () {
      final packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 55,
        rrIntervalMs: 1090,
        sdnnMs: 50,
        rmssdMs: 30,
        pnn50: 10,
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0x08, // Bradycardia flag
        meanRrMs: 1090,
      );

      expect(packet.bradycardia, true);
      expect(packet.tachycardia, false);
      expect(packet.hasArrhythmia, true);
    });

    test('detects tachycardia flag', () {
      final packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 110,
        rrIntervalMs: 545,
        sdnnMs: 40,
        rmssdMs: 25,
        pnn50: 8,
        signalQuality: 75,
        hrvValid: true,
        arrhythmiaFlags: 0x10, // Tachycardia flag
        meanRrMs: 545,
      );

      expect(packet.bradycardia, false);
      expect(packet.tachycardia, true);
      expect(packet.hasArrhythmia, true);
    });

    test('returns correct SDNN level', () {
      // Low SDNN
      var packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 40, // < 50 = low
        rmssdMs: 30,
        pnn50: 10,
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.sdnnLevel, 'low');

      // Normal SDNN
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 75, // 50-100 = normal
        rmssdMs: 30,
        pnn50: 10,
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.sdnnLevel, 'normal');

      // High SDNN
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 120, // > 100 = high
        rmssdMs: 30,
        pnn50: 10,
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.sdnnLevel, 'high');
    });

    test('returns correct RMSSD level', () {
      // Low RMSSD
      var packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 15, // < 20 = low
        pnn50: 10,
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.rmssdLevel, 'low');

      // Normal RMSSD
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 35, // 20-50 = normal
        pnn50: 10,
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.rmssdLevel, 'normal');

      // High RMSSD
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 60, // > 50 = high
        pnn50: 10,
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.rmssdLevel, 'high');
    });

    test('returns correct pNN50 level', () {
      // Low pNN50
      var packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 30,
        pnn50: 2, // < 3 = low
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.pnn50Level, 'low');

      // Normal pNN50
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 30,
        pnn50: 15, // 3-25 = normal
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.pnn50Level, 'normal');

      // High pNN50
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 30,
        pnn50: 30, // > 25 = high
        signalQuality: 80,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.pnn50Level, 'high');
    });

    test('returns correct signal quality level', () {
      // Poor quality
      var packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 30,
        pnn50: 10,
        signalQuality: 20, // < 30 = poor
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.signalQualityLevel, 'poor');

      // Acceptable quality
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 30,
        pnn50: 10,
        signalQuality: 50, // 30-70 = acceptable
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.signalQualityLevel, 'acceptable');

      // Good quality
      packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 70,
        rrIntervalMs: 857,
        sdnnMs: 60,
        rmssdMs: 30,
        pnn50: 10,
        signalQuality: 85, // >= 70 = good
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 857,
      );
      expect(packet.signalQualityLevel, 'good');
    });

    test('toString includes all relevant info', () {
      final packet = HRVPacketData(
        rawPayload: List.filled(20, 0),
        timestampMs: 0,
        heartRate: 72,
        rrIntervalMs: 833,
        sdnnMs: 65,
        rmssdMs: 42,
        pnn50: 15,
        signalQuality: 85,
        hrvValid: true,
        arrhythmiaFlags: 0,
        meanRrMs: 840,
      );

      final str = packet.toString();
      expect(str.contains('valid'), true);
      expect(str.contains('72'), true); // Heart rate
      expect(str.contains('833'), true); // RR interval
      expect(str.contains('65'), true); // SDNN
    });
  });

  group('OpenViewConstants HRV', () {
    test('HRV packet constants are correct', () {
      expect(OpenViewConstants.hrvPacketType, 0x03);
      expect(OpenViewConstants.hrvPayloadLength, 0x14); // 20 bytes
      expect(OpenViewConstants.hrvPacketLength, 27); // 5 + 20 + 2
    });
  });

  // The 'DataParser HRV parsing' group was deleted on 2026-08-31 for the same
  // reason as the EEG group: it exercised the retired OpenView framing. HRV
  // itself is live — _drainDblkBlocks() emits it — so this needs re-covering
  // against DBLK rather than restoring. The constants below still hold.
}
