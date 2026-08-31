import 'dart:async';
import 'package:flutter/foundation.dart';
import 'data_parser.dart';

/// Service for managing HRV packet data from HealthyPi 6
///
/// This service:
/// - Subscribes to HRV packets from DataParser
/// - Maintains history for trend analysis
/// - Provides convenient getters for UI consumption
/// - Notifies listeners when new HRV data arrives
///
/// Wire this service in main.dart via ChangeNotifierProvider and connect
/// to DataParser using addPostFrameCallback pattern.
class HRVPacketService extends ChangeNotifier {
  HRVPacketData? _latestData;
  StreamSubscription<HRVPacketData>? _subscription;

  // History buffer for trend analysis (last 5 minutes at ~0.2 Hz = 60 samples)
  final List<HRVPacketData> _history = [];
  static const int _maxHistorySize = 60;

  // R-R interval history for Poincaré plot (stores individual RR intervals)
  final List<int> _rrIntervals = [];
  static const int _maxRRIntervals = 200;

  // Connection state
  bool _isConnected = false;

  // ============= Public Getters =============

  /// Latest HRV packet data (null if none received yet)
  HRVPacketData? get latestData => _latestData;

  /// Whether currently connected to DataParser
  bool get isConnected => _isConnected;

  /// Whether device is still in learning phase (not enough R-R intervals)
  bool get isLearning => _latestData?.hrvValid != true;

  /// Whether HRV data is valid and ready to display
  bool get isValid => _latestData?.hrvValid == true;

  /// Whether any arrhythmia is detected
  bool get hasArrhythmia => _latestData?.hasArrhythmia ?? false;

  /// Whether bradycardia (HR < 60 BPM) is detected
  bool get hasBradycardia => _latestData?.bradycardia ?? false;

  /// Whether tachycardia (HR > 100 BPM) is detected
  bool get hasTachycardia => _latestData?.tachycardia ?? false;

  /// History of HRV packets for trend analysis (oldest first)
  List<HRVPacketData> get history => List.unmodifiable(_history);

  /// Number of HRV packets received
  int get packetsReceived => _history.length;

  /// R-R interval history for Poincaré plot (oldest first)
  List<int> get rrIntervals => List.unmodifiable(_rrIntervals);

  // ============= Convenience Getters for Current Values =============

  /// Current heart rate in BPM (null if no data)
  int? get heartRate => _latestData?.heartRate;

  /// Current R-R interval in ms (null if no data)
  int? get rrInterval => _latestData?.rrIntervalMs;

  /// Current SDNN in ms (null if no data)
  int? get sdnn => _latestData?.sdnnMs;

  /// Current RMSSD in ms (null if no data)
  int? get rmssd => _latestData?.rmssdMs;

  /// Current pNN50 percentage (null if no data)
  int? get pnn50 => _latestData?.pnn50;

  /// Current signal quality percentage (null if no data)
  int? get signalQuality => _latestData?.signalQuality;

  /// Current mean R-R interval in ms (null if no data)
  int? get meanRr => _latestData?.meanRrMs;

  // ============= Trend Analysis =============

  /// Calculate average SDNN over the history buffer
  double? get averageSdnn {
    if (_history.isEmpty) return null;
    final validData = _history.where((d) => d.hrvValid).toList();
    if (validData.isEmpty) return null;
    final sum = validData.fold<int>(0, (sum, d) => sum + d.sdnnMs);
    return sum / validData.length;
  }

  /// Calculate average RMSSD over the history buffer
  double? get averageRmssd {
    if (_history.isEmpty) return null;
    final validData = _history.where((d) => d.hrvValid).toList();
    if (validData.isEmpty) return null;
    final sum = validData.fold<int>(0, (sum, d) => sum + d.rmssdMs);
    return sum / validData.length;
  }

  /// Calculate average heart rate over the history buffer
  double? get averageHeartRate {
    if (_history.isEmpty) return null;
    final validData = _history.where((d) => d.hrvValid).toList();
    if (validData.isEmpty) return null;
    final sum = validData.fold<int>(0, (sum, d) => sum + d.heartRate);
    return sum / validData.length;
  }

  /// Get time span covered by history buffer
  Duration get historyDuration {
    if (_history.length < 2) return Duration.zero;
    return _history.last.timestamp.difference(_history.first.timestamp);
  }

  // ============= Connection Management =============

  /// Connect to DataParser and start receiving HRV packets
  void connectToParser(DataParser parser) {
    // Disconnect existing subscription if any
    disconnect();

    _subscription = parser.hrvStream.listen(_onHrvPacket);
    _isConnected = true;
    debugPrint('💓 HRVPacketService: Connected to DataParser');
  }

  /// Disconnect from DataParser
  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _isConnected = false;
  }

  /// Handle incoming HRV packet
  void _onHrvPacket(HRVPacketData packet) {
    _latestData = packet;

    // Add to history buffer
    _history.add(packet);
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }

    // Add R-R interval to Poincaré buffer (only if valid)
    if (packet.hrvValid && packet.rrIntervalMs > 0) {
      _rrIntervals.add(packet.rrIntervalMs);
      if (_rrIntervals.length > _maxRRIntervals) {
        _rrIntervals.removeAt(0);
      }
    }

    // Notify UI
    notifyListeners();
  }

  /// Clear history and current data (reset for new session)
  void reset() {
    _latestData = null;
    _history.clear();
    _rrIntervals.clear();
    notifyListeners();
    debugPrint('💓 HRVPacketService: Reset - cleared all data');
  }

  /// Alias for reset() for backwards compatibility
  void clear() => reset();

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
