import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/recording_models.dart';

/// High-performance biosignal file writer with buffering
class BiosignalFileWriter {
  static const int blockSize = 65536; // 64KB blocks
  static const int dataBlockMarker = 0x44415441; // 'DATA'
  static const int eventMarker = 0x45564E54; // 'EVNT'
  static const int indexMarker = 0x494E4458; // 'INDX'
  static const int fileHeaderSize = 100;

  final IOSink _sink;
  final int _bufferSize;

  int _blockSequence = 0;
  int _bytesWritten = 0;

  /// Every byte handed to the sink: header, blocks, events, index and footer.
  int get bytesWritten => _bytesWritten;
  bool _headerWritten = false;
  final List<_IndexEntry> _indexEntries = [];

  BiosignalFileWriter(File file, {int bufferSize = blockSize})
      : _bufferSize = bufferSize,
        _sink = file.openWrite();

  /// Write file header with metadata
  Future<void> writeHeader(RecordingMetadata metadata) async {
    if (_headerWritten) {
      throw RecordingException('Header already written');
    }

    final buffer = BytesBuilder();

    // File signature and format
    buffer.addByte(0x42); // 'B'
    buffer.addByte(0x49); // 'I'
    buffer.addByte(0x4F); // 'O'
    buffer.addByte(0x53); // 'S'
    buffer.addByte(0x49); // 'I'
    buffer.addByte(0x47); // 'G'

    // Format version
    buffer.add(_uint16ToBytes(1));

    // Header size placeholder (will be calculated)
    buffer.add(_uint32ToBytes(0));

    // Data offset placeholder
    buffer.add(_uint64ToBytes(0));

    // Device information
    buffer.add(_stringToBytes(metadata.deviceId, 64));
    buffer.add(_stringToBytes(metadata.deviceName, 64));
    buffer.add(_stringToBytes(metadata.firmwareVersion, 32));

    // Timestamps
    buffer.add(_int64ToBytes(metadata.createdAt.millisecondsSinceEpoch));

    // Channel information
    buffer.add(_uint16ToBytes(metadata.channels.length));

    // Recording parameters
    buffer.add(_int64ToBytes(metadata.recordingDuration.inMicroseconds));
    buffer.add(_uint64ToBytes(metadata.totalSamples));

    // Channel configurations
    for (final channel in metadata.channels) {
      buffer.add(_stringToBytes(channel.id, 32));
      buffer.add(_stringToBytes(channel.name, 64));
      buffer.add(_stringToBytes(channel.unit, 32));
      buffer.add(_float64ToBytes(channel.samplingRate));
      buffer.add(_float64ToBytes(channel.gainFactor));
      buffer.add(_float64ToBytes(channel.offset));
      buffer.add(_float64ToBytes(channel.minValue));
      buffer.add(_float64ToBytes(channel.maxValue));
    }

    // Subject metadata (if present)
    if (metadata.subjectMetadata != null) {
      buffer.addByte(1); // Present flag
      final sm = metadata.subjectMetadata!;
      buffer.add(_stringToBytes(sm.subjectId ?? '', 64));
      buffer.add(_int32ToBytes(sm.age ?? -1));
      buffer.add(_stringToBytes(sm.gender ?? '', 2));
      buffer.add(_stringToBytes(sm.condition ?? '', 128));
      buffer.add(_stringToBytes(sm.notes ?? '', 256));
    } else {
      buffer.addByte(0);
    }

    // Session metadata (if present)
    if (metadata.sessionMetadata != null) {
      buffer.addByte(1); // Present flag
      final sm = metadata.sessionMetadata!;
      buffer.add(_stringToBytes(sm.protocolName, 128));
      buffer.add(_stringToBytes(sm.location ?? '', 128));
      buffer.add(_stringToBytes(sm.operator ?? '', 64));
      buffer.add(_stringToBytes(sm.notes ?? '', 256));

      // Custom tags as JSON
      final tagsJson = jsonEncode(sm.customTags);
      buffer.add(_uint32ToBytes(tagsJson.length));
      buffer.add(utf8.encode(tagsJson));
    } else {
      buffer.addByte(0);
    }

    final headerBytes = buffer.toBytes();
    _sink.add(headerBytes);
    _bytesWritten += headerBytes.length;
    _headerWritten = true;
  }

