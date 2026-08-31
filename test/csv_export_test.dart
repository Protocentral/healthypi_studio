// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/models/export_models.dart';
import 'package:healthypi_studio/models/recording_models.dart';
import 'package:healthypi_studio/services/biosignal_file_writer.dart';
import 'package:healthypi_studio/services/recording_export_service.dart';

/// CSV export used to write a header and stop, so every export was an empty
/// file that looked like a success. These drive a real `.hpd` through the
/// exporter and check the rows that come out the other side.
void main() {
  late Directory tmp;

  final channels = <ChannelInfo>[
    ChannelInfo(id: 'ecg1', name: 'ECG I', unit: 'mV', samplingRate: 500),
    ChannelInfo(id: 'resp', name: 'Respiration', unit: 'Ω', samplingRate: 500),
  ];

  /// A `.hpd` with [count] samples, one millisecond apart.
  Future<File> writeRecording(int count, {List<EventMarker> events = const []}) async {
    final file = File('${tmp.path}/rec_${count}_${events.length}.hpd');
    final writer = BiosignalFileWriter(file);
    await writer.writeHeader(RecordingMetadata(
      deviceId: 'HealthyPi 6',
      channels: channels,
      recordingDuration: Duration(milliseconds: count),
      totalSamples: count,
    ));
    await writer.writeSamples([
      for (int i = 0; i < count; i++)
        MultiChannelSample(
          sequenceNumber: i,
          timestampMicros: i * 1000,
          values: {'ecg1': i * 0.5, 'resp': i * -0.25},
        ),
    ]);
    for (final e in events) {
      await writer.writeEvent(e);
    }
    await writer.finalize();
    return file;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hpi_csv_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('writes one row per sample, not just a header', () async {
    final source = await writeRecording(10);
    final out = await RecordingExportService().exportToCSV(
      inputFilePath: source.path,
      outputFileName: 'out.csv',
      outputDirectory: tmp,
    );

    expect(out, isNotNull);
    final lines = await File(out!).readAsLines();
    final data = lines.where((l) => !l.startsWith('#')).toList();
    // One header row plus one row per sample.
    expect(data.length, 11);
    expect(data.first, 'Time (s),ECG I (mV),Respiration (Ω)');
  });

  test('carries the sample values through, in channel order', () async {
    final source = await writeRecording(4);
    final out = await RecordingExportService().exportToCSV(
      inputFilePath: source.path,
      outputFileName: 'values.csv',
      outputDirectory: tmp,
      options: CSVExportOptions(decimalPrecision: 2, includeMetadata: false),
    );

    final rows = (await File(out!).readAsLines())
        .where((l) => !l.startsWith('#') && l.isNotEmpty)
        .toList();
    // -0.0 is what 0 * -0.25 is; the export prints the value it was given.
    expect(rows[1], '0.00,0.00,-0.00');
    expect(rows[2], '0.00,0.50,-0.25');
    expect(rows[3], '0.00,1.00,-0.50');
  });

  test('the metadata header is optional and off means no # lines', () async {
    final source = await writeRecording(3);
    final out = await RecordingExportService().exportToCSV(
      inputFilePath: source.path,
      outputFileName: 'bare.csv',
      outputDirectory: tmp,
      options: CSVExportOptions(includeMetadata: false, includeMarkers: false),
    );
    final text = await File(out!).readAsString();
    expect(text.contains('#'), isFalse);
  });

  test('downsampling keeps every nth row', () async {
    final source = await writeRecording(10);
    final out = await RecordingExportService().exportToCSV(
      inputFilePath: source.path,
      outputFileName: 'down.csv',
      outputDirectory: tmp,
      options: CSVExportOptions(downsampleFactor: 5, includeMetadata: false),
    );
    final rows = (await File(out!).readAsLines())
        .where((l) => l.isNotEmpty && !l.startsWith('Time'))
        .toList();
    expect(rows.length, 2);
  });

  test('a recording with no samples fails instead of writing an empty file',
      () async {
    final source = await writeRecording(0);
    final service = RecordingExportService();
    final out = await service.exportToCSV(
      inputFilePath: source.path,
      outputFileName: 'empty.csv',
      outputDirectory: tmp,
    );
    expect(out, isNull);
    expect(service.error, isNotNull);
  });

  test('a missing source file reports an error rather than throwing', () async {
    final service = RecordingExportService();
    final out = await service.exportToCSV(
      inputFilePath: '${tmp.path}/nope.hpd',
      outputFileName: 'x.csv',
      outputDirectory: tmp,
    );
    expect(out, isNull);
    expect(service.error, contains('not found'));
  });
}
