import 'package:flutter/foundation.dart';
import 'dart:async';

/// Performance metrics for a data stream
class StreamMetrics {
  final String streamName;
  final DateTime startTime;
  DateTime? endTime;

  int totalBytes = 0;
  int totalPackets = 0;
  int droppedPackets = 0;

  final List<int> packetSizes = [];
  final List<Duration> interPacketIntervals = [];

  DateTime? lastPacketTime;
  int lastSequenceNumber = -1;

  StreamMetrics(this.streamName, {DateTime? start})
      : startTime = start ?? DateTime.now();

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  double get bytesPerSecond =>
      duration.inMilliseconds > 0
          ? (totalBytes / duration.inMilliseconds) * 1000
          : 0;

  double get packetsPerSecond =>
      duration.inMilliseconds > 0
          ? (totalPackets / duration.inMilliseconds) * 1000
          : 0;

  double get averagePacketSize =>
      totalPackets > 0 ? totalBytes / totalPackets : 0;

  double get packetLossRate =>
      totalPackets > 0 ? droppedPackets / (totalPackets + droppedPackets) : 0;

  Duration get averageInterPacketInterval {
    if (interPacketIntervals.isEmpty) return Duration.zero;
    final totalMicros = interPacketIntervals.fold<int>(
      0,
      (sum, d) => sum + d.inMicroseconds,
    );
    return Duration(microseconds: totalMicros ~/ interPacketIntervals.length);
  }

  void recordPacket(int bytes, {int? sequenceNumber}) {
    final now = DateTime.now();

    totalBytes += bytes;
    totalPackets++;
    packetSizes.add(bytes);

    if (lastPacketTime != null) {
      interPacketIntervals.add(now.difference(lastPacketTime!));
    }

    // Check for dropped packets (sequence number gaps)
    if (sequenceNumber != null && lastSequenceNumber >= 0) {
      final expected = lastSequenceNumber + 1;
      if (sequenceNumber > expected) {
        droppedPackets += (sequenceNumber - expected);
      }
      lastSequenceNumber = sequenceNumber;
    } else if (sequenceNumber != null) {
      lastSequenceNumber = sequenceNumber;
    }

    lastPacketTime = now;
  }

  void finish() {
    endTime = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'streamName': streamName,
        'durationSeconds': duration.inSeconds,
        'totalBytes': totalBytes,
        'totalPackets': totalPackets,
        'droppedPackets': droppedPackets,
        'bytesPerSecond': bytesPerSecond,
        'packetsPerSecond': packetsPerSecond,
        'averagePacketSize': averagePacketSize,
        'packetLossRate': packetLossRate,
        'averageInterPacketIntervalUs':
            averageInterPacketInterval.inMicroseconds,
      };

  @override
  String toString() {
    return '''
$streamName Metrics:
  Duration: ${duration.inSeconds}s
  Total Bytes: $totalBytes (${(totalBytes / 1024).toStringAsFixed(2)} KB)
  Total Packets: $totalPackets
  Dropped Packets: $droppedPackets (${(packetLossRate * 100).toStringAsFixed(2)}%)
  Throughput: ${bytesPerSecond.toStringAsFixed(0)} bytes/sec
  Packet Rate: ${packetsPerSecond.toStringAsFixed(0)} packets/sec
  Avg Packet Size: ${averagePacketSize.toStringAsFixed(1)} bytes
  Avg Inter-Packet Interval: ${averageInterPacketInterval.inMicroseconds} μs
''';
  }
}

/// Monitors and compares throughput across multiple streams
class ThroughputMonitor extends ChangeNotifier {
  final Map<String, StreamMetrics> _streams = {};
  bool _isMonitoring = false;
  Timer? _updateTimer;

  /// Whether monitoring is active
  bool get isMonitoring => _isMonitoring;

  /// All monitored streams
  Map<String, StreamMetrics> get streams => Map.unmodifiable(_streams);

