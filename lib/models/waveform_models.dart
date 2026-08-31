import 'package:flutter/material.dart';

/// Configuration for a single waveform channel
class ChannelConfiguration {
  /// Unique identifier for the channel
  final String id;

  /// Display name for the channel
  final String label;

  /// Unit of measurement (e.g., "mV", "BPM", "°C")
  final String unit;

  /// Current visibility state
  bool isVisible;

  /// Color for this channel's waveform
  Color color;

  /// Minimum value for scaling
  double minValue;

  /// Maximum value for scaling
  double maxValue;

  /// Vertical offset in pixels
  double verticalOffset;

  /// Whether to use auto-scaling
  bool autoScale;

  /// Line width for rendering
  double lineWidth;

  /// Whether to show grid for this channel
  bool showGrid;

  /// Number of decimal places to display
  int decimalPlaces;

  /// Grid color
  Color gridColor;

  /// Height ratio for this channel (1.0 = normal, 0.75 = 75% height)
  double heightRatio;

  ChannelConfiguration({
    required this.id,
    required this.label,
    required this.unit,
    this.isVisible = true,
    this.color = Colors.white,
    this.minValue = -1000,
    this.maxValue = 1000,
    this.verticalOffset = 0,
    this.autoScale = true,
    this.lineWidth = 2,
    this.showGrid = true,
    this.decimalPlaces = 2,
    this.gridColor = const Color(0xFF415A77),
    this.heightRatio = 1.0,
  });

  /// Create a copy with modified values
  ChannelConfiguration copyWith({
    String? id,
    String? label,
    String? unit,
    bool? isVisible,
    Color? color,
    double? minValue,
    double? maxValue,
    double? verticalOffset,
    bool? autoScale,
    double? lineWidth,
    bool? showGrid,
    int? decimalPlaces,
    Color? gridColor,
    double? heightRatio,
  }) {
    return ChannelConfiguration(
      id: id ?? this.id,
      label: label ?? this.label,
      unit: unit ?? this.unit,
      isVisible: isVisible ?? this.isVisible,
      color: color ?? this.color,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      verticalOffset: verticalOffset ?? this.verticalOffset,
      autoScale: autoScale ?? this.autoScale,
      lineWidth: lineWidth ?? this.lineWidth,
      showGrid: showGrid ?? this.showGrid,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      gridColor: gridColor ?? this.gridColor,
      heightRatio: heightRatio ?? this.heightRatio,
    );
  }
}

/// Global chart settings and configuration
class ChartSettings {
  /// Total number of visible channels
  int channelCount;

  /// Time window in seconds (1, 5, 10, 30, 60)
  double timeWindowSeconds;

  /// Whether chart is paused
  bool isPaused;

  /// Sampling rate in Hz
  double samplingRate;

  /// Background color
  Color backgroundColor;

  /// Axis label color
  Color labelColor;

  /// Show global grid
  bool showGlobalGrid;

  /// Global grid color
  Color globalGridColor;

  /// Grid line style density
  GridDensity gridDensity;

  /// Current zoom level (1.0 = normal, >1.0 = zoomed in)
  double zoomLevel;

  /// Show measurement cursors
  bool showCursors;

  /// Cursor positions (normalized 0-1)
  List<double> cursorPositions;

  /// Line interpolation style
  LineInterpolation interpolation;

  /// Animation enabled for smooth transitions
  bool enableAnimation;

  ChartSettings({
    this.channelCount = 4,
    this.timeWindowSeconds = 10.0,
    this.isPaused = false,
    this.samplingRate = 250.0,
    this.backgroundColor = const Color(0xFF0D1B2A),
    this.labelColor = Colors.white,
    this.showGlobalGrid = true,
    this.globalGridColor = const Color(0xFF415A77),
    this.gridDensity = GridDensity.medium,
    this.zoomLevel = 1.0,
    this.showCursors = false,
    this.cursorPositions = const [],
    this.interpolation = LineInterpolation.linear,
    this.enableAnimation = true,
  });

