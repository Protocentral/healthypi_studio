import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/export_models.dart';

/// CSV exporter for biosignal recordings
class CSVExporter {
  final _progressController = StreamController<ExportProgress>.broadcast();

  Stream<ExportProgress> get progressStream => _progressController.stream;

  /// Export recording to CSV format
  Future<ExportResult> export({
    required RecordingDataForExport recording,
    required String outputPath,
    required CSVExportOptions options,
  }) async {
    final startTime = DateTime.now();

    try {
      // Validate output directory
      final file = File(outputPath);
      final directory = file.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Get channels to export
      final channelsToExport =
          recording.getChannelsToExport(options.channelsToExport);
      if (channelsToExport.isEmpty) {
        throw ExportException(
          message: 'No channels selected for export',
          code: 'NO_CHANNELS',
        );
      }

      // Open file for writing
      final sink = file.openWrite(encoding: utf8);

      try {
        // Write metadata header if enabled
        if (options.includeMetadata) {
          await _writeMetadataHeader(recording, options, sink);
        }

        // Write column headers
        await _writeColumnHeaders(channelsToExport, options, sink);

        // Get samples and events for export
        final samples = _getSamplesForExport(
          channelsToExport,
          options,
        );

        // Write data rows
        int rowsWritten = 0;
        int totalRows = samples;

        for (int i = 0; i < samples; i += 1000) {
          // Process in chunks for progress updates
          final end = (i + 1000).clamp(0, samples);
          final chunkSize = end - i;

          for (int j = 0; j < chunkSize; j++) {
            final sampleIndex = i + j;
            await _writeDataRow(
              sampleIndex,
              channelsToExport,
              recording,
              options,
              sink,
            );
            rowsWritten++;
          }

          // Update progress
          final progress = rowsWritten / totalRows;
          _progressController.add(
            ExportProgress(
              progress: progress.clamp(0.0, 1.0),
              samplesProcessed: rowsWritten,
              totalSamples: totalRows,
              currentOperation: 'Writing data rows',
              startTime: startTime,
            ),
          );
        }

        // Write event annotations if enabled and present
        if (options.includeMetadata &&
            recording.events.isNotEmpty &&
            options.includeTimestamps) {
          await _writeEventAnnotations(recording.events, options, sink);
        }

        await sink.close();

        // Get file size
        final fileSize = await file.length();

        return ExportResult(
          filePath: outputPath,
          format: 'CSV',
          samplesExported: totalRows,
          channelsExported: channelsToExport.length,
          eventsExported: recording.events.length,
          fileSizeBytes: fileSize.toInt(),
          exportDuration: DateTime.now().difference(startTime),
        );
      } on Exception {
        await sink.close();
        rethrow;
      }
    } catch (e) {
      _progressController.addError(e);
      if (e is ExportException) {
        rethrow;
      }
      throw ExportException(
        message: 'CSV export failed: ${e.toString()}',
        code: 'EXPORT_FAILED',
        originalException: e is Exception ? e : null,
      );
    }
  }

  /// Write metadata header
  Future<void> _writeMetadataHeader(
    RecordingDataForExport recording,
    CSVExportOptions options,
    IOSink sink,
  ) async {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final lines = <String>[
      '# HealthyPi Studio - CSV Data Export',
      '# Generated: ${dateFormat.format(DateTime.now())}',
      '#',
      '# Device: ${recording.deviceName}',
      '# Device ID: ${recording.deviceId}',
      '# Recording Date: ${dateFormat.format(recording.recordingDateTime)}',
      '# Duration: ${_formatDuration(recording.recordingDuration)}',
      '# Sampling Rate: ${recording.samplingRate.toStringAsFixed(1)} Hz',
      if (recording.subjectId != null) '# Subject ID: ${recording.subjectId}',
      if (recording.protocolName != null)
        '# Protocol: ${recording.protocolName}',
      if (recording.location != null) '# Location: ${recording.location}',
      if (recording.notes != null) '# Notes: ${recording.notes}',
      '#',
      '# Channels: ${recording.channels.length}',
    ];

    for (final channel in recording.channels) {
      lines.add('# - ${channel.name} (${channel.unit}): '
          '${channel.samplingRate.toStringAsFixed(1)} Hz');
    }

    lines.add('#');

    // Write all lines
    for (final line in lines) {
      sink.writeln(line);
    }
  }

  /// Write column header row
  Future<void> _writeColumnHeaders(
    List<ChannelDataForExport> channelsToExport,
    CSVExportOptions options,
    IOSink sink,
  ) async {
    final headers = <String>[];

    if (options.includeTimestamps) {
      headers.add(options.useRelativeTime ? 'Time(s)' : 'DateTime');
    }

    for (final channel in channelsToExport) {
      headers.add('${channel.name}(${channel.unit})');
    }

    final headerLine =
        headers.join(options.delimiter) + options.lineEnding;
    sink.write(headerLine);
  }

  /// Write single data row
  Future<void> _writeDataRow(
    int sampleIndex,
    List<ChannelDataForExport> channelsToExport,
    RecordingDataForExport recording,
    CSVExportOptions options,
    IOSink sink,
  ) async {
    final row = <String>[];

    // Add timestamp if enabled
    if (options.includeTimestamps) {
      if (options.useRelativeTime) {
        // Relative time from start
        final timeSeconds = sampleIndex / recording.samplingRate;
        row.add(options.formatNumber(timeSeconds));
      } else {
        // Absolute datetime
        final recordTime = recording.recordingDateTime
            .add(Duration(microseconds: (sampleIndex / recording.samplingRate * 1000000).toInt()));
        row.add(DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(recordTime));
      }
    }

    // Add channel values
    for (final channel in channelsToExport) {
      if (sampleIndex < channel.samples.length) {
        final value = channel.samples[sampleIndex];
        row.add(options.formatNumber(value));
      } else {
        row.add('');
      }
    }

    final dataLine = row.join(options.delimiter) + options.lineEnding;
    sink.write(dataLine);
  }

  /// Write event annotations as comments
  Future<void> _writeEventAnnotations(
    List<EventMarkerForExport> events,
    CSVExportOptions options,
    IOSink sink,
  ) async {
    sink.writeln('${options.lineEnding}# Events');

    final dateFormat = DateFormat('HH:mm:ss.SSS');

    for (final event in events) {
      final timeStr = dateFormat.format(
        DateTime(2024, 1, 1).add(event.timestamp),
      );
      sink.writeln(
        '# $timeStr - [${event.type}] ${event.description}',
      );
    }
  }

  /// Calculate total samples for export
  int _getSamplesForExport(
    List<ChannelDataForExport> channels,
    CSVExportOptions options,
  ) {
    if (channels.isEmpty) return 0;

    final baseChannel = channels[0];
    final samplesInRange =
        baseChannel.getSamplesInRange(options.timeRange).length;

    if (options.downsampleFactor > 1) {
      return (samplesInRange / options.downsampleFactor).ceil();
    }

    return samplesInRange;
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes}m ${seconds}s';
  }

  /// Cleanup resources
  void dispose() {
    _progressController.close();
  }
}
