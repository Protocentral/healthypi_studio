import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/data_parser.dart';

/// Single EEG sample from all 8 channels
///
/// Wraps the raw EEGPacketData with convenient double conversions
/// and combined lead-off status for easier processing.
class EegSample {
  /// Device timestamp in milliseconds
  final int timestampMs;

  /// Channel values in microvolts as doubles (8 channels)
  final List<double> channelsMicrovolts;

  /// Combined lead-off bitmask (positive | negative)
  final int leadOffStatus;

  /// Signal quality (0-100%)
  final int quality;

  /// Sequence number for packet loss detection
  final int sequenceNumber;

  EegSample({
    required this.timestampMs,
    required this.channelsMicrovolts,
    required this.leadOffStatus,
    required this.quality,
    required this.sequenceNumber,
  });

  /// Convert from raw EEGPacketData
  factory EegSample.fromPacket(EEGPacketData packet) {
    return EegSample(
      timestampMs: packet.timestampMs,
      channelsMicrovolts: packet.channels.map((v) => v.toDouble()).toList(),
      leadOffStatus: packet.leadOffPositive | packet.leadOffNegative,
      quality: packet.signalQuality,
      sequenceNumber: packet.sequenceNumber,
    );
  }

  /// Check if a specific channel (0-7) is connected
  bool isChannelConnected(int channel) {
    if (channel < 0 || channel > 7) return false;
    return (leadOffStatus & (1 << channel)) == 0;
  }

  /// Get value for specific channel in microvolts
  double getChannel(int channel) {
    if (channel < 0 || channel >= channelsMicrovolts.length) return 0.0;
    return channelsMicrovolts[channel];
  }
}

/// Configuration for a single EEG channel
class EegChannelConfig {
  /// Channel index (0-7)
  final int channelIndex;

  /// Display label (e.g., "Fp1", "O2")
  final String label;

  /// Display color
  final Color color;

  /// Whether channel is enabled for display
  final bool enabled;

  /// Gain multiplier for display scaling (default 1.0)
  final double gainMultiplier;

  /// Vertical offset for stacked display (in µV)
  final double verticalOffset;

  const EegChannelConfig({
    required this.channelIndex,
    required this.label,
    required this.color,
    this.enabled = true,
    this.gainMultiplier = 1.0,
    this.verticalOffset = 0.0,
  });

  /// Standard 10-20 system default labels for 8-channel montage
  static const List<String> defaultLabels = [
    'Fp1', 'Fp2', 'F3', 'F4', 'C3', 'C4', 'O1', 'O2'
  ];

  /// Default colors for 8 channels
  static const List<Color> defaultColors = [
    Color(0xFF4CAF50), // Green
    Color(0xFF2196F3), // Blue
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFFE91E63), // Pink
    Color(0xFF00BCD4), // Cyan
    Color(0xFFFFEB3B), // Yellow
    Color(0xFFF44336), // Red
  ];

  /// Create default configuration for all 8 channels
  static List<EegChannelConfig> createDefaultConfigs() {
    return List.generate(8, (i) => EegChannelConfig(
      channelIndex: i,
      label: defaultLabels[i],
      color: defaultColors[i],
      enabled: true,
      gainMultiplier: 1.0,
    ));
  }

  /// Copy with modifications
  EegChannelConfig copyWith({
    int? channelIndex,
    String? label,
    Color? color,
    bool? enabled,
    double? gainMultiplier,
    double? verticalOffset,
  }) {
    return EegChannelConfig(
      channelIndex: channelIndex ?? this.channelIndex,
      label: label ?? this.label,
      color: color ?? this.color,
      enabled: enabled ?? this.enabled,
      gainMultiplier: gainMultiplier ?? this.gainMultiplier,
      verticalOffset: verticalOffset ?? this.verticalOffset,
    );
  }
}

/// Circular buffer for efficient EEG waveform storage and retrieval
///
/// Optimized for real-time visualization with:
/// - O(1) sample insertion
/// - Efficient retrieval of last N samples
/// - Support for FFT-compatible power-of-2 extraction
class EegRingBuffer {
  /// Buffer capacity in samples
  final int capacity;

  /// Number of channels (always 8 for EEG)
  static const int channelCount = 8;

  /// Internal storage: [channel][sample]
  late final List<Float64List> _data;

  /// Current write position
  int _writeIndex = 0;

  /// Total samples written (may exceed capacity)
  int _totalSamplesWritten = 0;

