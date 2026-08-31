import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/recording_models.dart';
import '../services/biosignal_file_writer.dart';
import '../services/data_parser.dart';

/// Main recording engine with state machine and data management
class RecordingEngine extends ChangeNotifier {
  RecordingState _state = RecordingState.idle;
  final StreamController<RecordingStatus> _statusController =
      StreamController<RecordingStatus>.broadcast();

  // Nullable, not `late`: addSample(), getMetadata() and generateDefaultFilename()
  // are all reachable before the first startRecording() — addSample() explicitly
  // handles the idle state to feed the pre-buffer — and a `late` field turned
  // every one of those calls into a LateInitializationError.
  RecordingConfig? _config;
  late RecordingMetadata _metadata;

  DateTime? _recordingStartTime;
  DateTime? _pauseStartTime;
  Duration _totalPausedTime = Duration.zero;

  int _sequenceNumber = 0;
  int _samplesRecorded = 0;
  int _fileSizeBytes = 0;

  // Pre-buffer for capturing data before recording starts
  final Queue<MultiChannelSample> _preBuffer = Queue();
  int _maxPreBufferSize = 0;

  // Auto-save tracking
  Timer? _autoSaveTimer;

  // Event markers
  final List<EventMarker> _events = [];

  // HRV packet recording
  final List<HRVPacketData> _hrvPackets = [];
  int _hrvPacketsRecorded = 0;

  // File writer for persistent storage
  BiosignalFileWriter? _fileWriter;
  String? _currentFilePath;

  RecordingState get state => _state;

  /// The `.hpd` this session is writing, or wrote last. Survives `stopRecording`
  /// so a caller can act on the finished file; cleared by `reset()`.
  String? get currentFilePath => _currentFilePath;

  /// The connected board's firmware version, pushed in from `main.dart` so the
  /// engine keeps no dependency on the transport. Stamped into the file header;
  /// empty when no board answered, never a placeholder version.
  String deviceFirmwareVersion = '';
  Stream<RecordingStatus> get statusStream => _statusController.stream;
  Duration get elapsedTime {
    if (_recordingStartTime == null) return Duration.zero;

    final now = DateTime.now();
    final elapsed = now.difference(_recordingStartTime!);
    return elapsed - _totalPausedTime;
  }

  int get samplesRecorded => _samplesRecorded;
  /// Bytes on disk while a file is open, not the sum of sample payloads — the
  /// header, per-block headers, CRCs and the index count too, and the UI shows
  /// this as "File size" next to a real file.
  int get fileSizeBytes => _fileWriter?.bytesWritten ?? _fileSizeBytes;
  int get hrvPacketsRecorded => _hrvPacketsRecorded;
  List<HRVPacketData> get hrvPackets => List.unmodifiable(_hrvPackets);

  /// Initialize recording engine
  void initialize({
    int preBufferSeconds = 5,
    int maxPreBufferSamples = 2000,
  }) {
    _maxPreBufferSize = maxPreBufferSamples;
    _emitStatus();
  }

  /// Start a new recording session
  Future<void> startRecording(RecordingConfig config) async {
    if (_state != RecordingState.idle) {
      throw RecordingException('Cannot start recording in state: $_state');
    }

    try {
      _config = config;
      _recordingStartTime = DateTime.now();
      _sequenceNumber = 0;
      _samplesRecorded = 0;
      _fileSizeBytes = 0;
      _totalPausedTime = Duration.zero;
      _events.clear();

      // Initialize metadata
      _metadata = RecordingMetadata(
        // The firmware reports no serial over the stream or MCUmgr, so this
        // records the model. It is not a per-unit identifier and must not be
        // written as though it were.
        deviceId: 'HealthyPi 6',
        firmwareVersion: deviceFirmwareVersion,
        channels: config.channels,
        subjectMetadata: config.subjectMetadata,
        sessionMetadata: config.sessionMetadata,
      );

      // Initialize file writer
      _currentFilePath = await _generateFilePath();
      final file = File(_currentFilePath!);
      _fileWriter = BiosignalFileWriter(file);
      await _fileWriter!.writeHeader(_metadata);

      debugPrint('✅ Recording started: $_currentFilePath');

      _state = RecordingState.recording;

      // Start auto-save timer
      _autoSaveTimer = Timer.periodic(config.autoSaveInterval, (_) {
        _emitStatus();
      });

      _emitStatus();
      notifyListeners();
    } catch (e, st) {
      _state = RecordingState.error;
      throw RecordingException(
        'Failed to start recording',
        originalException: e,
        stackTrace: st,
      );
    }
  }

