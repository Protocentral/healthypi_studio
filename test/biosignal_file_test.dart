// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/models/recording_models.dart';
import 'package:healthypi_studio/services/biosignal_file_reader.dart';
import 'package:healthypi_studio/services/biosignal_file_writer.dart';

/// The `.hpd` writer and reader had never been tested against each other, and
/// did not in fact agree: block markers were written 16 bits wide and compared
/// 32, subject metadata was read back in a different field order than it was
/// written, and strings were stored as UTF-8 but decoded as Latin-1. Each of
/// these is a silent corruption, so each gets a test.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hpi_hpd_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> write(
    RecordingMetadata metadata,
    List<MultiChannelSample> samples, {
    List<EventMarker> events = const [],
  }) async {
    final file = File('${tmp.path}/t${DateTime.now().microsecondsSinceEpoch}.hpd');
    final writer = BiosignalFileWriter(file);
    await writer.writeHeader(metadata);
    if (samples.isNotEmpty) await writer.writeSamples(samples);
    for (final e in events) {
      await writer.writeEvent(e);
    }
    await writer.finalize();
    return file;
  }

  RecordingMetadata meta({
    List<ChannelInfo>? channels,
    SubjectMetadata? subject,
  }) =>
      RecordingMetadata(
        deviceId: 'HealthyPi 6',
        channels: channels ??
            [ChannelInfo(id: 'ecg1', name: 'ECG I', unit: 'mV', samplingRate: 500)],
        subjectMetadata: subject,
        recordingDuration: const Duration(seconds: 1),
        totalSamples: 3,
      );

  test('samples written to a file come back out of it', () async {
    final samples = [
      for (int i = 0; i < 3; i++)
        MultiChannelSample(
          sequenceNumber: i,
          timestampMicros: i * 2000,
          values: {'ecg1': i * 1.5},
        ),
    ];
    final reader = BiosignalFileReader(await write(meta(), samples));
    await reader.open();
    final read = await reader.readSamples().toList();
    await reader.close();

    expect(read.length, 3);
    expect(read[2].sequenceNumber, 2);
    expect(read[2].timestampMicros, 4000);
    expect(read[2].values['ecg1'], 3.0);
  });

  test('a multi-channel sample keeps its values on the right channels', () async {
    final channels = [
      ChannelInfo(id: 'ecg1', name: 'ECG I', unit: 'mV', samplingRate: 500),
      ChannelInfo(id: 'ppg', name: 'PPG', unit: 'a.u.', samplingRate: 125),
    ];
    final reader = BiosignalFileReader(await write(
      meta(channels: channels),
      [
        MultiChannelSample(
          sequenceNumber: 0,
          timestampMicros: 0,
          values: {'ecg1': 1.25, 'ppg': -7.5},
        ),
      ],
    ));
    await reader.open();
    final read = await reader.readSamples().toList();
    await reader.close();

    expect(read.single.values['ecg1'], 1.25);
    expect(read.single.values['ppg'], -7.5);
  });

  test('non-ASCII channel units survive the round trip', () async {
    final channels = [
      ChannelInfo(id: 'resp', name: 'Respiration', unit: 'Ω', samplingRate: 500),
      ChannelInfo(id: 'temp', name: 'Temperature', unit: '°C', samplingRate: 1),
    ];
    final reader = BiosignalFileReader(await write(meta(channels: channels), []));
    await reader.open();
    final header = await reader.readHeader();
    await reader.close();

    expect(header.channels[0].unit, 'Ω');
    expect(header.channels[1].unit, '°C');
  });

  test('subject metadata reads back in the field order it was written', () async {
    final subject = SubjectMetadata(
      subjectId: 'SUBJ-042',
      age: 31,
      gender: 'F',
      condition: 'resting',
      notes: 'seated, eyes open',
    );
    final reader = BiosignalFileReader(await write(meta(subject: subject), []));
    await reader.open();
    final header = await reader.readHeader();
    await reader.close();

    expect(header.subjectMetadata?.subjectId, 'SUBJ-042');
    expect(header.subjectMetadata?.age, 31);
    expect(header.subjectMetadata?.gender, 'F');
    expect(header.subjectMetadata?.condition, 'resting');
    expect(header.subjectMetadata?.notes, 'seated, eyes open');
  });

  test('event markers are found after the sample blocks', () async {
    final file = await write(
      meta(),
      [
        MultiChannelSample(
            sequenceNumber: 0, timestampMicros: 0, values: {'ecg1': 0}),
      ],
      events: [
        EventMarker(
          sequenceNumber: 1,
          timestampMicros: 500000,
          type: 'annotation',
          description: 'marker one',
        ),
      ],
    );
    final reader = BiosignalFileReader(file);
    await reader.open();
    final events = await reader.readEvents();
    await reader.close();

    expect(events.map((e) => e.description), contains('marker one'));
  });

  test('the header records the firmware version it was given', () async {
    final file = await write(
      RecordingMetadata(
        deviceId: 'HealthyPi 6',
        firmwareVersion: '1.4.2',
        channels: [
          ChannelInfo(id: 'ecg1', name: 'ECG I', unit: 'mV', samplingRate: 500)
        ],
        recordingDuration: Duration.zero,
        totalSamples: 0,
      ),
      [],
    );
    final reader = BiosignalFileReader(file);
    await reader.open();
    final header = await reader.readHeader();
    await reader.close();

    expect(header.firmwareVersion, '1.4.2');
  });

  test('an unread firmware version is empty, not a made-up number', () async {
    final file = await write(meta(), []);
    final reader = BiosignalFileReader(file);
    await reader.open();
    final header = await reader.readHeader();
    await reader.close();

    expect(header.firmwareVersion, isEmpty);
  });
}