  /// Timestamps for each sample position
  late final Int32List _timestamps;

  EegRingBuffer({this.capacity = 1250}) {
    // Initialize storage for 8 channels
    _data = List.generate(channelCount, (_) => Float64List(capacity));
    _timestamps = Int32List(capacity);
  }

  /// Number of valid samples in buffer (0 to capacity)
  int get sampleCount => _totalSamplesWritten < capacity
      ? _totalSamplesWritten
      : capacity;

  /// Whether buffer is full
  bool get isFull => _totalSamplesWritten >= capacity;

  /// Add a sample to the buffer
  void addSample(EegSample sample) {
    // Store channel values
    for (int ch = 0; ch < channelCount; ch++) {
      _data[ch][_writeIndex] = sample.channelsMicrovolts[ch];
    }

    // Store timestamp
    _timestamps[_writeIndex] = sample.timestampMs;

    // Advance write pointer
    _writeIndex = (_writeIndex + 1) % capacity;
    _totalSamplesWritten++;
  }

  /// Add raw packet directly (avoids EegSample allocation)
  void addPacket(EEGPacketData packet) {
    for (int ch = 0; ch < channelCount; ch++) {
      _data[ch][_writeIndex] = packet.channels[ch].toDouble();
    }
    _timestamps[_writeIndex] = packet.timestampMs;
    _writeIndex = (_writeIndex + 1) % capacity;
    _totalSamplesWritten++;
  }

  /// Get data for a specific channel
  ///
  /// Returns samples in chronological order (oldest first).
  /// If [lastNSamples] is specified, returns only the most recent N samples.
  List<double> getChannel(int channel, {int? lastNSamples}) {
    if (channel < 0 || channel >= channelCount) return [];

    final count = lastNSamples != null
        ? lastNSamples.clamp(0, sampleCount)
        : sampleCount;

    if (count == 0) return [];

    final result = Float64List(count);

    // Calculate starting index
    int readIndex;
    if (_totalSamplesWritten < capacity) {
      // Buffer not full yet, start from beginning
      readIndex = _totalSamplesWritten - count;
      if (readIndex < 0) readIndex = 0;
    } else {
      // Buffer full, calculate from write pointer
      readIndex = (_writeIndex - count + capacity) % capacity;
    }

    // Copy data in order
    for (int i = 0; i < count; i++) {
      result[i] = _data[channel][(readIndex + i) % capacity];
    }

    return result.toList();
  }

  /// Get data for all channels
  ///
  /// Returns [channelCount] lists, each containing samples in chronological order.
  List<List<double>> getAllChannels({int? lastNSamples}) {
    return List.generate(
      channelCount,
      (ch) => getChannel(ch, lastNSamples: lastNSamples),
    );
  }

  /// Get channel data sized for FFT (power-of-2 samples)
  ///
  /// Returns exactly [fftSize] samples, zero-padded if insufficient data.
  List<double> getChannelForFft(int channel, int fftSize) {
    if (channel < 0 || channel >= channelCount) {
      return List.filled(fftSize, 0.0);
    }

    final available = sampleCount;
    final result = Float64List(fftSize);

    if (available == 0) return result.toList();

    // Get up to fftSize samples
    final count = available < fftSize ? available : fftSize;

    // Calculate starting index for most recent samples
    int readIndex;
    if (_totalSamplesWritten < capacity) {
      readIndex = _totalSamplesWritten - count;
      if (readIndex < 0) readIndex = 0;
    } else {
      readIndex = (_writeIndex - count + capacity) % capacity;
    }

    // Copy data (will be left-aligned, remaining zeros on right)
    for (int i = 0; i < count; i++) {
      result[i] = _data[channel][(readIndex + i) % capacity];
    }

    return result.toList();
  }

  /// Get timestamps for samples
  List<int> getTimestamps({int? lastNSamples}) {
    final count = lastNSamples != null
        ? lastNSamples.clamp(0, sampleCount)
        : sampleCount;

    if (count == 0) return [];

    final result = Int32List(count);

    int readIndex;
    if (_totalSamplesWritten < capacity) {
      readIndex = _totalSamplesWritten - count;
      if (readIndex < 0) readIndex = 0;
    } else {
      readIndex = (_writeIndex - count + capacity) % capacity;
    }

    for (int i = 0; i < count; i++) {
      result[i] = _timestamps[(readIndex + i) % capacity];
    }

    return result.toList();
  }