  /// Write sample data block
  Future<void> writeSamples(List<MultiChannelSample> samples) async {
    if (!_headerWritten) {
      throw RecordingException('Header must be written before samples');
    }

    final buffer = BytesBuilder();

    // Block header. 32 bits: the marker is a four-character tag.
    buffer.add(_uint32ToBytes(dataBlockMarker));
    buffer.add(_uint32ToBytes(_blockSequence++));
    buffer.add(_uint32ToBytes(samples.length));

    // Timestamp
    if (samples.isNotEmpty) {
      buffer.add(_int64ToBytes(samples.first.timestampMicros));
      _indexEntries.add(_IndexEntry(
        timestamp: samples.first.timestampMicros,
        fileOffset: _bytesWritten,
        sampleCount: samples.length,
      ));
    }

    // Sample data
    for (final sample in samples) {
      buffer.add(_uint32ToBytes(sample.sequenceNumber));
      buffer.add(_int64ToBytes(sample.timestampMicros));

      for (final value in sample.values.values) {
        buffer.add(_float64ToBytes(value));
      }
    }

    // Block CRC32
    final blockBytes = buffer.toBytes();
    final crc = _calculateCRC32(blockBytes);
    buffer.add(_uint32ToBytes(crc));

    final allBytes = buffer.toBytes();
    _sink.add(allBytes);
    _bytesWritten += allBytes.length;

    // Flush if buffer gets large
    if (_bytesWritten % _bufferSize == 0) {
      await _sink.flush();
    }
  }

  /// Write an event marker
  Future<void> writeEvent(EventMarker event) async {
    if (!_headerWritten) {
      throw RecordingException('Header must be written before events');
    }

    final buffer = BytesBuilder();

    buffer.add(_uint32ToBytes(eventMarker));
    buffer.add(_uint32ToBytes(event.sequenceNumber));
    buffer.add(_int64ToBytes(event.timestampMicros));

    // Type
    final typeBytes = utf8.encode(event.type);
    buffer.add(_uint16ToBytes(typeBytes.length));
    buffer.add(typeBytes);

    // Description
    final descBytes = utf8.encode(event.description);
    buffer.add(_uint16ToBytes(descBytes.length));
    buffer.add(descBytes);

    final allBytes = buffer.toBytes();
    _sink.add(allBytes);
    _bytesWritten += allBytes.length;
  }

  /// Finalize file and close
  Future<void> finalize() async {
    if (!_headerWritten) {
      throw RecordingException('Cannot finalize without header');
    }

    // Write index if present
    if (_indexEntries.isNotEmpty) {
      final buffer = BytesBuilder();
      buffer.add(_uint32ToBytes(indexMarker));
      buffer.add(_uint32ToBytes(_indexEntries.length));

      for (final entry in _indexEntries) {
        buffer.add(_int64ToBytes(entry.timestamp));
        buffer.add(_uint64ToBytes(entry.fileOffset));
        buffer.add(_uint64ToBytes(entry.sampleCount));
      }

      final indexBytes = buffer.toBytes();
      _sink.add(indexBytes);
      _bytesWritten += indexBytes.length;
    }

    // Write footer
    final footer = BytesBuilder();
    footer.addByte(0x45); // 'E'
    footer.addByte(0x4E); // 'N'
    footer.addByte(0x44); // 'D'
    footer.addByte(0x4F); // 'O'
    footer.addByte(0x46); // 'F'
    footer.addByte(0x00); // null terminator
    footer.add(_uint16ToBytes(1)); // Format version

    final footerBytes = footer.toBytes();
    _sink.add(footerBytes);
    _bytesWritten += footerBytes.length;

    await _sink.flush();
    await _sink.close();
  }

  // Helper methods for type conversion
  List<int> _uint16ToBytes(int value) {
    final bytes = ByteData(2);
    bytes.setUint16(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  List<int> _uint32ToBytes(int value) {
    final bytes = ByteData(4);
    bytes.setUint32(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  List<int> _uint64ToBytes(int value) {
    final bytes = ByteData(8);
    bytes.setUint64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  List<int> _int32ToBytes(int value) {
    final bytes = ByteData(4);
    bytes.setInt32(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  List<int> _int64ToBytes(int value) {
    final bytes = ByteData(8);
    bytes.setInt64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  List<int> _float64ToBytes(double value) {
    final bytes = ByteData(8);
    bytes.setFloat64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  List<int> _stringToBytes(String str, int maxLength) {
    final encoded = utf8.encode(str);
    final result = List<int>.filled(maxLength, 0);
    final length = encoded.length < maxLength ? encoded.length : maxLength;
    result.setRange(0, length, encoded);
    return result;
  }

  int _calculateCRC32(List<int> bytes) {
    // Simple CRC32 implementation
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < bytes.length; i++) {
      crc = crc ^ bytes[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}

class _IndexEntry {
  final int timestamp;
  final int fileOffset;
  final int sampleCount;

  _IndexEntry({
    required this.timestamp,
    required this.fileOffset,
    required this.sampleCount,
  });
}
