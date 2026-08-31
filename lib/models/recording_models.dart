/// Recording states for the state machine
enum RecordingState {
  idle,      // Not recording
  recording, // Currently recording
  paused,    // Recording paused (can resume)
  stopped,   // Recording stopped (cannot resume)
  error,     // Error occurred
}

/// Status updates from recording engine
class RecordingStatus {
  final RecordingState state;
  final Duration elapsedTime;
  final int samplesRecorded;
  final int fileSizeBytes;
  final String? errorMessage;
  final DateTime timestamp;

  RecordingStatus({
    required this.state,
    required this.elapsedTime,
    required this.samplesRecorded,
    required this.fileSizeBytes,
    this.errorMessage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'RecordingStatus(state: $state, duration: $elapsedTime, samples: $samplesRecorded)';
}

/// Configuration for a recording session
class RecordingConfig {
  final String sessionName;
  final String? outputFilePath;
  final List<ChannelInfo> channels;
  final SubjectMetadata? subjectMetadata;
  final SessionMetadata? sessionMetadata;
  final bool enablePreBuffer;
  final Duration preBufferDuration;
  final Duration autoSaveInterval;
  final bool enableEventMarkers;

  RecordingConfig({
    required this.sessionName,
    this.outputFilePath,
    required this.channels,
    this.subjectMetadata,
    this.sessionMetadata,
    this.enablePreBuffer = true,
    this.preBufferDuration = const Duration(seconds: 5),
    this.autoSaveInterval = const Duration(minutes: 1),
    this.enableEventMarkers = true,
  });
}

/// Information about a recorded channel
class ChannelInfo {
  final String id;
  final String name;
  final String unit;
  final double samplingRate; // Hz
  final double gainFactor;   // Raw value to physical unit
  final double offset;       // Baseline offset
  final double minValue;     // Expected minimum
  final double maxValue;     // Expected maximum

  ChannelInfo({
    required this.id,
    required this.name,
    required this.unit,
    required this.samplingRate,
    this.gainFactor = 1.0,
    this.offset = 0.0,
    this.minValue = -1000,
    this.maxValue = 1000,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'samplingRate': samplingRate,
    'gainFactor': gainFactor,
    'offset': offset,
    'minValue': minValue,
    'maxValue': maxValue,
  };

  factory ChannelInfo.fromJson(Map<String, dynamic> json) => ChannelInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String,
    samplingRate: (json['samplingRate'] as num).toDouble(),
    gainFactor: (json['gainFactor'] as num?)?.toDouble() ?? 1.0,
    offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
    minValue: (json['minValue'] as num?)?.toDouble() ?? -1000,
    maxValue: (json['maxValue'] as num?)?.toDouble() ?? 1000,
  );
}

/// Subject information (optional)
class SubjectMetadata {
  final String? subjectId;
  final int? age;
  final String? gender; // M, F, Other
  final String? condition;
  final String? notes;
  final DateTime? dateOfBirth;

  SubjectMetadata({
    this.subjectId,
    this.age,
    this.gender,
    this.condition,
    this.notes,
    this.dateOfBirth,
  });

  Map<String, dynamic> toJson() => {
    'subjectId': subjectId,
    'age': age,
    'gender': gender,
    'condition': condition,
    'notes': notes,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
  };

  factory SubjectMetadata.fromJson(Map<String, dynamic> json) =>
      SubjectMetadata(
        subjectId: json['subjectId'] as String?,
        age: json['age'] as int?,
        gender: json['gender'] as String?,
        condition: json['condition'] as String?,
        notes: json['notes'] as String?,
        dateOfBirth: json['dateOfBirth'] != null
            ? DateTime.parse(json['dateOfBirth'] as String)
            : null,
      );
}

/// Session metadata
class SessionMetadata {
  final String protocolName;
  final String? location;
  final String? operator;
  final String? notes;
  final Map<String, String> customTags;
  final DateTime startTime;

  SessionMetadata({
    required this.protocolName,
    this.location,
    this.operator,
    this.notes,
    this.customTags = const {},
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'protocolName': protocolName,
    'location': location,
    'operator': operator,
    'notes': notes,
    'customTags': customTags,
    'startTime': startTime.toIso8601String(),
  };

  factory SessionMetadata.fromJson(Map<String, dynamic> json) =>
      SessionMetadata(
        protocolName: json['protocolName'] as String,
        location: json['location'] as String?,
        operator: json['operator'] as String?,
        notes: json['notes'] as String?,
        customTags: Map<String, String>.from(
          json['customTags'] as Map? ?? {},
        ),
        startTime: json['startTime'] != null
            ? DateTime.parse(json['startTime'] as String)
            : null,
      );
}

/// Multi-channel sample with timestamp
class MultiChannelSample {
  final int sequenceNumber;
  final int timestampMicros; // Microseconds since recording start
  final Map<String, double> values; // Channel ID -> value mapping

  MultiChannelSample({
    required this.sequenceNumber,
    required this.timestampMicros,
    required this.values,
  });

  int get sizeBytes => 4 + 8 + (values.length * 8); // sequence + timestamp + values

  @override
  String toString() =>
      'Sample($sequenceNumber, ${Duration(microseconds: timestampMicros)}, values: ${values.length})';
}

/// Event marker for annotations
class EventMarker {
  final int sequenceNumber;
  final int timestampMicros;
  final String type; // 'annotation', 'event', 'artifact'
  final String description;
  final DateTime recordedAt;

  EventMarker({
    required this.sequenceNumber,
    required this.timestampMicros,
    required this.type,
    required this.description,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'sequenceNumber': sequenceNumber,
    'timestampMicros': timestampMicros,
    'type': type,
    'description': description,
    'recordedAt': recordedAt.toIso8601String(),
  };

  factory EventMarker.fromJson(Map<String, dynamic> json) => EventMarker(
    sequenceNumber: json['sequenceNumber'] as int,
    timestampMicros: json['timestampMicros'] as int,
    type: json['type'] as String,
    description: json['description'] as String,
    recordedAt: DateTime.parse(json['recordedAt'] as String),
  );
}

/// Complete recording metadata
class RecordingMetadata {
  static const int formatVersion = 1;
  static const String fileSignature = 'BIOSIG';

  final String fileFormatVersion;
  final String deviceId;
  final String deviceName;
  final String firmwareVersion;
  final DateTime createdAt;
  final List<ChannelInfo> channels;
  final SubjectMetadata? subjectMetadata;
  final SessionMetadata? sessionMetadata;
  final Duration recordingDuration;
  final int totalSamples;
  final String dataChecksum;

  RecordingMetadata({
    this.fileFormatVersion = '1.0',
    required this.deviceId,
    this.deviceName = 'HealthyPi6',
    // Empty means "not read from the device". It is never defaulted to a
    // version number: the header is what an analysis tool trusts later.
    this.firmwareVersion = '',
    DateTime? createdAt,
    required this.channels,
    this.subjectMetadata,
    this.sessionMetadata,
    this.recordingDuration = Duration.zero,
    this.totalSamples = 0,
    this.dataChecksum = '',
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'fileFormatVersion': fileFormatVersion,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'firmwareVersion': firmwareVersion,
    'createdAt': createdAt.toIso8601String(),
    'channels': channels.map((c) => c.toJson()).toList(),
    'subjectMetadata': subjectMetadata?.toJson(),
    'sessionMetadata': sessionMetadata?.toJson(),
    'recordingDuration': recordingDuration.inMicroseconds,
    'totalSamples': totalSamples,
    'dataChecksum': dataChecksum,
  };

  factory RecordingMetadata.fromJson(Map<String, dynamic> json) =>
      RecordingMetadata(
        fileFormatVersion: json['fileFormatVersion'] as String? ?? '1.0',
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? 'HealthyPi6',
        firmwareVersion: json['firmwareVersion'] as String? ?? '1.0.0',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        channels: (json['channels'] as List?)
                ?.map((c) => ChannelInfo.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        subjectMetadata: json['subjectMetadata'] != null
            ? SubjectMetadata.fromJson(json['subjectMetadata'] as Map<String, dynamic>)
            : null,
        sessionMetadata: json['sessionMetadata'] != null
            ? SessionMetadata.fromJson(json['sessionMetadata'] as Map<String, dynamic>)
            : null,
        recordingDuration: Duration(
          microseconds: json['recordingDuration'] as int? ?? 0,
        ),
        totalSamples: json['totalSamples'] as int? ?? 0,
        dataChecksum: json['dataChecksum'] as String? ?? '',
      );
}

/// Exception for recording errors
class RecordingException implements Exception {
  final String message;
  final dynamic originalException;
  final StackTrace? stackTrace;

  RecordingException(
    this.message, {
    this.originalException,
    this.stackTrace,
  });

  @override
  String toString() => 'RecordingException: $message';
}

/// File format specification document content
const String FILE_FORMAT_SPECIFICATION = '''
BIOSIGNAL FILE FORMAT SPECIFICATION (v1.0)
==========================================

1. FILE STRUCTURE
=================

[File Header]
  - Signature (6 bytes): "BIOSIG"
  - Format Version (2 bytes): uint16
  - Header Size (4 bytes): uint32
  - Data Offset (8 bytes): uint64
  
[Metadata Header]
  - Device ID (64 bytes): null-terminated string
  - Device Name (64 bytes): null-terminated string
  - Firmware Version (32 bytes): null-terminated string
  - Creation Timestamp (8 bytes): int64 (milliseconds since epoch)
  - Number of Channels (2 bytes): uint16
  - Recording Duration (8 bytes): int64 (microseconds)
  - Total Samples (8 bytes): uint64
  
[Channel Configuration] (repeated for each channel)
  - Channel ID (32 bytes): null-terminated string
  - Channel Name (64 bytes): null-terminated string
  - Unit (32 bytes): null-terminated string
  - Sampling Rate (8 bytes): float64 (Hz)
  - Gain Factor (8 bytes): float64
  - Offset (8 bytes): float64
  - Min Value (8 bytes): float64
  - Max Value (8 bytes): float64
  
[Subject Metadata] (optional)
  - Subject ID (64 bytes): null-terminated string or empty
  - Age (4 bytes): int32 or -1 if not set
  - Gender (2 bytes): char (M/F/O)
  - Condition (128 bytes): null-terminated string
  - Notes (256 bytes): null-terminated string
  
[Session Metadata] (optional)
  - Protocol Name (128 bytes): null-terminated string
  - Location (128 bytes): null-terminated string
  - Operator (64 bytes): null-terminated string
  - Notes (256 bytes): null-terminated string
  - Custom Tags JSON Length (4 bytes): uint32
  - Custom Tags (variable): JSON-encoded key-value pairs

[Data Section]
  Multiple data blocks, each containing:
  - Block Marker (2 bytes): 0xDATA
  - Block Sequence (4 bytes): uint32
  - Samples in Block (4 bytes): uint32
  - Timestamp (8 bytes): int64 (microseconds)
  - Data (variable): interleaved samples
    * For each sample:
      - Sequence Number (4 bytes): uint32
      - Timestamp (8 bytes): int64 (microseconds)
      - Values (N * 8 bytes): float64 per channel
  - Block CRC32 (4 bytes): uint32

[Event Section] (optional)
  Multiple event entries:
  - Event Marker (2 bytes): 0xEVNT
  - Sequence Number (4 bytes): uint32
  - Timestamp (8 bytes): int64 (microseconds)
  - Type Length (2 bytes): uint16
  - Type (variable): null-terminated string
  - Description Length (2 bytes): uint16
  - Description (variable): null-terminated string

[Index Section] (optional)
  - Index Marker (2 bytes): 0xINDX
  - Number of Index Entries (4 bytes): uint32
  - Index Entries (repeated):
    * Timestamp (8 bytes): int64 (microseconds)
    * File Offset (8 bytes): uint64
    * Sample Count (8 bytes): uint64

[File Footer]
  - Data Checksum (4 bytes): CRC32
  - File Signature (6 bytes): "ENDOF"
  - Format Version (2 bytes): uint16

2. DATA LAYOUT
==============

Interleaved Sample Format (most efficient):
  Sample 1: [CH1, CH2, CH3, ..., CHN, TIMESTAMP]
  Sample 2: [CH1, CH2, CH3, ..., CHN, TIMESTAMP]
  ...

Each channel value is a 64-bit float (IEEE 754 double precision).

3. CHECKSUMS AND VALIDATION
============================

- CRC32 computed for each data block
- Overall file checksum covers all data sections
- Version compatibility checking on read
- Header integrity verification

4. DESIGN PRINCIPLES
====================

- Binary format for efficiency and speed
- Metadata in structured sections
- Event markers for annotations
- Optional index for quick seeks
- Atomic block writes for crash recovery
- CRC validation for data integrity
''';