  /// Copy with modified values
  ChartSettings copyWith({
    int? channelCount,
    double? timeWindowSeconds,
    bool? isPaused,
    double? samplingRate,
    Color? backgroundColor,
    Color? labelColor,
    bool? showGlobalGrid,
    Color? globalGridColor,
    GridDensity? gridDensity,
    double? zoomLevel,
    bool? showCursors,
    List<double>? cursorPositions,
    LineInterpolation? interpolation,
    bool? enableAnimation,
  }) {
    return ChartSettings(
      channelCount: channelCount ?? this.channelCount,
      timeWindowSeconds: timeWindowSeconds ?? this.timeWindowSeconds,
      isPaused: isPaused ?? this.isPaused,
      samplingRate: samplingRate ?? this.samplingRate,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      labelColor: labelColor ?? this.labelColor,
      showGlobalGrid: showGlobalGrid ?? this.showGlobalGrid,
      globalGridColor: globalGridColor ?? this.globalGridColor,
      gridDensity: gridDensity ?? this.gridDensity,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      showCursors: showCursors ?? this.showCursors,
      cursorPositions: cursorPositions ?? this.cursorPositions,
      interpolation: interpolation ?? this.interpolation,
      enableAnimation: enableAnimation ?? this.enableAnimation,
    );
  }
}

/// Enumeration for grid density levels
enum GridDensity {
  sparse,
  medium,
  dense,
}

/// Enumeration for line interpolation styles
enum LineInterpolation {
  linear,
  smooth,
}

/// Single data point with timestamp
class DataPoint {
  final double value;
  final DateTime timestamp;
  final int sampleIndex;

  DataPoint({
    required this.value,
    required this.timestamp,
    required this.sampleIndex,
  });

  @override
  String toString() => 'DataPoint(value: ${value.toStringAsFixed(2)}, time: $timestamp)';
}

/// Container for all channel data and metadata
class ChannelData {
  /// Configuration for this channel
  ChannelConfiguration config;

  /// Sampling rate in Hz for this specific channel
  /// (ECG: 500 Hz, PPG: 125 Hz, Temperature: 1 Hz, etc.)
  double samplingRate;

  /// Circular buffer of data points
  final List<DataPoint> buffer;

  /// Maximum buffer size
  final int maxBufferSize;

  /// Current write position in circular buffer
  int writeIndex = 0;

  /// Whether buffer is full (wrapped around)
  bool isBufferFull = false;

  /// Sample index for this specific channel (independent from others)
  int channelSampleIndex = 0;

  /// Cached window data (updated only when buffer changes)
  List<DataPoint>? _cachedWindowData;

  /// Last buffer state we cached from
  int? _lastCachedWriteIndex;

  /// Minimum value in current buffer
  double _minInBuffer = 0;

  /// Maximum value in current buffer
  double _maxInBuffer = 0;

  /// Counter for throttling stat updates (update every N samples)
  int _statsUpdateCounter = 0;
  static const int _statsUpdateInterval = 50; // Recalculate min/max every 50 samples (~100ms at 500Hz)

  ChannelData({
    required this.config,
    this.samplingRate = 500.0,
    this.maxBufferSize = 8000, // Support 8 seconds at 1kHz or 32 seconds at 250Hz
  }) : buffer = List<DataPoint>.filled(
    8000,
    DataPoint(value: 0, timestamp: DateTime.now(), sampleIndex: 0),
    growable: false,
  );

  /// Add a new data point to the buffer
  void addDataPoint(DataPoint point) {
    buffer[writeIndex] = point;
    writeIndex = (writeIndex + 1) % maxBufferSize;
    if (writeIndex == 0) {
      isBufferFull = true;
    }
    
    // Throttle stats updates (recalculate every N samples, not every sample)
    _statsUpdateCounter++;
    if (_statsUpdateCounter >= _statsUpdateInterval) {
      _statsUpdateCounter = 0;
      _updateStats();
    }
  }