  /// Clear the buffer
  void clear() {
    _writeIndex = 0;
    _totalSamplesWritten = 0;
    // Note: We don't clear the actual data arrays for performance
  }

  /// Get statistics for a channel
  Map<String, double> getChannelStats(int channel) {
    final data = getChannel(channel);
    if (data.isEmpty) {
      return {'min': 0, 'max': 0, 'mean': 0, 'range': 0};
    }

    double min = data.first;
    double max = data.first;
    double sum = 0;

    for (final value in data) {
      if (value < min) min = value;
      if (value > max) max = value;
      sum += value;
    }

    return {
      'min': min,
      'max': max,
      'mean': sum / data.length,
      'range': max - min,
    };
  }
}

/// EEG frequency bands for spectral analysis
enum EegFrequencyBand {
  delta(0.5, 4.0, 'Delta', 'Deep sleep'),
  theta(4.0, 8.0, 'Theta', 'Drowsiness, meditation'),
  alpha(8.0, 13.0, 'Alpha', 'Relaxed, eyes closed'),
  beta(13.0, 30.0, 'Beta', 'Active thinking'),
  gamma(30.0, 100.0, 'Gamma', 'High cognition');

  final double lowFreq;
  final double highFreq;
  final String name;
  final String description;

  const EegFrequencyBand(this.lowFreq, this.highFreq, this.name, this.description);
}

/// EEG display settings
class EegDisplaySettings {
  /// Time window to display in seconds
  final double timeWindowSeconds;

  /// Vertical scale in microvolts per division
  final double microvoltsPerDivision;

  /// Number of vertical divisions
  final int verticalDivisions;

  /// Whether to show grid
  final bool showGrid;

  /// Whether to auto-scale amplitude
  final bool autoScale;

  /// Sweep speed (pixels per second)
  final double sweepSpeed;

  /// Display mode
  final EegDisplayMode displayMode;

  const EegDisplaySettings({
    this.timeWindowSeconds = 5.0,
    this.microvoltsPerDivision = 100.0,
    this.verticalDivisions = 8,
    this.showGrid = true,
    this.autoScale = true,
    this.sweepSpeed = 100.0,
    this.displayMode = EegDisplayMode.stacked,
  });

  EegDisplaySettings copyWith({
    double? timeWindowSeconds,
    double? microvoltsPerDivision,
    int? verticalDivisions,
    bool? showGrid,
    bool? autoScale,
    double? sweepSpeed,
    EegDisplayMode? displayMode,
  }) {
    return EegDisplaySettings(
      timeWindowSeconds: timeWindowSeconds ?? this.timeWindowSeconds,
      microvoltsPerDivision: microvoltsPerDivision ?? this.microvoltsPerDivision,
      verticalDivisions: verticalDivisions ?? this.verticalDivisions,
      showGrid: showGrid ?? this.showGrid,
      autoScale: autoScale ?? this.autoScale,
      sweepSpeed: sweepSpeed ?? this.sweepSpeed,
      displayMode: displayMode ?? this.displayMode,
    );
  }
}

/// EEG display modes
enum EegDisplayMode {
  /// All channels stacked vertically
  stacked,

  /// All channels overlaid on same axes
  overlaid,

  /// Single channel view
  single,
}

/// Mental state classification based on dominant frequency bands
enum EegMentalState {
  unknown('Unknown', 'Insufficient data', Colors.grey),
  sleep('Sleep', 'High delta activity', Color(0xFF3F51B5)),
  drowsy('Drowsy', 'High theta activity', Color(0xFF009688)),
  relaxed('Relaxed', 'High alpha activity', Color(0xFF4CAF50)),
  focused('Focused', 'High beta activity', Color(0xFFFF9800)),
  stressed('Stressed', 'High beta+gamma', Color(0xFFF44336));

  final String label;
  final String description;
  final Color color;

  const EegMentalState(this.label, this.description, this.color);

  IconData get icon {
    switch (this) {
      case EegMentalState.unknown:
        return Icons.help_outline;
      case EegMentalState.sleep:
        return Icons.bedtime;
      case EegMentalState.drowsy:
        return Icons.visibility_off;
      case EegMentalState.relaxed:
        return Icons.self_improvement;
      case EegMentalState.focused:
        return Icons.psychology;
      case EegMentalState.stressed:
        return Icons.bolt;
    }
  }
}

