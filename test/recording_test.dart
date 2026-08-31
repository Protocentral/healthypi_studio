/// Unit tests for recording engine and file I/O
/// Run with: flutter test test/recording_test.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/models/recording_models.dart';
import 'package:healthypi_studio/services/recording_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingModels', () {
    test('RecordingState enum values', () {
      expect(RecordingState.idle, isNotNull);
      expect(RecordingState.recording, isNotNull);
      expect(RecordingState.paused, isNotNull);
      expect(RecordingState.stopped, isNotNull);
      expect(RecordingState.error, isNotNull);
    });

    test('ChannelInfo serialization', () {
      final channel = ChannelInfo(
        id: 'ch1',
        name: 'Channel 1',
        unit: 'mV',
        samplingRate: 500.0,
        gainFactor: 1.0,
        minValue: -5.0,
        maxValue: 5.0,
      );

      final json = channel.toJson();
      expect(json['id'], 'ch1');
      expect(json['name'], 'Channel 1');
      expect(json['samplingRate'], 500.0);

      final fromJson = ChannelInfo.fromJson(json);
      expect(fromJson.id, channel.id);
      expect(fromJson.name, channel.name);
      expect(fromJson.samplingRate, channel.samplingRate);
    });

    test('RecordingStatus creation', () {
      final status = RecordingStatus(
        state: RecordingState.recording,
        elapsedTime: const Duration(seconds: 10),
        samplesRecorded: 5000,
        fileSizeBytes: 40000,
      );

      expect(status.state, RecordingState.recording);
      expect(status.elapsedTime.inSeconds, 10);
      expect(status.samplesRecorded, 5000);
      expect(status.fileSizeBytes, 40000);
    });

    test('MultiChannelSample creation', () {
      final sample = MultiChannelSample(
        sequenceNumber: 1,
        timestampMicros: 1000,
        values: {
          'ch1': 100.5,
          'ch2': 200.3,
        },
      );

      expect(sample.sequenceNumber, 1);
      expect(sample.timestampMicros, 1000);
      expect(sample.values['ch1'], 100.5);
      expect(sample.values['ch2'], 200.3);
    });

    test('EventMarker creation and serialization', () {
      final event = EventMarker(
        sequenceNumber: 0,
        timestampMicros: 5000000,
        type: 'annotation',
        description: 'Test event',
      );

      expect(event.sequenceNumber, 0);
      expect(event.description, 'Test event');

      final json = event.toJson();
      expect(json['description'], 'Test event');

      final fromJson = EventMarker.fromJson(json);
      expect(fromJson.description, event.description);
    });
  });

  group('RecordingEngine', () {
    late RecordingEngine engine;
    late Directory tempDir;

    // Every assertion below runs against a live recording. addSample(),
    // addEvent() and addAnnotation() are all no-ops unless the engine is in
    // RecordingState.recording — the previous version of these tests called
    // them on an idle engine and asserted they took effect, which the engine
    // has never done.
    RecordingConfig configFor(String session) => RecordingConfig(
          sessionName: session,
          channels: [
            ChannelInfo(
              id: 'ch1',
              name: 'Channel 1',
              unit: 'mV',
              samplingRate: 500.0,
            ),
          ],
          subjectMetadata: SubjectMetadata(subjectId: 'S001', age: 30),
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hpi_rec_test');
      // startRecording() writes into getApplicationDocumentsDirectory(); stub
      // the platform channel so the engine can be exercised off-device.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
      engine = RecordingEngine();
      engine.initialize();
    });

    tearDown(() async {
      if (engine.state == RecordingState.recording ||
          engine.state == RecordingState.paused) {
        await engine.stopRecording();
      }
      engine.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Initial state is idle', () {
      expect(engine.state, RecordingState.idle);
      expect(engine.samplesRecorded, 0);
      expect(engine.getEvents(), isEmpty);
    });

    test('Samples are ignored while idle', () {
      engine.addSample({'ch1': 100.0});
      expect(engine.samplesRecorded, 0);
    });

    test('Start recording moves to recording state', () async {
      await engine.startRecording(configFor('Test'));
      expect(engine.state, RecordingState.recording);
    });

    test('Starting twice throws', () async {
      await engine.startRecording(configFor('Test'));
      expect(
        () => engine.startRecording(configFor('Test')),
        throwsA(isA<RecordingException>()),
      );
    });

    test('Status stream emits updates', () async {
      await engine.startRecording(configFor('Test'));

      var statusUpdates = 0;
      final sub = engine.statusStream.listen((_) => statusUpdates++);

      engine.addEvent(EventMarker(
        sequenceNumber: 0,
        timestampMicros: 0,
        type: 'test',
        description: 'triggers a status emit',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(statusUpdates, greaterThan(0));
      await sub.cancel();
    });

    test('Add single sample', () async {
      await engine.startRecording(configFor('Test'));
      engine.addSample({'ch1': 100.0});
      expect(engine.samplesRecorded, 1);
    });

    test('Add sample batch', () async {
      await engine.startRecording(configFor('Test'));

      final samples = <MultiChannelSample>[
        for (int i = 0; i < 10; i++)
          MultiChannelSample(
            sequenceNumber: i,
            timestampMicros: i * 4000,
            values: {'ch1': (i * 100).toDouble()},
          ),
      ];

      engine.addSampleBatch(samples);
      expect(engine.samplesRecorded, 10);
    });

    test('Add event marker', () async {
      await engine.startRecording(configFor('Test'));

      engine.addEvent(EventMarker(
        sequenceNumber: 0,
        timestampMicros: 0,
        type: 'test',
        description: 'Test marker',
      ));

      final events = engine.getEvents();
      expect(events.length, 1);
      expect(events[0].description, 'Test marker');
    });

    test('Add annotation creates event', () async {
      await engine.startRecording(configFor('Test'));

      engine.addAnnotation('Test annotation');

      final events = engine.getEvents();
      expect(events.length, 1);
      expect(events[0].description, 'Test annotation');
    });

    test('Get current status', () async {
      await engine.startRecording(configFor('Test'));
      engine.addSample({'ch1': 100.0});

      final status = engine.getCurrentStatus();
      expect(status.state, RecordingState.recording);
      expect(status.samplesRecorded, 1);
      expect(status.fileSizeBytes, greaterThan(0));
    });

    test('Reset clears state', () async {
      await engine.startRecording(configFor('Test'));
      engine.addSample({'ch1': 100.0});
      engine.addAnnotation('Test');

      expect(engine.samplesRecorded, 1);
      expect(engine.getEvents().length, 1);

      // reset() is only legal from stopped or idle — it refuses to discard a
      // recording that is still running.
      await engine.stopRecording();
      engine.reset();

      expect(engine.samplesRecorded, 0);
      expect(engine.getEvents().length, 0);
      expect(engine.state, RecordingState.idle);
    });

    test('Generate default filename', () async {
      await engine.startRecording(configFor('Test Session'));

      final filename = engine.generateDefaultFilename();
      expect(filename, startsWith('recording_Test_Session_'));
      expect(filename, endsWith('.hpd'));
    });

    test('Generate default filename before any recording', () {
      // Reachable from the UI before a session is configured; must not throw.
      expect(engine.generateDefaultFilename(), endsWith('.hpd'));
    });

    test('Recording metadata generation', () async {
      await engine.startRecording(configFor('Test Session'));
      engine.addSample({'ch1': 100.0});

      final metadata = engine.getMetadata();
      expect(metadata.channels.length, 1);
      expect(metadata.totalSamples, 1);
      expect(metadata.subjectMetadata?.subjectId, 'S001');
    });
  });

  group('Recording Configuration', () {
    test('RecordingConfig with all optional fields', () {
      final subjectMeta = SubjectMetadata(
        subjectId: 'P001',
        age: 45,
        gender: 'M',
        condition: 'Healthy',
        notes: 'No notes',
      );

      final sessionMeta = SessionMetadata(
        protocolName: 'Baseline',
        location: 'Lab A',
        operator: 'Dr. Smith',
        notes: 'Study notes',
      );

      final configUnused = RecordingConfig(
        sessionName: 'Study_001',
        channels: [
          ChannelInfo(
            id: 'ecg',
            name: 'ECG',
            unit: 'mV',
            samplingRate: 500.0,
          ),
        ],
        subjectMetadata: subjectMeta,
        sessionMetadata: sessionMeta,
        enablePreBuffer: true,
        preBufferDuration: const Duration(seconds: 5),
      );

      expect(configUnused.sessionName, 'Study_001');
      expect(configUnused.subjectMetadata?.subjectId, 'P001');
      expect(configUnused.sessionMetadata?.protocolName, 'Baseline');
      expect(configUnused.enablePreBuffer, true);
      expect(configUnused.preBufferDuration.inSeconds, 5);
    });
  });

  group('Recording Exception', () {
    test('RecordingException creation', () {
      final exception =
          RecordingException('Test error', originalException: Exception('Test'));

      expect(exception.message, 'Test error');
      expect(exception.originalException, isNotNull);
    });

    test('RecordingException toString', () {
      final exception = RecordingException('Test error');
      final str = exception.toString();

      expect(str, contains('RecordingException'));
      expect(str, contains('Test error'));
    });
  });

  group('File Size Calculations', () {
    test('Calculate file size for recording', () {
      // Approximately 8 bytes per sample per channel in binary format
      // 1 channel, 500 Hz, 1 second = 500 samples = 4000 bytes + overhead
      final fileSize = RecordingEngine().fileSizeBytes;
      expect(fileSize, greaterThanOrEqualTo(0));
    });
  });
}