  /// Get data points in the current time window (using this channel's sampling rate)
  List<DataPoint> getDataInWindow(double windowSeconds, double globalSamplingRate) {
    // Use this channel's actual sampling rate for accurate time window
    final pointsInWindow = (windowSeconds * samplingRate).toInt().clamp(1, maxBufferSize);
    
    // Return cached data if buffer hasn't changed
    if (_cachedWindowData != null && _lastCachedWriteIndex == writeIndex && _cachedWindowData!.length == pointsInWindow) {
      return _cachedWindowData!;
    }

    final result = <DataPoint>[];

    if (isBufferFull) {
      // Buffer has wrapped around - get most recent pointsInWindow samples
      for (int i = 0; i < pointsInWindow; i++) {
        final index = (writeIndex + i) % maxBufferSize;
        result.add(buffer[index]);
      }
    } else {
      // Buffer not full yet - return available samples within window
      final availablePoints = writeIndex;
      final startIndex = (availablePoints - pointsInWindow).clamp(0, availablePoints).toInt();
      for (int i = startIndex; i < availablePoints; i++) {
        result.add(buffer[i]);
      }
    }

    // Cache the result for next frame
    _cachedWindowData = result;
    _lastCachedWriteIndex = writeIndex;

    return result;
  }

  /// Update min/max statistics
  /// Only scans the VISIBLE time window (not entire buffer) for responsive autoscaling
  /// Default window: ~2 seconds worth of samples for quick response to signal changes
  void _updateStats() {
    if (writeIndex == 0 && !isBufferFull) {
      _minInBuffer = 0;
      _maxInBuffer = 0;
      return;
    }

    // Only scan recent samples in a short window for responsive autoscaling
    // Use ~2 seconds of data (1000 samples at 500Hz) for fast response to lead changes
    // This is much smaller than the full buffer (8000 samples) or display window (2500-5000)
    const int statsWindowSize = 1000;

    final int availableSamples = isBufferFull ? maxBufferSize : writeIndex;
    final int samplesToScan = availableSamples < statsWindowSize ? availableSamples : statsWindowSize;

    if (samplesToScan == 0) {
      _minInBuffer = 0;
      _maxInBuffer = 0;
      return;
    }

    // Start from the most recent sample and work backwards
    // writeIndex points to where the NEXT sample will be written
    // So (writeIndex - 1) is the most recent sample
    int startIndex = (writeIndex - 1 + maxBufferSize) % maxBufferSize;

    double min = buffer[startIndex].value;
    double max = buffer[startIndex].value;

    for (int i = 0; i < samplesToScan; i++) {
      final index = (startIndex - i + maxBufferSize) % maxBufferSize;
      final value = buffer[index].value;
      if (value < min) min = value;
      if (value > max) max = value;
    }

    _minInBuffer = min;
    _maxInBuffer = max;
  }

  /// Get minimum value in buffer
  double get minInBuffer => _minInBuffer;

  /// Get maximum value in buffer
  double get maxInBuffer => _maxInBuffer;

  /// Clear all data
  void clear() {
    writeIndex = 0;
    isBufferFull = false;
    _minInBuffer = 0;
    _maxInBuffer = 0;
    _statsUpdateCounter = 0;
  }

  /// Get current statistics string
  String getStatsString() {
    final lastPoint = buffer[(writeIndex - 1 + maxBufferSize) % maxBufferSize];
    return '${lastPoint.value.toStringAsFixed(config.decimalPlaces)} ${config.unit} '
        '[Min: ${_minInBuffer.toStringAsFixed(config.decimalPlaces)}, '
        'Max: ${_maxInBuffer.toStringAsFixed(config.decimalPlaces)}]';
  }
}

