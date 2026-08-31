import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/studio/studio_home.dart';
import 'services/ble_service.dart';
import 'services/data_parser.dart';
import 'services/eeg_packet_service.dart';
import 'services/filter_integration_service.dart';
import 'services/hrv_packet_service.dart';
import 'services/live_data_pump.dart';
import 'services/recording_engine.dart';
import 'services/recording_export_service.dart';
import 'services/recording_file_service.dart';
import 'services/throughput_monitor.dart';
import 'services/usb_serial_service.dart';
import 'services/wifi_serial_service.dart';
import 'shell/studio_nav.dart';
import 'shell/studio_settings.dart';
import 'shell/studio_shell.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1600, 1000),
      minimumSize: Size(1200, 800),
      title: 'HealthyPi Studio',
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const HealthyPiStudio());
}

class HealthyPiStudio extends StatelessWidget {
  const HealthyPiStudio({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ── Shell state ──────────────────────────────────────────────────────
        ChangeNotifierProvider(create: (_) => StudioNavController()),
        ChangeNotifierProvider(create: (_) => StudioSettings()),
        ChangeNotifierProvider(create: (_) => StudioSession()),
        ChangeNotifierProvider(create: (_) => StudioLinkSnapshot()),

        // ── Transports and parsing ───────────────────────────────────────────
        ChangeNotifierProvider(create: (_) => DataParser()),
        ChangeNotifierProvider(create: (_) => BleService()),

        // Registered before the transports because `UsbSerialService`'s wiring
        // reads it. `create` gets the MultiProvider's own context, which sees
        // only the providers *above* it — so a provider listed lower down is
        // invisible no matter how late the post-frame callback runs.
        ChangeNotifierProvider(create: (_) => RecordingEngine()),
        ChangeNotifierProvider(
          create: (context) {
            // Deferred so every provider above is available before wiring.
            final wifi = WifiSerialService();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              wifi.setDataParser(context.read<DataParser>());
            });
            return wifi;
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final usb = UsbSerialService();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              usb.setDataParser(context.read<DataParser>());
              // Keep "Auto-start streaming on connect" pushed into the service:
              // it decides whether opening the control port also sends
              // stream_start, and it must be current at the moment of connect,
              // not at the moment the toggle was flipped.
              final settings = context.read<StudioSettings>();
              void sync() => usb.autoStartStreaming = settings.autoStartOnConnect;
              sync();
              settings.addListener(sync);

              // The firmware version is read off the control port; recordings
              // stamp it into their header, so it has to reach the engine.
              final engine = context.read<RecordingEngine>();
              usb.addListener(() {
                engine.deviceFirmwareVersion = usb.firmwareVersion ?? '';
              });
            });
            return usb;
          },
        ),

        // ── Recording and export ─────────────────────────────────────────────
        ChangeNotifierProvider(create: (_) => RecordingFileService()),
        ChangeNotifierProvider(create: (_) => RecordingExportService()),

        // ── Analysis and diagnostics ─────────────────────────────────────────
        Provider<FilterIntegrationService>(
          create: (_) => FilterIntegrationService(filteringEnabled: false),
        ),
        ChangeNotifierProvider(create: (_) => ThroughputMonitor()),
        ChangeNotifierProvider(
          create: (context) {
            final hrv = HRVPacketService();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              hrv.connectToParser(context.read<DataParser>());
            });
            return hrv;
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final eeg = EEGPacketService();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              eeg.connectToParser(context.read<DataParser>());
            });
            return eeg;
          },
        ),

        // Acquisition sits at shell level so a recording survives navigation.
        ChangeNotifierProvider(
          create: (context) => LiveDataPump(
            dataParser: context.read<DataParser>(),
            usb: context.read<UsbSerialService>(),
            wifi: context.read<WifiSerialService>(),
            recordingEngine: context.read<RecordingEngine>(),
            filterService: context.read<FilterIntegrationService>(),
            throughput: context.read<ThroughputMonitor>(),
          ),
          lazy: false,
        ),
      ],
      child: const _StudioApp(),
    );
  }
}

class _StudioApp extends StatelessWidget {
  const _StudioApp();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StudioSettings>();
    return MaterialApp(
      title: 'HealthyPi Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      // "Reduce motion" in Settings reaches every pulsing indicator through the
      // standard accessibility flag rather than a bespoke channel.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: settings.reduceMotion),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const StudioHome(),
    );
  }
}
