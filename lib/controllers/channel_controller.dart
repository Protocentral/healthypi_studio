import 'dart:io';

import 'package:flutter/material.dart';
import '../models/waveform_models.dart';
import '../models/recording_models.dart';
import '../services/filter_integration_service.dart';

/// Information about a completed recording
class RecordingCompletionInfo {
  final Duration duration;
  final int totalSamples;

  /// Absolute path of the `.hpd` the engine wrote, or null if it never opened
  /// one (recording was UI-only because no engine was attached).
  final String? filePath;
  final DateTime completedAt;

  RecordingCompletionInfo({
    required this.duration,
    required this.totalSamples,
    required this.filePath,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  /// Just the file name, for display.
  String? get fileName => filePath?.split(Platform.pathSeparator).last;
}

/// Manages multiple waveform channels with data streaming and synchronization
class ChannelController extends ChangeNotifier {
  /// Map of channel ID to channel data
  final Map<String, ChannelData> _channels = {};

  /// Chart settings
  ChartSettings _settings;

  /// Current sample index (synchronized across all channels)
  int _currentSampleIndex = 0;

  /// Recording start time
  DateTime? _recordingStartTime;

  /// Total samples recorded
  int _totalSamplesRecorded = 0;

  /// Last completed recording information (null if no recording completed yet)
  RecordingCompletionInfo? _lastCompletedRecording;

  /// Recording bridge (optional - set when recording is needed)
  dynamic _recordingBridge;

  /// Recording engine (optional - set when recording is needed)
  dynamic _recordingEngine;

  /// Filter service (optional - injected for filtering support)
  FilterIntegrationService? _filterService;

  /// Counter for throttling autoscaling updates (update every N samples for performance)
  int _autoscaleUpdateCounter = 0;
  static const int _autoscaleUpdateInterval = 50; // Update autoscale every 50 samples (~100ms at 500Hz) for faster response

  /// Counter for throttling recording UI updates
  int _recordingUpdateCounter = 0;
  static const int _recordingUpdateInterval = 500; // Update recording UI every 500 samples (~1 second at 500 Hz)

  /// Sample rate measurement for debugging
  final Map<String, int> _samplesPerSecond = {};
  final Map<String, DateTime> _lastMeasurementTime = {};
  static const int _measurementInterval = 1000; // Measure every 1 second (ms)

  /// Constructor
  ChannelController({
    ChartSettings? initialSettings,
    List<ChannelConfiguration>? initialChannels,
    FilterIntegrationService? filterService,
  }) : _settings = initialSettings ?? ChartSettings(),
       _filterService = filterService {
    // Initialize channels with appropriate sampling rates
    if (initialChannels != null) {
      for (final config in initialChannels) {
        // Set per-channel sampling rate based on channel ID
        final samplingRate = _getSamplingRateForChannel(config.id);
        _channels[config.id] = ChannelData(config: config, samplingRate: samplingRate);
      }
    }
  }

  /// Get the appropriate sampling rate for a given channel ID
  /// Based on HealthyPi 6 / OpenView protocol specifications
  ///
  /// IMPORTANT: USB streams at 500 Hz, WiFi streams at 250 Hz
  /// The actual rate should be set dynamically based on connection type
  double _getSamplingRateForChannel(String channelId) {
    // Use the global sampling rate from settings for ECG/Respiration channels
    // This allows dynamic adjustment based on USB (500 Hz) vs WiFi (250 Hz)
    final baseSamplingRate = _settings.samplingRate;

    switch (channelId) {
      case 'ecg1':
      case 'ecg2':
      case 'ecg3':
      case 'respiration':
      case 'adc1':
      case 'adc2':
        return baseSamplingRate; // Use global rate: 500 Hz for USB, 250 Hz for WiFi
      case 'ppg':
        return baseSamplingRate / 4; // PPG: 1/4 of base rate (125 Hz for USB, 62.5 Hz for WiFi)
      case 'temperature':
        return 1.0; // Temperature: 1 Hz (update once per second)
      case 'heart_rate':
      case 'spo2':
        return 1.0; // Vitals: 1 Hz updates
      default:
        return baseSamplingRate; // Default to global sampling rate
    }
  }

  /// Update sampling rate for all channels (call when switching between USB/WiFi)
  /// USB = 500 Hz, WiFi = 250 Hz
  void updateSamplingRate(double newSamplingRate) {
    debugPrint('📊 Updating global sampling rate: ${_settings.samplingRate} Hz → $newSamplingRate Hz');
    _settings = _settings.copyWith(samplingRate: newSamplingRate);

    // Update each channel's sampling rate based on new base rate
    for (final entry in _channels.entries) {
      final channelId = entry.key;
      final newChannelRate = _getSamplingRateForChannel(channelId);
      entry.value.samplingRate = newChannelRate;
      debugPrint('  📈 Channel $channelId: ${entry.value.samplingRate} Hz → $newChannelRate Hz');
    }

    notifyListeners();
  }

  // ============= GETTERS =============

  /// Get all channels
  Map<String, ChannelData> get channels => Map.unmodifiable(_channels);

  /// Get current settings
  ChartSettings get settings => _settings;

  /// Get visible channels only
  Map<String, ChannelData> get visibleChannels {
    final result = <String, ChannelData>{};
    for (final entry in _channels.entries) {
      if (entry.value.config.isVisible) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Get number of visible channels
  int get visibleChannelCount => visibleChannels.length;

  /// Get channel by ID
  ChannelData? getChannel(String channelId) => _channels[channelId];

  /// Get current sample index
  int get currentSampleIndex => _currentSampleIndex;

  /// Get total samples recorded
  int get totalSamplesRecorded => _totalSamplesRecorded;

  /// Get recording duration
  Duration? get recordingDuration {
    if (_recordingStartTime == null) return null;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Check if recording
  bool get isRecording => _recordingStartTime != null;

  /// Get last completed recording info (null if no recording completed yet)
  RecordingCompletionInfo? get lastCompletedRecording => _lastCompletedRecording;

  /// Clear last completed recording info (call after user has seen the dialog)
  void clearLastCompletedRecording() {
    _lastCompletedRecording = null;
    notifyListeners();
  }

  /// Set recording engine (for actual file recording)
  void setRecordingEngine(dynamic recordingEngine) {
    _recordingEngine = recordingEngine;
  }

  // ============= CHANNEL MANAGEMENT =============

  /// Add a new channel
  void addChannel(ChannelConfiguration config) {
    if (_channels.containsKey(config.id)) {
      throw ArgumentError('Channel with ID ${config.id} already exists');
    }
    final samplingRate = _getSamplingRateForChannel(config.id);
    _channels[config.id] = ChannelData(config: config, samplingRate: samplingRate);
    notifyListeners();
  }

  /// Remove a channel
  void removeChannel(String channelId) {
    _channels.remove(channelId);
    notifyListeners();
  }

  /// Update channel configuration
  void updateChannelConfig(String channelId, ChannelConfiguration newConfig) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      channelData.config = newConfig;
      notifyListeners();
    }
  }

  /// Toggle channel visibility
  void toggleChannelVisibility(String channelId) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      channelData.config.isVisible = !channelData.config.isVisible;
      notifyListeners();
    }
  }

  /// Set channel color
  void setChannelColor(String channelId, Color color) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      channelData.config.color = color;
      notifyListeners();
    }
  }

  /// Set channel scale
  void setChannelScale(String channelId, double minValue, double maxValue) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      channelData.config.minValue = minValue;
      channelData.config.maxValue = maxValue;
      notifyListeners();
    }
  }

  /// Set auto-scale for channel
  void setChannelAutoScale(String channelId, bool autoScale) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      channelData.config.autoScale = autoScale;
      if (autoScale) {
        _autoScaleChannel(channelId);
      }
      notifyListeners();
    }
  }

  /// Set vertical offset for channel
  void setChannelVerticalOffset(String channelId, double offset) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      channelData.config.verticalOffset = offset;
      notifyListeners();
    }
  }

  // ============= DATA MANAGEMENT =============

  /// Add a data point to a channel
  void addDataPoint(String channelId, double value) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      final point = DataPoint(
        value: value,
        timestamp: DateTime.now(),
        sampleIndex: channelData.channelSampleIndex,
      );
      channelData.addDataPoint(point);
      channelData.channelSampleIndex++; // Increment channel's own sample index
      _totalSamplesRecorded++;
      
      // Measure samples per second for debugging
      final now = DateTime.now();
      _lastMeasurementTime.putIfAbsent(channelId, () => now);
      final elapsed = now.difference(_lastMeasurementTime[channelId]!).inMilliseconds;
      
      if (elapsed >= _measurementInterval) {
        // Disabled sample rate logging to reduce console clutter and CPU usage
        // Sample rate is displayed on the main UI instead
        
        _samplesPerSecond[channelId] = 0;
        _lastMeasurementTime[channelId] = now;
      } else {
        _samplesPerSecond[channelId] = (_samplesPerSecond[channelId] ?? 0) + 1;
      }
    }
  }

  /// Set recording bridge for automatic data forwarding during recording
  void setRecordingBridge(dynamic bridge) {
    _recordingBridge = bridge;
  }

  /// Set filter service for real-time filtering support
  /// This should be called after construction to inject the Provider-managed service
  void setFilterService(FilterIntegrationService service) {
    _filterService = service;
  }

  /// Add data point to multiple channels at once (synchronized)
  /// If filtering is enabled, applies filters before storing data
  /// Note: Each channel manages its own sample index independently
  /// PPG valid flag from firmware automatically decimates to ~125 Hz (only added when valid)
  /// PERFORMANCE: Does NOT call notifyListeners() - data updates don't need UI rebuilds
  /// UI updates happen when chart reads data from buffers on paint events
  void addDataPointsSync(Map<String, double> channelValues) {
    // Apply filtering if enabled (use injected service if available, else fall back to extension)
    final filters = _filterService ?? filterService;
    Map<String, double> processedValues = channelValues;

    if (filters.isFilteringEnabled) {
      processedValues = {};
      for (final entry in channelValues.entries) {
        final filtered = filters.processSample(entry.key, entry.value);
        // Protect against NaN/Infinity from unstable filters - pass through original value
        if (filtered.isNaN || filtered.isInfinite) {
          processedValues[entry.key] = entry.value;
        } else {
          processedValues[entry.key] = filtered;
        }
      }
    }

    // Store processed data - each channel increments its own index
    for (final entry in processedValues.entries) {
      addDataPoint(entry.key, entry.value);
    }

    // Track recording samples
    if (isRecording) {
      _totalSamplesRecorded += processedValues.length;

      // Notify listeners periodically for recording UI updates (every ~1 second)
      _recordingUpdateCounter++;
      if (_recordingUpdateCounter >= _recordingUpdateInterval) {
        _recordingUpdateCounter = 0;
        notifyListeners(); // Update recording status display
      }
    }

    // Forward to recording bridge if recording is active
    if (_recordingBridge != null) {
      _recordingBridge.onDataAdded(processedValues);
    }

    // Auto-scale channels that have autoscale enabled
    // Throttled to every N samples for performance (don't recalculate on every point)
    _autoscaleUpdateCounter++;

    // Check if any value is significantly outside current range (needs immediate rescale)
    bool needsImmediateRescale = false;
    for (final entry in processedValues.entries) {
      final channelData = _channels[entry.key];
      if (channelData != null && channelData.config.autoScale) {
        final range = channelData.config.maxValue - channelData.config.minValue;
        final value = entry.value;
        // If value is more than 50% outside current range, force immediate rescale
        if (value < channelData.config.minValue - range * 0.5 ||
            value > channelData.config.maxValue + range * 0.5) {
          needsImmediateRescale = true;
          break;
        }
      }
    }

    if (needsImmediateRescale || _autoscaleUpdateCounter >= _autoscaleUpdateInterval) {
      _autoscaleUpdateCounter = 0;
      for (final entry in processedValues.entries) {
        final channelData = _channels[entry.key];
        if (channelData != null && channelData.config.autoScale) {
          _autoScaleChannel(entry.key);
        }
      }
    }
    
    // NOTE: DO NOT call notifyListeners() here!
    // Data updates are read directly by the chart painter from channel buffers.
    // Calling notifyListeners() 500 times per second causes massive UI lag.
  }

  /// Add data point to a single channel (synchronizes index automatically)
  void addDataPointSyncIndex(String channelId, double value) {
    addDataPoint(channelId, value);
    notifyListeners();
  }

  /// Get data points for a channel within the current time window
  List<DataPoint> getChannelData(String channelId) {
    final channelData = _channels[channelId];
    if (channelData == null) return [];
    return channelData.getDataInWindow(_settings.timeWindowSeconds, _settings.samplingRate);
  }

  /// Clear all data
  void clearAllData() {
    for (final channelData in _channels.values) {
      channelData.clear();
      channelData.channelSampleIndex = 0; // Reset per-channel indices
    }
    _currentSampleIndex = 0;
    _totalSamplesRecorded = 0;
    notifyListeners();
  }

  /// Clear specific channel data
  void clearChannelData(String channelId) {
    final channelData = _channels[channelId];
    if (channelData != null) {
      channelData.clear();
      channelData.channelSampleIndex = 0; // Reset this channel's index
      notifyListeners();
    }
  }

  // ============= SETTINGS MANAGEMENT =============

  /// Update chart settings
  void updateSettings(ChartSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  /// Set time window
  void setTimeWindow(double seconds) {
    _settings = _settings.copyWith(timeWindowSeconds: seconds);
    notifyListeners();
  }

  /// Set sampling rate
  void setSamplingRate(double rate) {
    _settings = _settings.copyWith(samplingRate: rate);
    notifyListeners();
  }

  /// Toggle pause
  void togglePause() {
    _settings = _settings.copyWith(isPaused: !_settings.isPaused);
    notifyListeners();
  }

  /// Set pause state
  void setPauseState(bool paused) {
    _settings = _settings.copyWith(isPaused: paused);
    notifyListeners();
  }

  /// Set zoom level
  void setZoomLevel(double zoom) {
    _settings = _settings.copyWith(zoomLevel: zoom.clamp(0.5, 10.0));
    notifyListeners();
  }

  /// Adjust zoom in
  void zoomIn() {
    final newZoom = (_settings.zoomLevel * 1.2).clamp(0.5, 10.0);
    setZoomLevel(newZoom);
  }

  /// Adjust zoom out
  void zoomOut() {
    final newZoom = (_settings.zoomLevel / 1.2).clamp(0.5, 10.0);
    setZoomLevel(newZoom);
  }

  // ============= RECORDING MANAGEMENT =============

  /// Start recording
  Future<void> startRecording() async {
    _recordingStartTime = DateTime.now();
    _totalSamplesRecorded = 0;
    _recordingUpdateCounter = 0;
    notifyListeners();
    debugPrint('🔴 Recording started (UI state)');

    // Start the actual RecordingEngine if available
    if (_recordingEngine != null) {
      try {
        // Create recording config from current channels
        final channelInfoList = <ChannelInfo>[];

        for (final entry in _channels.entries) {
          final channelId = entry.key;
          final channelData = entry.value;
          final channelConfig = channelData.config;

          // Only include visible channels
          if (channelConfig.isVisible) {
            channelInfoList.add(ChannelInfo(
              id: channelId,
              name: channelConfig.label,
              unit: channelConfig.unit,
              samplingRate: channelData.samplingRate,
              gainFactor: 1.0,
              offset: 0.0,
              minValue: channelConfig.minValue,
              maxValue: channelConfig.maxValue,
            ));
          }
        }

        final config = RecordingConfig(
          sessionName: 'Recording_${DateTime.now().toString().replaceAll(' ', '_')}',
          channels: channelInfoList,
        );

        await _recordingEngine.startRecording(config);
        debugPrint('✅ RecordingEngine started with ${channelInfoList.length} channels');
      } catch (e) {
        debugPrint('❌ Failed to start RecordingEngine: $e');
      }
    } else {
      debugPrint('⚠️ RecordingEngine not set - recording only UI state');
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!isRecording) return;

    final duration = recordingDuration!;
    final samples = _totalSamplesRecorded;

    // Stop the actual RecordingEngine if available
    if (_recordingEngine != null) {
      try {
        await _recordingEngine.stopRecording();
        debugPrint('✅ RecordingEngine stopped');
      } catch (e) {
        debugPrint('❌ Failed to stop RecordingEngine: $e');
      }
    }

    // The file the engine actually wrote — not a name rebuilt from the clock,
    // which drifted from the real one by the session name and the seconds spent
    // finalising the file.
    final filePath = _recordingEngine?.currentFilePath as String?;

    _lastCompletedRecording = RecordingCompletionInfo(
      duration: duration,
      totalSamples: samples,
      filePath: filePath,
    );

    _recordingStartTime = null;
    _recordingUpdateCounter = 0;
    notifyListeners();

    debugPrint('⏹️ Recording stopped: ${duration.inSeconds}s, $samples samples '
        '→ ${filePath ?? "no file"}');
  }

  // ============= AUTO-SCALING =============

  /// Auto-scale a single channel based on current data
  void _autoScaleChannel(String channelId) {
    final channelData = _channels[channelId];
    if (channelData != null && channelData.buffer.isNotEmpty) {
      final min = channelData.minInBuffer;
      final max = channelData.maxInBuffer;

      // Calculate range with minimum threshold to prevent too-tight scaling
      var range = max - min;

      // Ensure minimum range to prevent division issues and overly tight scaling
      // Use 1% of the center value as minimum range, or 1.0 if center is near zero
      final center = (max + min) / 2;
      final minRange = (center.abs() * 0.01).clamp(1.0, double.infinity);
      if (range < minRange) {
        range = minRange;
      }

      // Add 15% padding for better visual margin
      final padding = range * 0.15;

      channelData.config.minValue = min - padding;
      channelData.config.maxValue = max + padding;
    }
  }

  /// Auto-scale all channels
  void autoScaleAll() {
    for (final channelId in _channels.keys) {
      if (_channels[channelId]!.config.autoScale) {
        _autoScaleChannel(channelId);
      }
    }
    notifyListeners();
  }

  // ============= STATISTICS & STATUS =============

  /// Get statistics for a channel
  String getChannelStats(String channelId) {
    final channelData = _channels[channelId];
    return channelData?.getStatsString() ?? 'No data';
  }

  /// Get all channel statistics
  Map<String, String> getAllStats() {
    final result = <String, String>{};
    for (final entry in _channels.entries) {
      result[entry.key] = entry.value.getStatsString();
    }
    return result;
  }

  /// Get recording info string
  String getRecordingInfo() {
    if (!isRecording) return 'Not Recording';
    final duration = recordingDuration;
    final samples = _totalSamplesRecorded;
    return 'Recording: ${duration?.inSeconds}s | Samples: $samples | '
        'Rate: ${(_settings.samplingRate).toStringAsFixed(0)} Hz';
  }

  // ============= EXPORT & SERIALIZATION =============

  /// Export channel data as CSV
  String exportAsCSV(String channelId) {
    final channelData = _channels[channelId];
    if (channelData == null) return '';

    final buffer = StringBuffer();
    buffer.writeln('timestamp,sampleIndex,value');

    for (final point in channelData.buffer) {
      if (point.sampleIndex >= 0) {
        buffer.writeln(
          '${point.timestamp.toIso8601String()},${point.sampleIndex},${point.value}',
        );
      }
    }

    return buffer.toString();
  }

  /// Export all visible channels as CSV
  String exportAllAsCSV() {
    final buffer = StringBuffer();
    final visibleIds = visibleChannels.keys.toList();

    // Header
    buffer.write('timestamp,sampleIndex');
    for (final id in visibleIds) {
      buffer.write(',$id');
    }
    buffer.writeln();

    // Data (sync all channels by sample index)
    final maxSamples = _channels.values
        .fold<int>(0, (max, ch) => ch.buffer.length > max ? ch.buffer.length : max);

    for (int i = 0; i < maxSamples; i++) {
      final firstChannel = _channels.values.first;
      if (i < firstChannel.buffer.length) {
        final timestamp = firstChannel.buffer[i].timestamp;
        final sampleIndex = firstChannel.buffer[i].sampleIndex;

        buffer.write('$timestamp,$sampleIndex');
        for (final id in visibleIds) {
          final data = _channels[id];
          final value = i < data!.buffer.length ? data.buffer[i].value : '';
          buffer.write(',$value');
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  @override
  void dispose() {
    _channels.clear();
    super.dispose();
  }
}