/// EEG frequency band power values
///
/// Contains power spectral density for each standard EEG frequency band.
/// Power is typically in µV² units.
class EegBandPowers {
  /// Delta band power (0.5-4 Hz) - deep sleep, unconsciousness
  final double delta;

  /// Theta band power (4-8 Hz) - drowsiness, light sleep, meditation
  final double theta;

  /// Alpha band power (8-13 Hz) - relaxed wakefulness, eyes closed
  final double alpha;

  /// Beta band power (13-30 Hz) - active thinking, concentration
  final double beta;

  /// Gamma band power (30-50 Hz) - high-level cognition
  /// Note: Limited to 50 Hz due to device's lowpass filter
  final double gamma;

  /// Timestamp when this measurement was taken
  final DateTime timestamp;

  /// Channel index this measurement is from (-1 for average across channels)
  final int channelIndex;

  const EegBandPowers({
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
    required this.timestamp,
    this.channelIndex = -1,
  });

  /// Total power across all bands
  double get totalPower => delta + theta + alpha + beta + gamma;

  /// Relative power for each band (0.0 - 1.0)
  double get relativeDelta => totalPower > 0 ? delta / totalPower : 0;
  double get relativeTheta => totalPower > 0 ? theta / totalPower : 0;
  double get relativeAlpha => totalPower > 0 ? alpha / totalPower : 0;
  double get relativeBeta => totalPower > 0 ? beta / totalPower : 0;
  double get relativeGamma => totalPower > 0 ? gamma / totalPower : 0;

  /// Get power for a specific band
  double getPower(EegFrequencyBand band) {
    switch (band) {
      case EegFrequencyBand.delta:
        return delta;
      case EegFrequencyBand.theta:
        return theta;
      case EegFrequencyBand.alpha:
        return alpha;
      case EegFrequencyBand.beta:
        return beta;
      case EegFrequencyBand.gamma:
        return gamma;
    }
  }

  /// Get relative power for a specific band (0.0 - 1.0)
  double getRelativePower(EegFrequencyBand band) {
    switch (band) {
      case EegFrequencyBand.delta:
        return relativeDelta;
      case EegFrequencyBand.theta:
        return relativeTheta;
      case EegFrequencyBand.alpha:
        return relativeAlpha;
      case EegFrequencyBand.beta:
        return relativeBeta;
      case EegFrequencyBand.gamma:
        return relativeGamma;
    }
  }