/// Predefined channel presets for common use cases
class ChannelPresets {
  // OpenView Format: 3 ECG channels (standard 3-lead configuration)
  static final ecg1Channel = ChannelConfiguration(
    id: 'ecg1',
    label: 'LEAD-I',
    unit: 'mV',
    color: const Color(0xFFFF0000),
    minValue: -500,
    maxValue: 500,
    lineWidth: 1.5,
  );

  static final ecg2Channel = ChannelConfiguration(
    id: 'ecg2',
    label: 'LEAD-II',
    unit: 'mV',
    color: const Color(0xFFFF6B35),
    minValue: -500,
    maxValue: 500,
    lineWidth: 1.5,
  );

  static final ecg3Channel = ChannelConfiguration(
    id: 'ecg3',
    label: 'V1',
    unit: 'mV',
    color: const Color(0xFFFFB84D),
    minValue: -500,
    maxValue: 500,
    lineWidth: 1.5,
  );

  // OpenView Format: Respiration/BioZ
  static final respirationChannel = ChannelConfiguration(
    id: 'respiration',
    label: 'Respiration',
    unit: 'mV',
    color: const Color(0xFF00FF00),
    minValue: -500,
    maxValue: 500,
    lineWidth: 1.5,
  );

  // OpenView Format: PPG (using Red channel as primary)
  // Note: PPG always uses autoscale since it has no specific unit
  static final ppgChannel = ChannelConfiguration(
    id: 'ppg',
    label: 'PPG',
    unit: 'a.u.',
    color: const Color(0xFF00FFFF),
    minValue: -500,
    maxValue: 500,
    lineWidth: 1.5,
    autoScale: true,
  );

  // OpenView Format: Temperature
  static final temperatureChannel = ChannelConfiguration(
    id: 'temperature',
    label: 'Temperature',
    unit: '°C',
    color: const Color(0xFFFF69B4),
    minValue: 35,
    maxValue: 40,
    lineWidth: 1.5,
  );

  // Vitals (non-waveform)
  static final heartRateChannel = ChannelConfiguration(
    id: 'heart_rate',
    label: 'Heart Rate',
    unit: 'BPM',
    color: const Color(0xFFFF0000),
    minValue: 40,
    maxValue: 200,
    lineWidth: 2,
  );

  static final spo2Channel = ChannelConfiguration(
    id: 'spo2',
    label: 'SpO₂',
    unit: '%',
    color: const Color(0xFF0066FF),
    minValue: 90,
    maxValue: 100,
    lineWidth: 2,
  );

  // ADC Extension Channels (INP14/PA2 and INP15/PA3)
  static final adcChannel1 = ChannelConfiguration(
    id: 'adc1',
    label: 'ADC1',
    unit: 'mV',
    color: const Color(0xFFAA55FF),
    minValue: -500,
    maxValue: 500,
    lineWidth: 1.5,
    autoScale: true,
    heightRatio: 0.75,
  );

  static final adcChannel2 = ChannelConfiguration(
    id: 'adc2',
    label: 'ADC2',
    unit: 'mV',
    color: const Color(0xFF55AAFF),
    minValue: -500,
    maxValue: 500,
    lineWidth: 1.5,
    autoScale: true,
    heightRatio: 0.75,
  );

  // EEG Channels (from ADS1299 8-channel EEG at 250 Hz)
  // Typical EEG amplitude: ±10 to ±100 µV
  static final eegChannel1 = ChannelConfiguration(
    id: 'eeg1',
    label: 'EEG Fp1',
    unit: 'µV',
    color: const Color(0xFF4CAF50), // Green
    minValue: -100,
    maxValue: 100,
    lineWidth: 1.0,
    autoScale: true,
    heightRatio: 0.75,
  );

  static final eegChannel2 = ChannelConfiguration(
    id: 'eeg2',
    label: 'EEG Fp2',
    unit: 'µV',
    color: const Color(0xFF2196F3), // Blue
    minValue: -100,
    maxValue: 100,
    lineWidth: 1.0,
    autoScale: true,
    heightRatio: 0.75,
  );
}
