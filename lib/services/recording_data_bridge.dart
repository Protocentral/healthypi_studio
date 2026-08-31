import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:collection';
import '../controllers/channel_controller.dart';
import '../services/recording_engine.dart';
import '../models/recording_models.dart';

/// Bridges ChannelController and RecordingEngine for automatic recording
///
/// This service automatically forwards live data from the visualization pipeline
/// to the recording engine when recording is active. It batches samples for
/// efficient disk writes and manages the recording lifecycle.
class RecordingDataBridge extends ChangeNotifier {
  final RecordingEngine recordingEngine;
  final ChannelController channelController;

  bool _isRecording = false;
  Timer? _flushTimer;

  // Buffer for batch writing (improves performance)
  final Queue<Map<String, double>> _sampleQueue = Queue();
  static const int _batchSize = 100; // Write every 100 samples

  int _totalSamplesForwarded = 0;
  DateTime? _recordingStartTime;

  /// Constructor
  RecordingDataBridge({
    required this.recordingEngine,
    required this.channelController,
  }) {
    // Listen to recording state changes
    recordingEngine.addListener(_onRecordingStateChanged);
    debugPrint('✅ RecordingDataBridge initialized');
  }

  // ============= GETTERS =============

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Total samples forwarded to recording engine
  int get totalSamplesForwarded => _totalSamplesForwarded;

  /// Queue length (diagnostic)
  int get queueLength => _sampleQueue.length;

  // ============= RECORDING LIFECYCLE =============

  void _onRecordingStateChanged() {
    final newState = recordingEngine.state;
    final wasRecording = _isRecording;
    _isRecording = newState == RecordingState.recording;

    if (!wasRecording && _isRecording) {
      _startRecordingFlow();
    } else if (wasRecording && !_isRecording) {
      _stopRecordingFlow();
    }
  }

  void _startRecordingFlow() {
    _recordingStartTime = DateTime.now();
    _totalSamplesForwarded = 0;
    _sampleQueue.clear();

    // Start periodic flush timer (every 100ms)
    _flushTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _flushSampleQueue(),
    );

    debugPrint('✅ RecordingDataBridge: Started recording flow');
  }

  void _stopRecordingFlow() {
    _flushTimer?.cancel();
    _flushTimer = null;

    // Final flush
    _flushSampleQueue();

    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!)
        : Duration.zero;

    debugPrint('✅ RecordingDataBridge: Stopped recording flow');
    debugPrint('   Total samples forwarded: $_totalSamplesForwarded');
    debugPrint('   Duration: ${duration.inSeconds}s');
    debugPrint('   Avg rate: ${_totalSamplesForwarded / duration.inSeconds.clamp(1, double.infinity)} samples/sec');
  }

  // ============= DATA FORWARDING =============

  /// Called by ChannelController after adding data
  ///
  /// This is the main entry point for live data during recording.
  /// Data is batched and periodically flushed to the RecordingEngine.
  void onDataAdded(Map<String, double> channelValues) {
    if (!_isRecording) return;

    // Add to queue
    _sampleQueue.add(Map.from(channelValues));

    // Flush if batch size reached
    if (_sampleQueue.length >= _batchSize) {
      _flushSampleQueue();
    }
  }

  void _flushSampleQueue() {
    if (_sampleQueue.isEmpty) return;

    final samples = <MultiChannelSample>[];
    final now = DateTime.now();

    while (_sampleQueue.isNotEmpty) {
      final values = _sampleQueue.removeFirst();
      samples.add(MultiChannelSample(
        sequenceNumber: _totalSamplesForwarded + samples.length,
        timestampMicros: now.microsecondsSinceEpoch,
        values: values,
      ));
    }

    // Forward batch to recording engine
    try {
      recordingEngine.addSampleBatch(samples);
      _totalSamplesForwarded += samples.length;

      // Periodic status update (every 1000 samples)
      if (_totalSamplesForwarded % 1000 == 0) {
        debugPrint('📊 RecordingDataBridge: Forwarded $_totalSamplesForwarded samples '
                   '(queue: ${_sampleQueue.length})');
      }
    } catch (e) {
      debugPrint('❌ RecordingDataBridge: Error flushing samples: $e');
    }

    notifyListeners();
  }

  // ============= STATISTICS =============

  /// Get recording statistics
  Map<String, dynamic> getStats() {
    return {
      'isRecording': _isRecording,
      'totalSamplesForwarded': _totalSamplesForwarded,
      'queueLength': _sampleQueue.length,
      'recordingDuration': _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inSeconds
          : 0,
      'avgSamplesPerSecond': _recordingStartTime != null
          ? _totalSamplesForwarded /
              DateTime.now()
                  .difference(_recordingStartTime!)
                  .inSeconds
                  .clamp(1, double.infinity)
          : 0,
    };
  }

  // ============= CLEANUP =============

  @override
  void dispose() {
    _flushTimer?.cancel();
    recordingEngine.removeListener(_onRecordingStateChanged);
    debugPrint('✅ RecordingDataBridge disposed');
    super.dispose();
  }
}