  /// Pause recording (can be resumed)
  Future<void> pauseRecording() async {
    if (_state != RecordingState.recording) {
      throw RecordingException('Cannot pause in state: $_state');
    }

    try {
      _pauseStartTime = DateTime.now();
      _state = RecordingState.paused;
      _emitStatus();
      notifyListeners();
    } catch (e, st) {
      _state = RecordingState.error;
      throw RecordingException(
        'Failed to pause recording',
        originalException: e,
        stackTrace: st,
      );
    }
  }

  /// Resume paused recording
  Future<void> resumeRecording() async {
    if (_state != RecordingState.paused) {
      throw RecordingException('Cannot resume in state: $_state');
    }

    try {
      if (_pauseStartTime != null) {
        _totalPausedTime +=
            DateTime.now().difference(_pauseStartTime!);
        _pauseStartTime = null;
      }

      _state = RecordingState.recording;
      _emitStatus();
      notifyListeners();
    } catch (e, st) {
      _state = RecordingState.error;
      throw RecordingException(
        'Failed to resume recording',
        originalException: e,
        stackTrace: st,
      );
    }
  }

  /// Stop recording (cannot be resumed)
  Future<void> stopRecording() async {
    if (_state == RecordingState.idle || _state == RecordingState.stopped) {
      return; // Already stopped
    }

    try {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = null;

      // Finalize and close file
      if (_fileWriter != null) {
        await _fileWriter!.finalize();
        // Keep the final size once the writer is gone.
        _fileSizeBytes = _fileWriter!.bytesWritten;
        _fileWriter = null;

        debugPrint('✅ Recording stopped: $_currentFilePath');
        debugPrint('   Total samples: $_samplesRecorded');
        debugPrint('   File size: ${(_fileSizeBytes / 1024).toStringAsFixed(2)} KB');
      }

      _state = RecordingState.stopped;
      _emitStatus();
      notifyListeners();
    } catch (e, st) {
      _state = RecordingState.error;
      throw RecordingException(
        'Failed to stop recording',
        originalException: e,
        stackTrace: st,
      );
    }
  }

  /// Add a data sample during recording.
  ///
  /// **This does not write to the file** — it counts the sample and, when idle,
  /// pre-buffers it. Only `addSampleBatch` reaches `BiosignalFileWriter`, and
  /// that is what the live path (`RecordingDataBridge`) calls. Nothing but the
  /// tests calls this today; anything that starts to must not expect the sample
  /// to land on disk.
  void addSample(Map<String, double> values) {
    if (_state == RecordingState.error || _state == RecordingState.stopped) {
      return;
    }

    final sample = MultiChannelSample(
      sequenceNumber: _sequenceNumber++,
      timestampMicros: elapsedTime.inMicroseconds,
      values: values,
    );

    if (_state == RecordingState.recording) {
      _samplesRecorded++;
      _fileSizeBytes += sample.sizeBytes;
    } else if (_state == RecordingState.idle && (_config?.enablePreBuffer ?? false)) {
      // Pre-buffer data
      _preBuffer.add(sample);
      if (_preBuffer.length > _maxPreBufferSize) {
        _preBuffer.removeFirst();
      }
    }
  }

