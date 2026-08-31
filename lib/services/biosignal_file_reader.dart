import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/recording_models.dart';

/// File reader for biosignal recordings
class BiosignalFileReader {
  final File _file;
  late RandomAccessFile _raf;
  bool _isOpen = false;

  BiosignalFileReader(this._file);

  /// Open file for reading
  Future<void> open() async {
    if (_isOpen) return;
    _raf = await _file.open();
    _isOpen = true;
  }

  /// Close file
  Future<void> close() async {
    if (_isOpen) {
      await _raf.close();
      _isOpen = false;
    }
  }

  /// Read header metadata
  Future<RecordingMetadata> readHeader() async {
    if (!_isOpen) {
      throw RecordingException('File not open. Call open() first.');
    }

    await _raf.setPosition(0);
    final sig = await _raf.read(6);
    if (String.fromCharCodes(sig) != 'BIOSIG') {
      throw RecordingException('Invalid file signature');
    }

    final version = _readUint16(await _raf.read(2));
    if (version != 1) {
      throw RecordingException('Unsupported format version: $version');
    }

    _readUint32(await _raf.read(4)); // Header size
    _readUint64(await _raf.read(8)); // Data offset

    final deviceId = _readString(await _raf.read(64));
    final deviceName = _readString(await _raf.read(64));
    final firmwareVersion = _readString(await _raf.read(32));
    final createdAtMs = _readInt64(await _raf.read(8));
    final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);

    final channelCount = _readUint16(await _raf.read(2));
    final recordingDurationMicros = _readInt64(await _raf.read(8));
    final totalSamples = _readUint64(await _raf.read(8));

    final channels = <ChannelInfo>[];
    for (int i = 0; i < channelCount; i++) {
      channels.add(ChannelInfo(
        id: _readString(await _raf.read(32)),
        name: _readString(await _raf.read(64)),
        unit: _readString(await _raf.read(32)),
        samplingRate: _readFloat64(await _raf.read(8)),
        gainFactor: _readFloat64(await _raf.read(8)),
        offset: _readFloat64(await _raf.read(8)),
        minValue: _readFloat64(await _raf.read(8)),
        maxValue: _readFloat64(await _raf.read(8)),
      ));
    }

    SubjectMetadata? subjectMetadata;
    if ((await _raf.read(1))[0] == 1) {
      // Field order follows the writer exactly: id, age, gender, condition,
      // notes. Reading them out of order silently shifts every later field.
      final subjectId = _readString(await _raf.read(64));
      final ageVal = _readInt32(await _raf.read(4));
      subjectMetadata = SubjectMetadata(
        subjectId: subjectId,
        age: ageVal == -1 ? null : ageVal,
        gender: _readString(await _raf.read(2)),
        condition: _readString(await _raf.read(128)),
        notes: _readString(await _raf.read(256)),
      );
    }

    SessionMetadata? sessionMetadata;
    if ((await _raf.read(1))[0] == 1) {
      final protocolName = _readString(await _raf.read(128));
      final location = _readString(await _raf.read(128));
      final operator = _readString(await _raf.read(64));
      final notes = _readString(await _raf.read(256));
      final tagsLength = _readUint32(await _raf.read(4));
      final tagsJson = String.fromCharCodes(await _raf.read(tagsLength));
      final customTags = Map<String, String>.from(jsonDecode(tagsJson) as Map? ?? {});

      sessionMetadata = SessionMetadata(
        protocolName: protocolName,
        location: location,
        operator: operator,
        notes: notes,
        customTags: customTags,
      );
    }

    return RecordingMetadata(
      fileFormatVersion: '1.0',
      deviceId: deviceId,
      deviceName: deviceName,
      firmwareVersion: firmwareVersion,
      createdAt: createdAt,
      channels: channels,
      subjectMetadata: subjectMetadata,
      sessionMetadata: sessionMetadata,
      recordingDuration: Duration(microseconds: recordingDurationMicros),
      totalSamples: totalSamples,
    );
  }

  /// Stream samples from file
  Stream<MultiChannelSample> readSamples() async* {
    if (!_isOpen) {
      throw RecordingException('File not open. Call open() first.');
    }

    final metadata = await readHeader();
    final fileLength = await _raf.length();

    while (await _raf.position() < fileLength) {
      try {
        final markerBytes = await _raf.read(4);
        if (markerBytes.length < 4) break;

        final marker = _bytesToUint32(markerBytes);
        if (marker != 0x44415441) break; // DATA

        _readUint32(await _raf.read(4)); // blockSeq
        final sampleCount = _readUint32(await _raf.read(4));
        _readInt64(await _raf.read(8)); // timestamp

        for (int i = 0; i < sampleCount; i++) {
          final seq = _readUint32(await _raf.read(4));
          final ts = _readInt64(await _raf.read(8));

          final values = <String, double>{};
          for (final channel in metadata.channels) {
            values[channel.id] = _readFloat64(await _raf.read(8));
          }

          yield MultiChannelSample(
            sequenceNumber: seq,
            timestampMicros: ts,
            values: values,
          );
        }

        await _raf.read(4); // CRC
      } catch (e) {
        break;
      }
    }
  }

  /// Read all event markers
  Future<List<EventMarker>> readEvents() async {
    if (!_isOpen) {
      throw RecordingException('File not open. Call open() first.');
    }

    final events = <EventMarker>[];
    int position = 0;
    final fileLength = await _raf.length();

    while (position < fileLength) {
      await _raf.setPosition(position);
      try {
        final markerBytes = await _raf.read(4);
        if (markerBytes.length < 4) break;

        if (_bytesToUint32(markerBytes) == 0x45564E54) { // EVENT
          final seqNum = _readUint32(await _raf.read(4));
          final timestamp = _readInt64(await _raf.read(8));
          final typeLength = _readUint16(await _raf.read(2));
          final type = String.fromCharCodes(await _raf.read(typeLength));
          final descLength = _readUint16(await _raf.read(2));
          final description = String.fromCharCodes(await _raf.read(descLength));

          events.add(EventMarker(
            sequenceNumber: seqNum,
            timestampMicros: timestamp,
            type: type,
            description: description,
          ));

          position = await _raf.position();
        } else {
          position += 1;
        }
      } catch (e) {
        break;
      }
    }

    return events;
  }

  static int _readUint16(List<int> b) => _bytesToUint16(b);
  static int _readUint32(List<int> b) => _bytesToUint32(b);
  static int _readUint64(List<int> b) => _bytesToUint64(b);
  static int _readInt32(List<int> b) => _bytesToInt32(b);
  static int _readInt64(List<int> b) => _bytesToInt64(b);
  static double _readFloat64(List<int> b) => _bytesToFloat64(b);

  /// The writer stores these as UTF-8, so they have to be decoded as UTF-8.
  /// `String.fromCharCodes` treats each byte as a code point, which turned every
  /// non-ASCII character in a channel name or unit — 'Ω', '°C' — into mojibake.
  static String _readString(List<int> bytes) {
    final nullIdx = bytes.indexOf(0);
    final body = bytes.sublist(0, nullIdx >= 0 ? nullIdx : bytes.length);
    // A field truncated mid-character would otherwise throw and take the whole
    // header read with it.
    return utf8.decode(body, allowMalformed: true);
  }

  static int _bytesToUint16(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint16(0, Endian.little);
  static int _bytesToUint32(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.little);
  static int _bytesToUint64(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getUint64(0, Endian.little);
  static int _bytesToInt32(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getInt32(0, Endian.little);
  static int _bytesToInt64(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getInt64(0, Endian.little);
  static double _bytesToFloat64(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getFloat64(0, Endian.little);
}
