import 'dart:async';
import 'package:flutter/foundation.dart';
import 'data_parser.dart';

/// Service for managing EEG packet data from HealthyPi
///
/// This service:
/// - Subscribes to EEG packets from DataParser
/// - Maintains history for trend analysis
/// - Tracks electrode connection status
/// - Provides convenient getters for UI consumption
/// - Notifies listeners when new EEG data arrives
///
/// Wire this service in main.dart via ChangeNotifierProvider and connect
/// to DataParser using addPostFrameCallback pattern.
class EEGPacketService extends ChangeNotifier {
  EEGPacketData? _latestData;
  StreamSubscription<EEGPacketData>? _subscription;

  // History buffer for trend analysis (last 5 seconds at 250 Hz = 1250 samples)
  final List<EEGPacketData> _history = [];
  static const int _maxHistorySize = 1250;

  // Connection state
  bool _isConnected = false;

  // Channel data buffers for visualization (stores recent values per channel)
  static const int _channelBufferSize = 500; // ~2 seconds at 250 Hz
  final List<List<int>> _channelBuffers = List.generate(8, (_) => <int>[]);

  // ============= Public Getters =============

  /// Latest EEG packet data (null if none received yet)
  EEGPacketData? get latestData => _latestData;

  /// Whether currently connected to DataParser
  bool get isConnected => _isConnected;

  /// History of EEG packets for trend analysis (oldest first)
  List<EEGPacketData> get history => List.unmodifiable(_history);

  /// Number of EEG packets received
  int get packetsReceived => _history.length;

  /// Get buffer for specific channel (0-7)
  List<int> getChannelBuffer(int channel) {
    if (channel < 0 || channel > 7) return [];
    return List.unmodifiable(_channelBuffers[channel]);
  }

  // ============= Convenience Getters for Current Values =============

  /// Current signal quality (null if no data)
  int? get signalQuality => _latestData?.signalQuality;

  /// Number of connected channels (0-8)
  int get connectedChannelCount => _latestData?.connectedChannelCount ?? 0;

  /// List of disconnected channel indices (0-7)
  List<int> get disconnectedChannels => _latestData?.disconnectedChannels ?? [];

  /// Check if specific channel is connected
  bool isChannelConnected(int channel) {
    return _latestData?.isChannelConnected(channel) ?? false;
  }

  /// Get current value for specific channel in microvolts
  int? getChannelValue(int channel) {
    if (_latestData == null || channel < 0 || channel > 7) return null;
    return _latestData!.channels[channel];
  }

  /// Get all current channel values
  List<int>? get currentChannelValues => _latestData?.channels;

  /// Lead-off positive bitmask
  int? get leadOffPositive => _latestData?.leadOffPositive;

  /// Lead-off negative bitmask
  int? get leadOffNegative => _latestData?.leadOffNegative;

  // ============= Statistics =============

  /// Calculate average signal quality over the history buffer
  double? get averageSignalQuality {
    if (_history.isEmpty) return null;
    final sum = _history.fold<int>(0, (sum, d) => sum + d.signalQuality);
    return sum / _history.length;
  }

  /// Get time span covered by history buffer
  Duration get historyDuration {
    if (_history.length < 2) return Duration.zero;
    final firstTs = _history.first.timestampMs;
    final lastTs = _history.last.timestampMs;
    return Duration(milliseconds: lastTs - firstTs);
  }

  /// Calculate channel statistics (min, max, mean) for a specific channel
  Map<String, double>? getChannelStats(int channel) {
    if (channel < 0 || channel > 7) return null;
    final buffer = _channelBuffers[channel];
    if (buffer.isEmpty) return null;

    int min = buffer.first;
    int max = buffer.first;
    int sum = 0;

    for (final value in buffer) {
      if (value < min) min = value;
      if (value > max) max = value;
      sum += value;
    }

    return {
      'min': min.toDouble(),
      'max': max.toDouble(),
      'mean': sum / buffer.length,
      'range': (max - min).toDouble(),
    };
  }

  // ============= Connection Management =============

  /// Connect to DataParser and start receiving EEG packets
  void connectToParser(DataParser parser) {
    // Disconnect existing subscription if any
    disconnect();

    _subscription = parser.eegStream.listen(_onEegPacket);
    _isConnected = true;
    debugPrint('🧠 EEGPacketService: Connected to DataParser');
  }

  /// Disconnect from DataParser
  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _isConnected = false;
  }

  /// Handle incoming EEG packet
  void _onEegPacket(EEGPacketData packet) {
    _latestData = packet;

    // Add to history buffer
    _history.add(packet);
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }

    // Update channel buffers
    for (int i = 0; i < 8; i++) {
      _channelBuffers[i].add(packet.channels[i]);
      if (_channelBuffers[i].length > _channelBufferSize) {
        _channelBuffers[i].removeAt(0);
      }
    }

    // Notify UI
    notifyListeners();
  }

  /// Clear history and current data (reset for new session)
  void reset() {
    _latestData = null;
    _history.clear();
    for (final buffer in _channelBuffers) {
      buffer.clear();
    }
    notifyListeners();
    debugPrint('🧠 EEGPacketService: Reset - cleared all data');
  }

  /// Alias for reset() for backwards compatibility
  void clear() => reset();

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
