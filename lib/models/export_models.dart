import 'package:intl/intl.dart';

/// Time range specification for exports
class TimeRange {
  final Duration startTime;
  final Duration endTime;

  TimeRange({
    required this.startTime,
    required this.endTime,
  }) : assert(endTime.inMicroseconds >= startTime.inMicroseconds,
            'End time must be >= start time');

  /// Full range (entire recording)
  factory TimeRange.full() => TimeRange(
        startTime: Duration.zero,
        endTime: const Duration(hours: 10), // Max duration
      );

  /// Custom range
  factory TimeRange.custom({
    required Duration start,
    required Duration end,
  }) =>
      TimeRange(startTime: start, endTime: end);

  Duration get duration =>
      Duration(microseconds: endTime.inMicroseconds - startTime.inMicroseconds);

  bool contains(Duration time) =>
      time.inMicroseconds >= startTime.inMicroseconds &&
      time.inMicroseconds <= endTime.inMicroseconds;
}

/// CSV export options and configuration
class CSVExportOptions {
  /// Channels to export (null = all)
  final List<String>? channelsToExport;

  /// Time range to export
  final TimeRange timeRange;

  /// Field delimiter (comma, tab, semicolon)
  final String delimiter;

  /// Decimal precision (2-8)
  final int decimalPrecision;

  /// Include metadata header
  final bool includeMetadata;

  /// Include timestamp column
  final bool includeTimestamps;

  /// Use relative time (seconds from start) or absolute
  final bool useRelativeTime;

  /// Line ending style
  final String lineEnding;

  /// Downsample factor (1 = no downsampling, 2 = every 2nd sample, etc.)
  final int downsampleFactor;

  /// Append the recording's event markers after the sample rows.
  final bool includeMarkers;

  CSVExportOptions({
    this.channelsToExport,
    TimeRange? timeRange,
    this.delimiter = ',',
    this.decimalPrecision = 4,
    this.includeMetadata = true,
    this.includeTimestamps = true,
    this.useRelativeTime = true,
    this.lineEnding = '\n',
    this.downsampleFactor = 1,
    this.includeMarkers = true,
  })  : timeRange = timeRange ?? TimeRange.full(),
        assert(decimalPrecision >= 2 && decimalPrecision <= 8,
            'Decimal precision must be 2-8'),
        assert(downsampleFactor >= 1, 'Downsample factor must be >= 1'),
        assert(
            delimiter == ',' || delimiter == '\t' || delimiter == ';',
            'Delimiter must be comma, tab, or semicolon');

  /// Create a copy with modified options
  CSVExportOptions copyWith({
    List<String>? channelsToExport,
    TimeRange? timeRange,
    String? delimiter,
    int? decimalPrecision,
    bool? includeMetadata,
    bool? includeTimestamps,
    bool? useRelativeTime,
    String? lineEnding,
    int? downsampleFactor,
    bool? includeMarkers,
  }) =>
      CSVExportOptions(
        channelsToExport: channelsToExport ?? this.channelsToExport,
        timeRange: timeRange ?? this.timeRange,
        delimiter: delimiter ?? this.delimiter,
        decimalPrecision: decimalPrecision ?? this.decimalPrecision,
        includeMetadata: includeMetadata ?? this.includeMetadata,
        includeTimestamps: includeTimestamps ?? this.includeTimestamps,
        useRelativeTime: useRelativeTime ?? this.useRelativeTime,
        lineEnding: lineEnding ?? this.lineEnding,
        downsampleFactor: downsampleFactor ?? this.downsampleFactor,
        includeMarkers: includeMarkers ?? this.includeMarkers,
      );

  /// Format number to specified decimal places
  String formatNumber(double value) {
    final formatter = NumberFormat('0.${'0' * decimalPrecision}');
    return formatter.format(value);
  }

  /// Get delimiter name for display
  String get delimiterName {
    switch (delimiter) {
      case ',':
        return 'Comma';
      case '\t':
        return 'Tab';
      case ';':
        return 'Semicolon';
      default:
        return 'Custom';
    }
  }
}

/// Export progress information
class ExportProgress {
  final double progress; // 0.0 to 1.0
  final int samplesProcessed;
  final int totalSamples;
  final String? currentOperation;
  final DateTime startTime;