  /// Add a batch of samples (more efficient)
  void addSampleBatch(List<MultiChannelSample> samples) {
    if (_state != RecordingState.recording) return;

    for (final sample in samples) {
      _samplesRecorded++;
      _fileSizeBytes += sample.sizeBytes;
    }

    // Write to file
    _fileWriter?.writeSamples(samples);
  }

  /// Add an event marker/annotation
  void addEvent(EventMarker event) {
    if (_state != RecordingState.recording) {
      return;
    }

    final adjustedEvent = EventMarker(
      sequenceNumber: event.sequenceNumber,
      timestampMicros: elapsedTime.inMicroseconds,
      type: event.type,
      description: event.description,
    );

    _events.add(adjustedEvent);
    _emitStatus();
  }

  /// Add a text annotation
  void addAnnotation(String text) {
    if (_state != RecordingState.recording) {
      return;
    }

    addEvent(
      EventMarker(
        sequenceNumber: _sequenceNumber,
        timestampMicros: elapsedTime.inMicroseconds,
        type: 'annotation',
        description: text,
      ),
    );
  }

  /// Add an HRV packet to the recording
  ///
  /// HRV packets are stored separately from waveform samples and can be
  /// exported to CSV alongside the main recording data.
  void addHRVPacket(HRVPacketData packet) {
    if (_state != RecordingState.recording) {
      return;
    }

    _hrvPackets.add(packet);
    _hrvPacketsRecorded++;
  }

  /// Clear recorded HRV packets (called when resetting)
  void _clearHRVPackets() {
    _hrvPackets.clear();
    _hrvPacketsRecorded = 0;
  }

  /// Flush pre-buffer samples when starting recording
  List<MultiChannelSample> getPreBufferedSamples() {
    return List.from(_preBuffer);
  }

  /// Get current recording status
  RecordingStatus getCurrentStatus() {
    return RecordingStatus(
      state: _state,
      elapsedTime: elapsedTime,
      samplesRecorded: _samplesRecorded,
      fileSizeBytes: _fileSizeBytes,
      errorMessage: null,
    );
  }

  /// Get recording metadata (for saving)
  RecordingMetadata getMetadata() {
    return RecordingMetadata(
      deviceId: _metadata.deviceId,
      deviceName: _metadata.deviceName,
      firmwareVersion: _metadata.firmwareVersion,
      channels: _config?.channels ?? const [],
      subjectMetadata: _config?.subjectMetadata,
      sessionMetadata: _config?.sessionMetadata,
      recordingDuration: elapsedTime,
      totalSamples: _samplesRecorded,
    );
  }

  /// Get all recorded events
  List<EventMarker> getEvents() => List.from(_events);

  /// Generate default filename based on current session
  String generateDefaultFilename() {
    final dateFormat = DateFormat('yyyy-MM-dd_HH-mm-ss');
    final timestamp = dateFormat.format(DateTime.now());
    final sessionName = (_config?.sessionName ?? 'session').replaceAll(' ', '_');
    return 'recording_${sessionName}_$timestamp.hpd';
  }

  /// Generate full file path for recording
  Future<String> _generateFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(path.join(directory.path, 'HealthyPi_Recordings'));

    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final filename = generateDefaultFilename();
    return path.join(recordingsDir.path, filename);
  }

  /// Reset engine for new session
  void reset() {
    if (_state != RecordingState.stopped && _state != RecordingState.idle) {
      throw RecordingException(
        'Cannot reset recording in state: $_state',
      );
    }

    _state = RecordingState.idle;
    _currentFilePath = null;
    _sequenceNumber = 0;
    _samplesRecorded = 0;
    _fileSizeBytes = 0;
    _totalPausedTime = Duration.zero;
    _preBuffer.clear();
    _events.clear();
    _clearHRVPackets();
    _recordingStartTime = null;
    _pauseStartTime = null;

    _emitStatus();
    notifyListeners();
  }

  void _emitStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(getCurrentStatus());
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _statusController.close();
    super.dispose();
  }
}
