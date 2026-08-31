import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/data_parser.dart';

void main() {
  group('EEGPacketData', () {
    test('creates EEG packet with all fields', () {
      final eegData = EEGPacketData(
        rawPayload: List.filled(46, 0),
        sequenceNumber: 12345,
        timestampMs: 1000000,
        channels: [10, -20, 30, -40, 50, -60, 70, -80],
        leadOffPositive: 0x00,
        leadOffNegative: 0x00,
        signalQuality: 85,
      );

      expect(eegData.sequenceNumber, 12345);
      expect(eegData.timestampMs, 1000000);
      expect(eegData.channels.length, 8);
      expect(eegData.channels[0], 10);
      expect(eegData.channels[7], -80);
      expect(eegData.signalQuality, 85);
    });

    test('detects all channels connected when lead-off is zero', () {
      final eegData = EEGPacketData(
        rawPayload: List.filled(46, 0),
        sequenceNumber: 1,
        timestampMs: 0,
        channels: List.filled(8, 0),
        leadOffPositive: 0x00,
        leadOffNegative: 0x00,
        signalQuality: 100,
      );

      for (int i = 0; i < 8; i++) {
        expect(eegData.isChannelConnected(i), true,
            reason: 'Channel $i should be connected');
      }
      expect(eegData.connectedChannelCount, 8);
      expect(eegData.disconnectedChannels, isEmpty);
    });

    test('detects channel 0 disconnected (positive)', () {
      final eegData = EEGPacketData(
        rawPayload: List.filled(46, 0),
        sequenceNumber: 1,
        timestampMs: 0,
        channels: List.filled(8, 0),
        leadOffPositive: 0x01, // Bit 0 set = channel 0 positive disconnected
        leadOffNegative: 0x00,
        signalQuality: 80,
      );

      expect(eegData.isChannelConnected(0), false);
      expect(eegData.isChannelConnected(1), true);
      expect(eegData.connectedChannelCount, 7);
      expect(eegData.disconnectedChannels, [0]);
    });

    test('detects channel 3 disconnected (negative)', () {
      final eegData = EEGPacketData(
        rawPayload: List.filled(46, 0),
        sequenceNumber: 1,
        timestampMs: 0,
        channels: List.filled(8, 0),
        leadOffPositive: 0x00,
        leadOffNegative: 0x08, // Bit 3 set = channel 3 negative disconnected
        signalQuality: 80,
      );

      expect(eegData.isChannelConnected(3), false);
      expect(eegData.isChannelConnected(2), true);
      expect(eegData.isChannelConnected(4), true);
      expect(eegData.connectedChannelCount, 7);
      expect(eegData.disconnectedChannels, [3]);
    });

    test('detects multiple channels disconnected', () {
      final eegData = EEGPacketData(
        rawPayload: List.filled(46, 0),
        sequenceNumber: 1,
        timestampMs: 0,
        channels: List.filled(8, 0),
        leadOffPositive: 0x05, // Bits 0 and 2 set
        leadOffNegative: 0x80, // Bit 7 set
        signalQuality: 50,
      );

      expect(eegData.isChannelConnected(0), false);
      expect(eegData.isChannelConnected(1), true);
      expect(eegData.isChannelConnected(2), false);
      expect(eegData.isChannelConnected(7), false);
      expect(eegData.connectedChannelCount, 5);
      expect(eegData.disconnectedChannels, [0, 2, 7]);
    });

    test('returns correct signal quality level', () {
      expect(
        EEGPacketData(
          rawPayload: List.filled(46, 0),
          sequenceNumber: 1,
          timestampMs: 0,
          channels: List.filled(8, 0),
          leadOffPositive: 0x00,
          leadOffNegative: 0x00,
          signalQuality: 10,
        ).signalQualityLevel,
        'poor',
      );

      expect(
        EEGPacketData(
          rawPayload: List.filled(46, 0),
          sequenceNumber: 1,
          timestampMs: 0,
          channels: List.filled(8, 0),
          leadOffPositive: 0x00,
          leadOffNegative: 0x00,
          signalQuality: 50,
        ).signalQualityLevel,
        'acceptable',
      );

      expect(
        EEGPacketData(
          rawPayload: List.filled(46, 0),
          sequenceNumber: 1,
          timestampMs: 0,
          channels: List.filled(8, 0),
          leadOffPositive: 0x00,
          leadOffNegative: 0x00,
          signalQuality: 85,
        ).signalQualityLevel,
        'good',
      );
    });

    test('getChannel returns correct value or 0 for invalid index', () {
      final eegData = EEGPacketData(
        rawPayload: List.filled(46, 0),
        sequenceNumber: 1,
        timestampMs: 0,
        channels: [100, 200, 300, 400, 500, 600, 700, 800],
        leadOffPositive: 0x00,
        leadOffNegative: 0x00,
        signalQuality: 100,
      );

      expect(eegData.getChannel(0), 100);
      expect(eegData.getChannel(7), 800);
      expect(eegData.getChannel(-1), 0);
      expect(eegData.getChannel(8), 0);
    });

    test('toString includes relevant info', () {
      final eegData = EEGPacketData(
        rawPayload: List.filled(46, 0),
        sequenceNumber: 42,
        timestampMs: 5000,
        channels: [100, 0, 0, 0, 0, 0, 0, 0],
        leadOffPositive: 0x00,
        leadOffNegative: 0x00,
        signalQuality: 90,
      );

      final str = eegData.toString();
      expect(str.contains('seq: 42'), true);
      expect(str.contains('8/8 connected'), true);
      expect(str.contains('quality: 90%'), true);
    });
  });

  group('OpenViewConstants EEG', () {
    test('EEG packet constants are correct', () {
      expect(OpenViewConstants.eegPacketType, 0x04);
      expect(OpenViewConstants.eegPayloadLength, 0x2E); // 46 decimal
      expect(OpenViewConstants.eegPacketLength, 51); // 51 bytes total
      expect(OpenViewConstants.eegChannelCount, 8);
      expect(OpenViewConstants.eegSamplingRate, 250);
    });
  });

  // The 'DataParser EEG parsing' group was deleted on 2026-08-31. It fed
  // OpenView-framed EEG packets to parseBinaryData(), a path that has been
  // unreachable since the 2026-06-08 .HP6 DBLK migration, so every test in it
  // asserted behaviour the app no longer has. DBLK does not carry EEG yet;
  // when it does, write the tests against that framing. The packet-layout
  // constants below still hold and are still checked.
}

/// Helper: Convert uint32 to little-endian bytes

/// Helper: Convert int32 to little-endian bytes