  /// Dominant frequency band (highest power)
  EegFrequencyBand get dominantBand {
    final powers = {
      EegFrequencyBand.delta: delta,
      EegFrequencyBand.theta: theta,
      EegFrequencyBand.alpha: alpha,
      EegFrequencyBand.beta: beta,
      EegFrequencyBand.gamma: gamma,
    };
    return powers.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Classify mental state based on band power ratios
  EegMentalState get mentalState {
    if (totalPower < 1.0) return EegMentalState.unknown;

    // Calculate ratios for classification
    final deltaRatio = relativeDelta;
    final thetaRatio = relativeTheta;
    final alphaRatio = relativeAlpha;
    final betaRatio = relativeBeta;
    final gammaRatio = relativeGamma;

    // Classification logic based on dominant frequencies
    if (deltaRatio > 0.5) {
      return EegMentalState.sleep;
    } else if (thetaRatio > 0.35 && alphaRatio < 0.25) {
      return EegMentalState.drowsy;
    } else if (alphaRatio > 0.30) {
      return EegMentalState.relaxed;
    } else if (betaRatio > 0.35 && gammaRatio > 0.15) {
      return EegMentalState.stressed;
    } else if (betaRatio > 0.30) {
      return EegMentalState.focused;
    } else if (alphaRatio > 0.20) {
      return EegMentalState.relaxed;
    }

    return EegMentalState.unknown;
  }

  /// Attention level (0-100) based on beta/theta ratio
  int get attentionLevel {
    if (theta < 0.001) return 50;
    final ratio = beta / (theta + delta * 0.5);
    // Normalize to 0-100 range (typical ratio range: 0.5 - 3.0)
    return ((ratio - 0.5) / 2.5 * 100).clamp(0, 100).round();
  }

  /// Relaxation level (0-100) based on alpha dominance
  int get relaxationLevel {
    if (totalPower < 0.001) return 50;
    // Alpha relative to beta+gamma indicates relaxation
    final relaxRatio = alpha / (beta + gamma + 0.001);
    return ((relaxRatio / 2.0) * 100).clamp(0, 100).round();
  }

  /// Create empty/zero band powers
  factory EegBandPowers.empty() {
    return EegBandPowers(
      delta: 0,
      theta: 0,
      alpha: 0,
      beta: 0,
      gamma: 0,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'EegBandPowers(δ:${delta.toStringAsFixed(1)}, '
        'θ:${theta.toStringAsFixed(1)}, '
        'α:${alpha.toStringAsFixed(1)}, '
        'β:${beta.toStringAsFixed(1)}, '
        'γ:${gamma.toStringAsFixed(1)})';
  }
}

/// Filter settings for EEG screen
///
/// Controls real-time digital filtering applied to EEG waveforms.
class EegFilterSettings {
  /// Enable bandpass filter (1-40 Hz)
  final bool bandpassEnabled;

  /// Enable notch filter (50 or 60 Hz)
  final bool notchEnabled;

  /// Notch frequency (50.0 or 60.0 Hz)
  final double notchFrequency;

  const EegFilterSettings({
    this.bandpassEnabled = true,
    this.notchEnabled = true,
    this.notchFrequency = 50.0,
  });

  /// Check if any filter is enabled
  bool get isFilteringActive => bandpassEnabled || notchEnabled;

  /// Copy with modifications
  EegFilterSettings copyWith({
    bool? bandpassEnabled,
    bool? notchEnabled,
    double? notchFrequency,
  }) {
    return EegFilterSettings(
      bandpassEnabled: bandpassEnabled ?? this.bandpassEnabled,
      notchEnabled: notchEnabled ?? this.notchEnabled,
      notchFrequency: notchFrequency ?? this.notchFrequency,
    );
  }

  @override
  String toString() {
    final filters = <String>[];
    if (bandpassEnabled) filters.add('BP(1-40Hz)');
    if (notchEnabled) filters.add('Notch(${notchFrequency.toInt()}Hz)');
    return filters.isEmpty ? 'No filters' : filters.join('+');
  }
}

/// EEG event marker for annotations on waveform display
///
/// Supports predefined marker types (eyes open/closed, blink, etc.)
/// and custom annotations with keyboard shortcuts.
class EegMarker {
  /// Unique identifier
  final String id;

  /// Timestamp in milliseconds (relative to buffer/recording start)
  final int timestampMs;

  /// Marker type (predefined or custom)
  final EegMarkerType type;

  /// Optional custom description
  final String? customDescription;

  /// When the marker was created
  final DateTime createdAt;

  /// Sample index in the buffer when marker was placed
  final int? sampleIndex;

  const EegMarker({
    required this.id,
    required this.timestampMs,
    required this.type,
    this.customDescription,
    required this.createdAt,
    this.sampleIndex,
  });

  /// Get display label for this marker
  String get label => customDescription ?? type.label;

  /// Get color for this marker
  Color get color => type.color;

  /// Get icon for this marker
  IconData get icon => type.icon;

  /// Create a marker at current time
  factory EegMarker.now({
    required EegMarkerType type,
    required int timestampMs,
    String? customDescription,
    int? sampleIndex,
  }) {
    return EegMarker(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      timestampMs: timestampMs,
      type: type,
      customDescription: customDescription,
      createdAt: DateTime.now(),
      sampleIndex: sampleIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestampMs': timestampMs,
    'type': type.name,
    'customDescription': customDescription,
    'createdAt': createdAt.toIso8601String(),
    'sampleIndex': sampleIndex,
  };

  factory EegMarker.fromJson(Map<String, dynamic> json) => EegMarker(
    id: json['id'] as String,
    timestampMs: json['timestampMs'] as int,
    type: EegMarkerType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => EegMarkerType.custom,
    ),
    customDescription: json['customDescription'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    sampleIndex: json['sampleIndex'] as int?,
  );
}

/// Predefined EEG marker types with keyboard shortcuts
enum EegMarkerType {
  eyesOpen('Eyes Open', '1', Color(0xFF4CAF50), Icons.visibility),
  eyesClosed('Eyes Closed', '2', Color(0xFF2196F3), Icons.visibility_off),
  eyeBlink('Eye Blink', '3', Color(0xFFFF9800), Icons.remove_red_eye),
  jawClench('Jaw Clench', '4', Color(0xFFF44336), Icons.face),
  leftHand('Left Hand', '5', Color(0xFF9C27B0), Icons.back_hand),
  rightHand('Right Hand', '6', Color(0xFF00BCD4), Icons.front_hand),
  artifact('Artifact', '7', Color(0xFFFFEB3B), Icons.warning),
  taskStart('Task Start', '8', Color(0xFF8BC34A), Icons.play_arrow),
  taskEnd('Task End', '9', Color(0xFF607D8B), Icons.stop),
  custom('Custom', '0', Color(0xFF9E9E9E), Icons.edit);

  final String label;
  final String shortcut;
  final Color color;
  final IconData icon;

  const EegMarkerType(this.label, this.shortcut, this.color, this.icon);

  /// Get marker type from keyboard shortcut
  static EegMarkerType? fromShortcut(String key) {
    for (final type in values) {
      if (type.shortcut == key) return type;
    }
    return null;
  }
}

/// Collection of EEG markers with helper methods
class EegMarkerList {
  final List<EegMarker> _markers;

  EegMarkerList([List<EegMarker>? markers]) : _markers = markers ?? [];

  /// All markers
  List<EegMarker> get markers => List.unmodifiable(_markers);

  /// Number of markers
  int get length => _markers.length;

  /// Whether list is empty
  bool get isEmpty => _markers.isEmpty;

  /// Add a marker
  void add(EegMarker marker) {
    _markers.add(marker);
    // Keep sorted by timestamp
    _markers.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }

  /// Remove a marker by ID
  bool remove(String markerId) {
    final index = _markers.indexWhere((m) => m.id == markerId);
    if (index >= 0) {
      _markers.removeAt(index);
      return true;
    }
    return false;
  }

  /// Clear all markers
  void clear() => _markers.clear();

  /// Get markers within a time range
  List<EegMarker> getMarkersInRange(int startMs, int endMs) {
    return _markers
        .where((m) => m.timestampMs >= startMs && m.timestampMs <= endMs)
        .toList();
  }

  /// Get markers visible in the current time window
  ///
  /// [bufferEndTimeMs] is the timestamp of the newest sample in the buffer
  /// [timeWindowSeconds] is the visible time window duration
  List<EegMarker> getVisibleMarkers(int bufferEndTimeMs, double timeWindowSeconds) {
    final windowMs = (timeWindowSeconds * 1000).toInt();
    final startMs = bufferEndTimeMs - windowMs;
    return getMarkersInRange(startMs, bufferEndTimeMs);
  }

  /// Convert to JSON
  List<Map<String, dynamic>> toJson() => _markers.map((m) => m.toJson()).toList();

  /// Create from JSON
  factory EegMarkerList.fromJson(List<dynamic> json) {
    return EegMarkerList(
      json.map((j) => EegMarker.fromJson(j as Map<String, dynamic>)).toList(),
    );
  }
}

/// Per-channel band powers for all 8 EEG channels
class EegAllChannelsBandPowers {
  /// Band powers for each channel (index 0-7)
  final List<EegBandPowers> channels;

  /// Average band powers across all channels
  final EegBandPowers average;

  /// Timestamp
  final DateTime timestamp;

  const EegAllChannelsBandPowers({
    required this.channels,
    required this.average,
    required this.timestamp,
  });

  /// Create from list of channel band powers
  factory EegAllChannelsBandPowers.fromChannels(List<EegBandPowers> channelPowers) {
    if (channelPowers.isEmpty) {
      return EegAllChannelsBandPowers(
        channels: [],
        average: EegBandPowers.empty(),
        timestamp: DateTime.now(),
      );
    }

    // Calculate average across channels
    double avgDelta = 0, avgTheta = 0, avgAlpha = 0, avgBeta = 0, avgGamma = 0;
    for (final ch in channelPowers) {
      avgDelta += ch.delta;
      avgTheta += ch.theta;
      avgAlpha += ch.alpha;
      avgBeta += ch.beta;
      avgGamma += ch.gamma;
    }
    final n = channelPowers.length;

    return EegAllChannelsBandPowers(
      channels: channelPowers,
      average: EegBandPowers(
        delta: avgDelta / n,
        theta: avgTheta / n,
        alpha: avgAlpha / n,
        beta: avgBeta / n,
        gamma: avgGamma / n,
        timestamp: DateTime.now(),
        channelIndex: -1,
      ),
      timestamp: DateTime.now(),
    );
  }
}
