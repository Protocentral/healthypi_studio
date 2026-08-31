import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/export_models.dart';
import '../../models/recording_models.dart';
import '../../services/data_parser.dart';
import '../../services/live_data_pump.dart';
import '../../services/recording_engine.dart';
import '../../services/recording_export_service.dart';
import '../../services/recording_file_service.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_settings.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_primitives.dart';
import 'connect_screen.dart';
import 'device_screen.dart';
import 'eeg_screen.dart';
import 'filters_screen.dart';
import 'hrv_screen.dart';
import 'link_health_screen.dart';
import 'live_screen.dart';
import 'recordings_screen.dart';
import 'settings_screen.dart';

/// The app's single host: the shell chrome wrapped around whichever destination
/// the rail has selected.
///
/// Screens are kept alive across navigation so a running recording, a filled FFT
/// window and a scrolled table all survive a trip to another destination.
class StudioHome extends StatefulWidget {
  const StudioHome({super.key});

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  final _recordings = GlobalKey<RecordingsScreenState>();
  final _connect = GlobalKey<ConnectScreenState>();
  final _filters = GlobalKey<FiltersScreenState>();
  final _link = GlobalKey<LinkHealthScreenState>();
  final _device = GlobalKey<DeviceScreenState>();
  final _settings = GlobalKey<SettingsScreenState>();
  final FocusNode _shortcuts = FocusNode(debugLabel: 'studio-shortcuts');

  Timer? _linkTimer;