  ExportProgress({
    required this.progress,
    required this.samplesProcessed,
    required this.totalSamples,
    this.currentOperation,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  /// Estimated time remaining
  Duration get estimatedTimeRemaining {
    if (progress <= 0 || progress >= 1.0) return Duration.zero;

    final elapsed = DateTime.now().difference(startTime);
    final totalEstimated = elapsed.inMilliseconds / progress;
    final remaining = (totalEstimated - elapsed.inMilliseconds).toInt();

    return Duration(milliseconds: remaining.clamp(0, 10000000));
  }

  /// Format remaining time for display
  String get formattedTimeRemaining {
    final remaining = estimatedTimeRemaining;
    if (remaining.inSeconds < 60) {
      return '${remaining.inSeconds}s';
    } else if (remaining.inMinutes < 60) {
      return '${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
    } else {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m';
    }
  }

  @override
  String toString() =>
      'ExportProgress($progress, $samplesProcessed/$totalSamples, $formattedTimeRemaining remaining)';
}

/// Export result information
class ExportResult {
  final String filePath;
  final String format; // 'CSV'
  final int samplesExported;
  final int channelsExported;
  final int eventsExported;
  final int fileSizeBytes;
  final Duration exportDuration;
  final List<String> warnings;

  ExportResult({
    required this.filePath,
    required this.format,
    required this.samplesExported,
    required this.channelsExported,
    required this.eventsExported,
    required this.fileSizeBytes,
    required this.exportDuration,
    this.warnings = const [],
  });

  /// File size formatted for display
  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSizeBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Export rate in samples per second
  int get exportRate {
    if (exportDuration.inSeconds == 0) return 0;
    return (samplesExported / exportDuration.inSeconds).toInt();
  }

  @override
  String toString() =>
      'ExportResult($format, $samplesExported samples, $fileSizeFormatted, ${exportDuration.inSeconds}s)';
}

/// Export error information
class ExportException implements Exception {
  final String message;
  final String code;
  final Exception? originalException;

  ExportException({
    required this.message,
    required this.code,
    this.originalException,
  });

  @override
  String toString() => 'ExportException[$code]: $message';
}

/// Channel data for export
class ChannelDataForExport {
  final String id;
  final String name;
  final String unit;
  final double samplingRate;
  final List<double> samples;
  final double minValue;
  final double maxValue;

  ChannelDataForExport({
    required this.id,
    required this.name,
    required this.unit,
    required this.samplingRate,
    required this.samples,
    this.minValue = double.negativeInfinity,
    this.maxValue = double.infinity,
  });

  /// Get sample count after downsampling
  int getSampleCountDownsampled(int downsampleFactor) {
    return (samples.length / downsampleFactor).ceil();
  }

  /// Get downsampled samples
  List<double> getDownsampledSamples(int downsampleFactor) {
    if (downsampleFactor <= 1) return samples;

    final downsampled = <double>[];
    for (int i = 0; i < samples.length; i += downsampleFactor) {
      downsampled.add(samples[i]);
    }
    return downsampled;
  }

  /// Get samples within time range
  List<double> getSamplesInRange(TimeRange timeRange) {
    final startIndex =
        (timeRange.startTime.inMicroseconds / (1000000 / samplingRate))
            .toInt();
    final endIndex =
        (timeRange.endTime.inMicroseconds / (1000000 / samplingRate)).toInt();

    final clampedStart = startIndex.clamp(0, samples.length);
    final clampedEnd = endIndex.clamp(0, samples.length);

    if (clampedStart >= clampedEnd) return [];

    return samples.sublist(clampedStart, clampedEnd);
  }
}

/// Recording data for export
class RecordingDataForExport {
  final String deviceName;
  final String deviceId;
  final DateTime recordingDateTime;
  final Duration recordingDuration;
  final String? subjectId;
  final String? protocolName;
  final String? location;
  final String? notes;
  final List<ChannelDataForExport> channels;
  final List<EventMarkerForExport> events;

  RecordingDataForExport({
    required this.deviceName,
    required this.deviceId,
    required this.recordingDateTime,
    required this.recordingDuration,
    required this.channels,
    required this.events,
    this.subjectId,
    this.protocolName,
    this.location,
    this.notes,
  });

  /// Get total number of samples (from first channel)
  int get totalSamples =>
      channels.isNotEmpty ? channels[0].samples.length : 0;

  /// Get sampling rate (from first channel)
  double get samplingRate =>
      channels.isNotEmpty ? channels[0].samplingRate : 0;

  /// Get channels to export
  List<ChannelDataForExport> getChannelsToExport(
    List<String>? channelIds,
  ) {
    if (channelIds == null || channelIds.isEmpty) {
      return channels;
    }

    return channels.where((ch) => channelIds.contains(ch.id)).toList();
  }
}

/// Event marker for export
class EventMarkerForExport {
  final Duration timestamp;
  final String type;
  final String description;
  final int sequenceNumber;

  EventMarkerForExport({
    required this.timestamp,
    required this.type,
    required this.description,
    required this.sequenceNumber,
  });
}
