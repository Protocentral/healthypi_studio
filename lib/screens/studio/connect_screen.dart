import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/usb_device_info.dart';
import '../../services/usb_serial_service.dart';
import '../../services/wifi_serial_service.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_brand.dart';
import '../../widgets/hpi/hpi_primitives.dart';

enum _SourceFilter { all, usb, wifi }

/// Connect (design 2h) — the Live destination's empty state.
///
/// The chrome stays exactly the same, rail dimmed rather than gone, so the app
/// never feels like a different program. USB and WiFi in one list, with an
/// offline path to a saved recording.
///
/// **BLE is disabled.** `BleService` connects but never assigns its data or
/// command characteristics, so no samples and no control traffic flow over it —
/// offering it here would be a connection that does nothing. It stays out of
/// the UI until the firmware's BLE surface and the transport are both real.
/// The service and its provider are left in place so re-enabling it is a change
/// to this file alone.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => ConnectScreenState();
}

class ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _wifiHost = TextEditingController();

  /// USB only until the user asks for more: it is the transport that carries
  /// live data, control and firmware update, and the only one that enumerates
  /// without being told an address.
  _SourceFilter _filter = _SourceFilter.usb;
  String? _connecting;
  String? _error;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    // USB enumeration is free and silent, so it runs on arrival.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUsb());
  }

  @override
  void dispose() {
    _wifiHost.dispose();
    super.dispose();
  }

  List<Widget> buildStatusItems(BuildContext context) {
    final p = context.hpi;
    return [
      StatusItem('No device connected', icon: Icons.usb_off, tone: p.textFaint),
      StatusItem(_scanning ? 'scanning USB' : 'idle'),
      if (_error != null) StatusItem(_error!, tone: p.error),
    ];
  }

  Future<void> _refreshUsb() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _scanning = true;
    });
    try {
      await context.read<UsbSerialService>().refreshDevices();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final nav = context.read<StudioNavController>();

    final ports = usb.getAllPortsInfo();
    final showUsb =
        _filter == _SourceFilter.all || _filter == _SourceFilter.usb;
    final showWifi =
        _filter == _SourceFilter.all || _filter == _SourceFilter.wifi;
    final found = showUsb ? ports.length : 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: SizedBox(
          width: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: HpiMonoMark(
                  width: 96,
                  variant: HpiMonoVariant.white,
                  opacity: 0.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'CONNECT A DEVICE',
                textAlign: TextAlign.center,
                style: HpiText.screenTitle(p).copyWith(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                'Plug a HealthyPi 6 in over USB, or reach it over WiFi. Studio '
                'keeps showing demo data until a real device is attached.',
                textAlign: TextAlign.center,
                style: HpiText.body(p).copyWith(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 18),
              HpiCard(
                padding: EdgeInsets.zero,
                clip: true,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: p.well,
                        border: Border(
                          bottom: BorderSide(color: p.outlineSoft),
                        ),
                      ),
                      child: Row(
                        children: [
                          HpiStatusDot(
                            color: p.brand,
                            size: 9,
                            pulse: _scanning,
                            period: const Duration(milliseconds: 1200),
                          ),
                          const SizedBox(width: 10),
                          HpiLabel(
                            _scanning ? 'Scanning · $found found' : '$found found',
                          ),
                          const Spacer(),
                          HpiSegmented<_SourceFilter>(
                            segments: const [
                              HpiSegment(
                                value: _SourceFilter.all,
                                label: 'All',
                              ),
                              HpiSegment(
                                value: _SourceFilter.usb,
                                label: 'USB',
                              ),
                              HpiSegment(
                                value: _SourceFilter.wifi,
                                label: 'WiFi',
                              ),
                            ],
                            value: _filter,
                            onChanged: (f) => setState(() => _filter = f),
                          ),
                          const SizedBox(width: 10),
                          HpiToolButton(
                            icon: Icons.refresh,
                            label: 'Rescan',
                            onPressed: _refreshUsb,
                          ),
                        ],
                      ),
                    ),
                    if (showUsb)
                      for (final port in ports) _usbRow(context, port),
                    if (showWifi) _wifiRow(context),
                    if (found == 0 && !showWifi)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 26),
                        child: Center(
                          child: HpiNote(
                            'Nothing found yet. Plug the board in and press '
                            'Rescan.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // IntrinsicHeight, not stretch: this Row lives inside a scroll
              // view, so it has no bounded height to stretch into.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: HpiCard(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: HpiColumn(
                          gap: 8,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const HpiLabel('Work offline'),
                            HpiGhostButton(
                              label: 'Keep running demo data',
                              icon: Icons.play_circle,
                              expand: true,
                              onPressed: nav.dismissConnect,
                            ),
                            HpiNote(
                              'Every screen works against demo data, so the '
                              'layout and controls are explorable without '
                              'hardware.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HpiCard(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: HpiColumn(
                          gap: 8,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const HpiLabel('Open a recording'),
                            HpiGhostButton(
                              label: 'Recordings & export',
                              icon: Icons.folder_open,
                              expand: true,
                              onPressed: () =>
                                  nav.go(StudioDestination.records),
                            ),
                            HpiNote(
                              'Saved .hpd files can be inspected and '
                              'exported without a board attached.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: p.well,
                  border: Border.all(color: p.outline),
                  borderRadius: HpiRadius.buttonR,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.help_outline, size: 17, color: p.accent),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        Platform.isLinux
                            ? 'Board not listed? On Linux your user must be in '
                                  'the dialout group to open the serial port.'
                            : (Platform.isMacOS
                                  ? 'Board not listed? On macOS confirm the CDC '
                                        'driver claimed the port — it appears as '
                                        '/dev/cu.usbmodem*.'
                                  : 'Board not listed? Check that the USB CDC '
                                        'driver is installed and the port is not '
                                        'held by another program.'),
                        style: HpiText.body(
                          p,
                        ).copyWith(fontSize: 11.5, height: 1.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                HpiNote(_error!, color: p.error),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _usbRow(BuildContext context, UsbDeviceInfo port) {
    final p = context.hpi;
    final busy = _connecting == port.portName;
    return _DeviceRow(
      icon: Icons.usb,
      iconTone: port.isHealthyPi ? p.brand : p.textMuted,
      highlight: port.isHealthyPi,
      title: port.displayName,
      subtitle: '${port.portName} · VID ${port.vidHex} PID ${port.pidHex}',
      transport: 'USB CDC',
      detail: port.serialNumber ?? 'wired',
      primary: port.isHealthyPi,
      busy: busy,
      onConnect: busy ? null : () => _connectUsb(port.portName),
    );
  }

  Widget _wifiRow(BuildContext context) {
    final p = context.hpi;
    final busy = _connecting == 'wifi';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi, size: 19, color: p.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HealthyPi over WiFi',
                  style: HpiText.uiTitle(p).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _wifiHost,
                    style: HpiText.mono(p.textPrimary, size: 11.5),
                    decoration: const InputDecoration(
                      hintText: '192.168.1.50  ·  TCP port 5000',
                    ),
                    onSubmitted: (_) => _connectWifi(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          HpiGhostButton(
            label: busy ? 'Connecting…' : 'Connect',
            height: 32,
            onPressed: busy ? null : _connectWifi,
          ),
        ],
      ),
    );
  }

  Future<void> _connectUsb(String portName) async {
    setState(() {
      _connecting = portName;
      _error = null;
    });
    // Transports are exclusive: drop WiFi before claiming the serial port.
    final wifi = context.read<WifiSerialService>();
    if (wifi.isConnected) await wifi.disconnect();
    if (!mounted) return;
    final ok = await context.read<UsbSerialService>().connect(portName);
    if (!mounted) return;
    setState(() {
      _connecting = null;
      _error = ok ? null : 'Could not open $portName. Is it already in use?';
    });
  }

  Future<void> _connectWifi() async {
    final host = _wifiHost.text.trim();
    if (host.isEmpty) {
      setState(() => _error = 'Enter the device IP address or hostname.');
      return;
    }
    setState(() {
      _connecting = 'wifi';
      _error = null;
    });
    final usb = context.read<UsbSerialService>();
    if (usb.isConnected) await usb.disconnect();
    if (!mounted) return;
    final ok = await context.read<WifiSerialService>().connect(host);
    if (!mounted) return;
    setState(() {
      _connecting = null;
      _error = ok ? null : 'Could not reach $host on port 5000.';
    });
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.icon,
    required this.iconTone,
    required this.title,
    required this.subtitle,
    required this.transport,
    required this.detail,
    required this.onConnect,
    this.primary = false,
    this.highlight = false,
    this.busy = false,
  });

  final IconData icon;
  final Color iconTone;
  final String title;
  final String subtitle;
  final String transport;
  final String detail;
  final VoidCallback? onConnect;

  /// A recognised HealthyPi gets the amber primary button; anything else gets
  /// the quiet one.
  final bool primary;
  final bool highlight;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: highlight ? p.brand.withValues(alpha: 0.07) : null,
        border: Border(
          top: BorderSide(color: p.divider),
          left: BorderSide(
            color: highlight ? p.brand : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: iconTone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HpiText.uiTitle(p).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 3),
                HpiMono(
                  subtitle,
                  size: 10.5,
                  color: p.textFaint,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: HpiMono(transport, size: 11, color: p.textMuted),
          ),
          SizedBox(
            width: 96,
            child: HpiMono(detail, size: 10.5, color: p.textMuted),
          ),
          const SizedBox(width: 8),
          if (primary)
            HpiPrimaryButton(
              label: busy ? 'Connecting…' : 'Connect',
              height: 32,
              onPressed: onConnect,
            )
          else
            HpiGhostButton(
              label: busy ? 'Connecting…' : 'Connect',
              height: 32,
              onPressed: onConnect,
            ),
        ],
      ),
    );
  }
}