  /// Start monitoring a named stream
  void startMonitoring(String streamName) {
    if (_streams.containsKey(streamName)) {
      debugPrint('⚠️ Stream $streamName already being monitored');
      return;
    }

    _streams[streamName] = StreamMetrics(streamName);
    _isMonitoring = true;

    // Start periodic UI updates (every second)
    _updateTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });

    debugPrint('📊 Started monitoring stream: $streamName');
    notifyListeners();
  }

  /// Stop monitoring a specific stream
  void stopMonitoring(String streamName) {
    final metrics = _streams[streamName];
    if (metrics != null) {
      metrics.finish();
      debugPrint('📊 Stopped monitoring stream: $streamName');
      debugPrint(metrics.toString());
    }

    // Don't remove from map - keep for comparison
    // _streams.remove(streamName);

    if (_streams.values.every((m) => m.endTime != null)) {
      _isMonitoring = false;
      _updateTimer?.cancel();
      _updateTimer = null;
    }

    notifyListeners();
  }

  /// Stop all monitoring
  void stopAll() {
    for (final streamName in _streams.keys.toList()) {
      stopMonitoring(streamName);
    }
  }

  /// Record a packet for a stream
  void recordPacket(String streamName, int bytes, {int? sequenceNumber}) {
    final metrics = _streams[streamName];
    if (metrics == null) {
      debugPrint(
          '⚠️ Attempting to record packet for unmonitored stream: $streamName');
      return;
    }

    if (metrics.endTime != null) {
      debugPrint('⚠️ Stream $streamName monitoring already stopped');
      return;
    }

    metrics.recordPacket(bytes, sequenceNumber: sequenceNumber);

    // Don't notify every packet - too expensive
    // Timer updates UI every second instead
  }

  /// Clear all metrics (reset)
  void clearAll() {
    _streams.clear();
    _isMonitoring = false;
    _updateTimer?.cancel();
    _updateTimer = null;
    debugPrint('📊 Cleared all throughput metrics');
    notifyListeners();
  }

  /// Get metrics for a specific stream
  StreamMetrics? getMetrics(String streamName) => _streams[streamName];

  /// Compare two streams
  String compareStreams(String stream1Name, String stream2Name) {
    final s1 = _streams[stream1Name];
    final s2 = _streams[stream2Name];

    if (s1 == null || s2 == null) {
      return 'Error: One or both streams not found';
    }

    final throughputDiff =
        ((s1.bytesPerSecond - s2.bytesPerSecond) / s2.bytesPerSecond) * 100;
    final packetRateDiff =
        ((s1.packetsPerSecond - s2.packetsPerSecond) / s2.packetsPerSecond) *
            100;

    return '''
Comparison: $stream1Name vs $stream2Name
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Throughput:
  $stream1Name: ${s1.bytesPerSecond.toStringAsFixed(0)} bytes/sec
  $stream2Name: ${s2.bytesPerSecond.toStringAsFixed(0)} bytes/sec
  Difference: ${throughputDiff >= 0 ? '+' : ''}${throughputDiff.toStringAsFixed(1)}%

Packet Rate:
  $stream1Name: ${s1.packetsPerSecond.toStringAsFixed(0)} packets/sec
  $stream2Name: ${s2.packetsPerSecond.toStringAsFixed(0)} packets/sec
  Difference: ${packetRateDiff >= 0 ? '+' : ''}${packetRateDiff.toStringAsFixed(1)}%

Packet Loss:
  $stream1Name: ${(s1.packetLossRate * 100).toStringAsFixed(3)}%
  $stream2Name: ${(s2.packetLossRate * 100).toStringAsFixed(3)}%

Latency:
  $stream1Name: ${s1.averageInterPacketInterval.inMicroseconds} μs
  $stream2Name: ${s2.averageInterPacketInterval.inMicroseconds} μs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
  }

  /// Get summary of all streams
  String getSummary() {
    if (_streams.isEmpty) {
      return 'No streams monitored';
    }

    final buffer = StringBuffer();
    buffer.writeln('Throughput Monitor Summary');
    buffer.writeln('═' * 50);

    for (final metrics in _streams.values) {
      buffer.writeln();
      buffer.write(metrics.toString());
    }

    return buffer.toString();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
