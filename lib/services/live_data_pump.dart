import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/channel_controller.dart';
import '../models/waveform_models.dart';
import '../theme/hpi_tokens.dart';
import 'data_parser.dart';
import 'filter_integration_service.dart';
import 'recording_data_bridge.dart';
import 'recording_engine.dart';
import 'throughput_monitor.dart';
import 'usb_serial_service.dart';
import 'wifi_serial_service.dart';

/// Where the waveforms on screen are coming from.
enum LiveDataSource {
  /// No transport attached — the app runs the built-in generator so every screen
  /// stays legible offline.
  simulated,

  /// A HealthyPi board over USB CDC or WiFi.
  device,
}

/// Owns acquisition for the whole shell: the [ChannelController] behind every
/// waveform, the transport bridge into [DataParser], and the vitals trend rings
/// the vitals cards read.
///
/// This used to live inside the dashboard screen, which meant it was torn down
/// and rebuilt whenever the user changed screens. It sits at shell level now so
/// a recording survives navigation.
class LiveDataPump extends ChangeNotifier with WidgetsBindingObserver {
  LiveDataPump({
    required DataParser dataParser,
    required UsbSerialService usb,
    required WifiSerialService wifi,
    required RecordingEngine recordingEngine,
    required FilterIntegrationService filterService,
    required ThroughputMonitor throughput,
  })  : _parser = dataParser,
        _usb = usb,
        _wifi = wifi,
        _throughput = throughput {
    _controller = ChannelController(
      initialSettings: ChartSettings(
        channelCount: liveChannels.length,
        timeWindowSeconds: 10,
        samplingRate: _ecgSampleRate,
        showGlobalGrid: true,
      ),
      initialChannels: liveChannels,
    );
    _bridge = RecordingDataBridge(
      recordingEngine: recordingEngine,
      channelController: _controller,
    );
    _controller
      ..setRecordingBridge(_bridge)
      ..setRecordingEngine(recordingEngine)
      ..setFilterService(filterService);

    WidgetsBinding.instance.addObserver(this);
    _parser.addListener(_onParserData);
    _usb.addListener(_onTransportChanged);
    _wifi.addListener(_onTransportChanged);
    _startSimulation();
    _vitalsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sampleVitals());
  }

  /// The rates the app's channels run at — not always the wire rate. ECG is
  /// 500 Hz on the wire and here; the device streams PPG at 250 Hz, which
  /// `_onParserData` decimates 4:1 to 125 Hz for display, so that is the rate
  /// every consumer of the `ppg` channel sees.
  static const double _ecgSampleRate = 500;
  static const double _wifiSampleRate = 250;
  static const double ppgSampleRate = 125;
  static const double eegSampleRate = 250;

  /// How many trend points a vitals sparkline keeps (~1 point/second).
  static const int vitalsTrendLength = 60;

  final DataParser _parser;
  final UsbSerialService _usb;
  final WifiSerialService _wifi;
  final ThroughputMonitor _throughput;

  late final ChannelController _controller;
  late final RecordingDataBridge _bridge;

  Timer? _simulationTimer;
  Timer? _vitalsTimer;
  LiveDataSource _source = LiveDataSource.simulated;
  bool _inForeground = true;
  bool _frameScheduled = false;
  int _simSampleIndex = 0;
  int _packetIndex = 0;
  DateTime? _streamStart;
  final math.Random _random = math.Random();

  final List<double> _hrTrend = [];
  final List<double> _spo2Trend = [];
  final List<double> _respTrend = [];
  final List<double> _tempTrend = [];

  ChannelController get controller => _controller;
  LiveDataSource get source => _source;
  bool get isSimulated => _source == LiveDataSource.simulated;

  /// True when a transport is attached, regardless of whether data is flowing.
  bool get hasDevice => _usb.isConnected || _wifi.isConnected;

  /// How long the current stream has been running.
  Duration get streamDuration =>
      _streamStart == null ? Duration.zero : DateTime.now().difference(_streamStart!);

  List<double> get hrTrend => List.unmodifiable(_hrTrend);
  List<double> get spo2Trend => List.unmodifiable(_spo2Trend);
  List<double> get respTrend => List.unmodifiable(_respTrend);
  List<double> get tempTrend => List.unmodifiable(_tempTrend);

  /// The channel set the design shows on Live, in display order, using the
  /// semantic trace ramp rather than saturated primaries.
  static List<ChannelConfiguration> get liveChannels => [
        ChannelConfiguration(
          id: 'ecg1',
          label: 'Lead I',
          unit: 'mV',
          color: HpiTraceRamp.dark.ecg1,
          minValue: -500,
          maxValue: 500,
          lineWidth: 1.6,
        ),
        ChannelConfiguration(
          id: 'ecg2',
          label: 'Lead II',
          unit: 'mV',
          color: HpiTraceRamp.dark.ecg2,
          minValue: -500,
          maxValue: 500,
          lineWidth: 1.6,
        ),
        ChannelConfiguration(
          id: 'ecg3',
          label: 'V1',
          unit: 'mV',
          color: HpiTraceRamp.dark.ecg3,
          minValue: -500,
          maxValue: 500,
          lineWidth: 1.6,
        ),
        ChannelConfiguration(
          id: 'respiration',
          label: 'Respiration',
          unit: 'mV',
          color: HpiTraceRamp.dark.respiration,
          minValue: -500,
          maxValue: 500,
          lineWidth: 1.8,
        ),
        ChannelConfiguration(
          id: 'ppg',
          label: 'PPG red',
          unit: 'a.u.',
          color: HpiTraceRamp.dark.ppg,
          lineWidth: 1.8,
          autoScale: true,
        ),
        ChannelConfiguration(
          id: 'eeg1',
          label: 'EEG Fp1',
          unit: 'µV',
          color: HpiTraceRamp.dark.eeg1,
          minValue: -100,
          maxValue: 100,
          lineWidth: 1.2,
          autoScale: true,
          heightRatio: 0.8,
        ),
        ChannelConfiguration(
          id: 'eeg2',
          label: 'EEG Fp2',
          unit: 'µV',
          color: HpiTraceRamp.dark.eeg2,
          minValue: -100,
          maxValue: 100,
          lineWidth: 1.2,
          autoScale: true,
          heightRatio: 0.8,
        ),
      ];

  /// The per-channel detail line shown in the gutter: the channel's rate and
  /// unit, which are facts. It used to assert filter corners ('40 Hz LP') that
  /// the app only applies if the user has enabled that chain on the Filters
  /// screen, where filtering is off by default.
  static String channelDetail(String channelId) => switch (channelId) {
        'ecg1' || 'ecg2' || 'ecg3' => '500 Hz · µV',
        'respiration' => '500 Hz · BioZ',
        'ppg' => '125 Hz · a.u.',
        'eeg1' || 'eeg2' => '250 Hz · µV',
        _ => '',
      };

  // ── transport ──────────────────────────────────────────────────────────────

  void _onTransportChanged() {
    final connected = hasDevice;
    if (connected && _source != LiveDataSource.device) {
      _source = LiveDataSource.device;
      _simulationTimer?.cancel();
      _simulationTimer = null;
      _controller.clearAllData();
      _packetIndex = 0;
      _streamStart = DateTime.now();
      _controller.updateSamplingRate(
        _usb.isConnected ? _ecgSampleRate : _wifiSampleRate,
      );
      _throughput.startMonitoring(_usb.isConnected ? 'usb' : 'wifi');
      debugPrint('✅ Acquisition source: device '
          '(${_usb.isConnected ? "USB 500 Hz" : "WiFi 250 Hz"})');
      notifyListeners();
      return;
    }

    if (!connected && _source == LiveDataSource.device) {
      _source = LiveDataSource.simulated;
      _controller.clearAllData();
      _streamStart = DateTime.now();
      _controller.updateSamplingRate(_ecgSampleRate);
      _throughput.stopAll();
      _startSimulation();
      debugPrint('📊 Acquisition source: simulated (no transport attached)');
      notifyListeners();
      return;
    }

    // Still connected but the active transport changed — follow its rate.
    if (connected) {
      _controller.updateSamplingRate(
        _usb.isConnected ? _ecgSampleRate : _wifiSampleRate,
      );
    }
  }

  void _onParserData() {
    if (_source != LiveDataSource.device) return;
    // Keep feeding the recorder when the window is hidden, but skip the frame
    // hop so we are not queueing callbacks that will not run.
    if (!_inForeground) {
      _drainPackets();
      return;
    }
    if (_frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (_source == LiveDataSource.device) _drainPackets();
    });
  }

  /// Drain every packet the parser has buffered. Each packet carries its own
  /// sample values, so they must be added one at a time.
  void _drainPackets() {
    if (_controller.settings.isPaused) return;
    try {
      final packets = _parser.consumePackets();
      if (packets.isEmpty) return;
      final eegPackets = _parser.consumeEegPackets();
      var eegIndex = 0;

      for (final packet in packets) {
        final values = <String, double>{
          'ecg1': packet.ecg1.toDouble(),
          'ecg2': packet.ecg2.toDouble(),
          'ecg3': packet.ecg3.toDouble(),
          'respiration': packet.respiration.toDouble(),
        };

        // EEG arrives at 250 Hz against a 500 Hz waveform clock.
        if (_packetIndex.isEven && eegIndex < eegPackets.length) {
          final eeg = eegPackets[eegIndex++];
          if (eeg.channels.length >= 2) {
            values['eeg1'] = eeg.channels[0].toDouble();
            values['eeg2'] = eeg.channels[1].toDouble();
          }
        }

        // PPG is decimated to 125 Hz for display.
        if (_packetIndex % 4 == 0) {
          values['ppg'] = packet.ppgRed.toDouble() / 100.0;
        }
        _packetIndex++;

        _controller.addDataPointsSync(values);
        // Feed the diagnostics counters that Link health reads. Without this the
        // whole screen reports zeroes.
        _throughput.recordPacket(
          _usb.isConnected ? 'usb' : 'wifi',
          packet.hasSequenceNumber
              ? OpenViewConstants.v2PacketLength
              : OpenViewConstants.v1PacketLength,
          sequenceNumber: packet.hasSequenceNumber ? packet.sequenceNumber : null,
        );
      }
    } catch (e) {
      debugPrint('❌ Acquisition drain failed: $e');
    }
  }

  // ── vitals trends ──────────────────────────────────────────────────────────

  void _sampleVitals() {
    if (_source == LiveDataSource.device) {
      final data = _parser.currentOpenViewData;
      if (data == null) return;
      _push(_hrTrend, data.heartRate.toDouble());
      _push(_spo2Trend, data.spo2.toDouble());
      _push(_respTrend, data.respirationRate.toDouble());
      _push(_tempTrend, data.temperature);
    } else {
      final t = _simSampleIndex / _ecgSampleRate;
      _push(_hrTrend, 72 + 3 * math.sin(t / 9));
      _push(_spo2Trend, 98 + math.sin(t / 14));
      _push(_respTrend, 16 + math.sin(t / 11));
      _push(_tempTrend, 36.5 + 0.05 * math.sin(t / 23));
    }
    notifyListeners();
  }

  static void _push(List<double> ring, double value) {
    if (!value.isFinite) return;
    ring.add(value);
    if (ring.length > vitalsTrendLength) ring.removeAt(0);
  }

  // ── simulation ─────────────────────────────────────────────────────────────

  void _startSimulation() {
    _simulationTimer?.cancel();
    _streamStart ??= DateTime.now();
    _simulationTimer = Timer.periodic(const Duration(microseconds: 2000), (_) {
      if (_controller.settings.isPaused ||
          _source != LiveDataSource.simulated ||
          !_inForeground) {
        return;
      }
      _simSampleIndex++;
      _controller.addDataPointsSync(_simulate(_simSampleIndex));
    });
  }

  Map<String, double> _simulate(int index) {
    final t = index / _ecgSampleRate;
    final cycle = ((2 * math.pi * 1.2 * t) % (2 * math.pi)) / (2 * math.pi);

    final pWave = 5 *
        math.sin(math.pi * cycle * 2) *
        math.exp(-math.pow((cycle - 0.15) / 0.08, 2));
    var qrs = 0.0;
    if (cycle >= 0.35 && cycle <= 0.45) {
      qrs -= 12 * math.sin((cycle - 0.35) / 0.1 * math.pi);
    }
    if (cycle >= 0.40 && cycle <= 0.55) {
      qrs += 35 * math.sin((cycle - 0.40) / 0.15 * math.pi);
    }
    if (cycle >= 0.50 && cycle <= 0.65) {
      qrs -= 20 * math.sin((cycle - 0.50) / 0.15 * math.pi);
    }
    final tWave = 10 *
        math.sin(math.pi * (cycle - 0.65) / 0.35) *
        math.exp(-math.pow((cycle - 0.75) / 0.12, 2));
    final wander = 1.5 * math.sin(2 * math.pi * 0.1 * t);
    double noise() => 1.5 * (_random.nextDouble() - 0.5);

    // V1 is deliberately a different morphology (rsR' with an inverted T) so the
    // three leads are distinguishable, not three copies.
    var v1Qrs = 0.0;
    if (cycle >= 0.35 && cycle <= 0.45) {
      v1Qrs += 20 * math.sin((cycle - 0.35) / 0.1 * math.pi);
    }
    if (cycle >= 0.45 && cycle <= 0.65) {
      v1Qrs -= 30 * math.sin((cycle - 0.45) / 0.2 * math.pi);
    }

    final values = <String, double>{
      'ecg1': pWave * 0.6 + qrs * 0.9 + tWave * 0.8 + wander + noise(),
      'ecg2': pWave * 0.5 + qrs * 1.1 + tWave * 1.0 + wander + noise(),
      'ecg3': pWave * 0.3 + v1Qrs - tWave * 0.9 + wander + noise(),
      'respiration': 150 * math.sin(2 * math.pi * 0.3 * t),
      'eeg1': _simulateEeg(t, index, 1.5, 6.0, 10.0, 20.0, 0),
      'eeg2': _simulateEeg(t, index, 1.6, 6.2, 10.1, 20.5, 10),
    };

    if (index % 4 == 0) {
      values['ppg'] = 100.0 * math.exp(-math.pow((cycle - 0.18) * 12, 2)) +
          35.0 * math.exp(-math.pow((cycle - 0.45) * 10, 2)) +
          noise();
    }
    return values;
  }

  double _simulateEeg(double t, int index, double delta, double theta,
      double alpha, double beta, int blinkOffset) {
    var v = 30.0 * math.sin(2 * math.pi * delta * t) +
        15.0 * math.sin(2 * math.pi * theta * t) +
        10.0 * math.sin(2 * math.pi * alpha * t) +
        5.0 * math.sin(2 * math.pi * beta * t) +
        3.0 * (_random.nextDouble() - 0.5);
    // A periodic blink artefact, so the artefact controls have something to act on.
    final phase = index % 1500;
    if (phase >= blinkOffset && phase < blinkOffset + 100) {
      v += 80.0 * math.sin(math.pi * (phase - blinkOffset) / 100.0);
    }
    return v;
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _simulationTimer?.cancel();
    _vitalsTimer?.cancel();
    _parser.removeListener(_onParserData);
    _usb.removeListener(_onTransportChanged);
    _wifi.removeListener(_onTransportChanged);
    _bridge.dispose();
    _controller.dispose();
    super.dispose();
  }
}