  @override
  void initState() {
    super.initState();
    // The app bar reads link numbers from a 1 Hz snapshot rather than watching
    // the 500 Hz parser, so chrome does not rebuild per packet.
    _linkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final parser = context.read<DataParser>();
      context.read<StudioLinkSnapshot>().update(
            packetsPerSecond: parser.packetsPerSecond,
            lossPercent: parser.hasSequenceTracking
                ? parser.sequenceBasedLossPercent
                : parser.sampleLossPercent,
            packetsReceived: parser.packetsReceived,
            packetsDropped: parser.packetsDropped,
            gaps: parser.sequenceGaps,
            protocol: parser.protocolVersionString,
          );
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _shortcuts.requestFocus());
  }

  @override
  void dispose() {
    _linkTimer?.cancel();
    _shortcuts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<StudioNavController>();
    final pump = context.watch<LiveDataPump>();

    // Connect is the Live destination's empty state, not a separate shell: the
    // chrome stays put and the rail dims rather than disappearing.
    final onConnect = nav.destination == StudioDestination.live &&
        !pump.hasDevice &&
        !nav.connectDismissed;

    return Scaffold(
      body: Focus(
        focusNode: _shortcuts,
        autofocus: true,
        onKeyEvent: _onKey,
        child: StudioShell(
          chromeDimmed: onConnect,
          primaryAction: onConnect ? null : _primaryAction(context, nav),
          statusItems: onConnect
              ? (_connect.currentState?.buildStatusItems(context) ?? const [])
              : _statusItems(context, nav),
          child: _content(nav, onConnect),
        ),
      ),
    );
  }

  Widget _content(StudioNavController nav, bool onConnect) {
    // IndexedStack keeps every destination mounted; the offstage ones stop
    // painting but keep their state.
    return IndexedStack(
      index: StudioDestination.values.indexOf(nav.destination),
      children: [
        onConnect ? ConnectScreen(key: _connect) : const LiveScreen(),
        const HrvScreen(),
        const EegScreen(),
        RecordingsScreen(key: _recordings),
        FiltersScreen(key: _filters),
        LinkHealthScreen(key: _link),
        DeviceScreen(key: _device),
        SettingsScreen(key: _settings),
      ],
    );
  }

  /// The one amber action per screen. Recording owns it everywhere except
  /// Recordings & export, where exporting is the job.
  Widget? _primaryAction(BuildContext context, StudioNavController nav) {
    if (nav.destination == StudioDestination.records) {
      final state = _recordings.currentState;
      return state?.buildPrimaryAction(context);
    }
    if (nav.destination == StudioDestination.device) return null;
    return const RecordButton();
  }

  List<Widget> _statusItems(BuildContext context, StudioNavController nav) {
    switch (nav.destination) {
      case StudioDestination.records:
        return _recordings.currentState?.buildStatusItems(context) ?? const [];
      case StudioDestination.filters:
        return _filters.currentState?.buildStatusItems(context) ?? const [];
      case StudioDestination.link:
        return _link.currentState?.buildStatusItems(context) ?? const [];
      case StudioDestination.device:
        return _device.currentState?.buildStatusItems(context) ?? const [];
      case StudioDestination.settings:
        return _settings.currentState?.buildStatusItems(context) ?? const [];
      case StudioDestination.live:
      case StudioDestination.hrv:
      case StudioDestination.eeg:
        return _acquisitionStatus(context);
    }
  }

  List<Widget> _acquisitionStatus(BuildContext context) {
    final p = context.hpi;
    // The 1 Hz snapshot, not the parser itself: watching `DataParser` here
    // rebuilt the entire shell on every parse batch, and the waveform quietly
    // came to depend on that for its frame rate.
    final link = context.watch<StudioLinkSnapshot>();
    final pump = context.watch<LiveDataPump>();
    final engine = context.watch<RecordingEngine>();
    final healthy = link.gaps == 0;

    return [
      StatusItem(
        pump.isSimulated
            ? 'Demo data · no device attached'
            : '${link.protocol} · '
                '${healthy ? "seq OK" : "${link.gaps} gaps"}',
        icon: pump.isSimulated
            ? Icons.science_outlined
            : (healthy ? Icons.check_circle : Icons.warning_amber_rounded),
        tone: pump.isSimulated ? p.brand : (healthy ? p.success : p.warning),
      ),
      StatusItem(pump.isSimulated
          ? '500 Hz generated'
          : '${link.packetsPerSecond.toStringAsFixed(0)} Hz · '
              '${link.gaps} gaps'),
      StatusItem('${link.packetsReceived} pkt · '
          '${link.packetsDropped} dropped'),
      if (engine.state == RecordingState.recording)
        StatusItem(
          'REC ${formatDuration(engine.elapsedTime)} · '
              '${formatBytes(engine.fileSizeBytes)}',
          icon: Icons.fiber_manual_record,
          tone: p.error,
        ),
    ];
  }

  /// Global shortcuts, as documented on the Settings screen.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // A shell-level handler still sees characters typed into a descendant text
    // field, so `R` in a host name would start a recording and a digit would
    // navigate out from under the caret. Text entry wins.
    if (textEntryHasFocus()) return KeyEventResult.ignored;
    final nav = context.read<StudioNavController>();
    final pump = context.read<LiveDataPump>();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      return nav.escape() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.space) {
      pump.controller.togglePause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      nav.go(StudioDestination.live);
      nav.toggleFocusMode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _toggleRecording();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      dropMarker(context);
      return KeyEventResult.handled;
    }
    for (var i = 0; i < StudioDestination.values.length; i++) {
      if (key == _digits[i]) {
        nav.go(StudioDestination.values[i]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  static const List<LogicalKeyboardKey> _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
  ];

  Future<void> _toggleRecording() async {
    final engine = context.read<RecordingEngine>();
    final pump = context.read<LiveDataPump>();
    if (engine.state == RecordingState.recording ||
        engine.state == RecordingState.paused) {
      await stopRecordingAndExport(context);
    } else {
      await pump.controller.startRecording();
    }
  }
}

/// Stop the recording, then honour **Auto-export after recording**.
///
/// The export reads the `.hpd` the engine has just finalised, so it can only run
/// after the stop completes. CSV is the one format implemented end to end, which
/// is why the setting is a toggle and not a format picker.
Future<void> stopRecordingAndExport(BuildContext context) async {
  final pump = context.read<LiveDataPump>();
  final settings = context.read<StudioSettings>();
  final exporter = context.read<RecordingExportService>();
  final files = context.read<RecordingFileService>();
  final messenger = ScaffoldMessenger.maybeOf(context);

  await pump.controller.stopRecording();
  unawaited(files.loadRecordings());
  if (!settings.autoExportAfterRecording) return;

  final String? source = pump.controller.lastCompletedRecording?.filePath;
  if (source == null) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Auto-export skipped: the recording wrote no file.'),
    ));
    return;
  }

  final String base =
      source.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.hpd$'), '');
  final String? out = await exporter.exportToCSV(
    inputFilePath: source,
    outputFileName: '$base.csv',
    options: CSVExportOptions(
      includeMetadata: true,
      includeTimestamps: true,
    ),
  );

  messenger?.showSnackBar(SnackBar(
    content: Text(out == null
        ? 'Auto-export failed: ${exporter.error ?? "unknown error"}'
        : 'Exported ${out.split(Platform.pathSeparator).last}'),
  ));
}

/// True while the caret is in a text field, anywhere in the app.
///
/// Flutter delivers character keys to ancestor `Focus.onKeyEvent` handlers even
/// while an `EditableText` holds the focus, so every global single-key shortcut
/// has to stand down explicitly or it fires mid-word.
bool textEntryHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// The app's primary action: start or stop recording, from anywhere.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final engine = context.watch<RecordingEngine>();
    final pump = context.watch<LiveDataPump>();
    final recording = engine.state == RecordingState.recording ||
        engine.state == RecordingState.paused;

    return HpiPrimaryButton(
      label: recording
          ? 'Stop · ${formatDuration(engine.elapsedTime)}'
          : 'Start recording',
      icon: recording ? Icons.stop : Icons.fiber_manual_record,
      tone: recording ? p.error : p.accent,
      onPressed: () async {
        if (recording) {
          await stopRecordingAndExport(context);
        } else {
          await pump.controller.startRecording();
        }
      },
    );
  }
}
