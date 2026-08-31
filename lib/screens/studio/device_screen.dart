import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart' show ImageSlot;

import '../../services/data_parser.dart';
import '../../services/live_data_pump.dart';
import '../../services/smp_serial_client.dart';
import '../../services/usb_serial_service.dart';
import '../../services/wifi_serial_service.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_settings.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_brand.dart';
import '../../widgets/hpi/hpi_primitives.dart';
import '../../widgets/hpi/hpi_table.dart';

/// Where the MCUmgr SMP session is carried.
enum OtaTransport { usb, wifi }

/// Device & firmware (design 2g).
///
/// Identity, health counters and the sensor inventory by part number. OTA is a
/// card inside the shell rather than its own `Scaffold`, with the
/// streaming-paused consequence stated up front.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => DeviceScreenState();
}

class DeviceScreenState extends State<DeviceScreen> {
  final TextEditingController _host =
      TextEditingController(text: 'healthypi.local');
  OtaTransport _transport = OtaTransport.usb;
  String? _m7Path;
  String? _m4Path;
  bool _busy = false;
  bool _done = false;
  double _progress = 0;
  String _status = 'Select a signed firmware image to begin.';

  bool get isUpdating => _busy;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  List<Widget> buildStatusItems(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    if (_busy) {
      return [
        StatusItem('Updating firmware · streaming paused',
            icon: Icons.system_update, tone: p.accent),
        StatusItem('${(_progress * 100).toStringAsFixed(0)}% transferred'),
        const StatusItem('do not disconnect'),
      ];
    }
    return [
      StatusItem(
        usb.controlConnected ? 'Control port open (CDC1)' : 'No control port',
        icon: usb.controlConnected ? Icons.check_circle : Icons.info_outline,
        tone: usb.controlConnected ? p.success : p.textFaint,
      ),
      StatusItem(usb.isConnected
          ? 'USB ${usb.connectedPortName?.split('/').last ?? ""}'
          : 'not attached over USB'),
      if (_done) const StatusItem('update sent · device rebooting'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final parser = context.watch<DataParser>();

    return ScreenBody(
      header: ScreenHeader(
        title: StudioDestination.device.title,
        badge: _busy
            ? HpiBadge('Updating', tone: p.accent)
            : (usb.controlConnected
                ? HpiBadge('Connected', tone: p.success)
                : HpiBadge('No control port', tone: p.textMuted)),
        subtitle: usb.isConnected
            ? 'HealthyPi 6 · ${usb.connectedPortName} · '
                '${parser.protocolVersionString}'
            : 'Connect a board over USB to read its identity and update firmware',
      ),
      child: ScreenColumns(
        sideWidth: 352,
        side: _FirmwareColumn(state: this),
        main: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _IdentityCard(),
            kCardGap,
            const _CountersRow(),
            kCardGap,
            const Expanded(child: _SensorInventory()),
          ],
        ),
      ),
    );
  }

  // ── OTA ────────────────────────────────────────────────────────────────────

  Future<void> pick({required bool m7}) async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: m7
          ? 'Select signed M7 image (.bin)'
          : 'Select signed M4 image (.bin)',
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (res == null || res.files.isEmpty) return;
    setState(() {
      if (m7) {
        _m7Path = res.files.single.path;
      } else {
        _m4Path = res.files.single.path;
      }
    });
  }

  /// Upload each image into its MCUboot secondary slot, mark it pending, then
  /// reset so MCUboot installs and boots the new firmware.
  Future<void> install() async {
    if (_m7Path == null) {
      _set('Select at least the M7 image.');
      return;
    }
    final usb = context.read<UsbSerialService>();

    SmpSerialClient client;
    var ownsClient = false;
    if (_transport == OtaTransport.wifi) {
      final host = _host.text.trim();
      if (host.isEmpty) {
        _set('Enter the device host (e.g. healthypi.local).');
        return;
      }
      setState(() {
        _busy = true;
        _done = false;
        _progress = 0;
      });
      _set('Connecting to $host:9000…');
      final tcp = SmpSerialClient();
      if (!await tcp.openTcp(host)) {
        _fail('WiFi connect to $host:9000 failed. Is the device on WiFi with '
            'the SMP gateway up?');
        return;
      }
      client = tcp;
      ownsClient = true;
    } else {
      if (!usb.controlConnected) {
        _set('Control port not open — connect the device over USB first.');
        return;
      }
      setState(() {
        _busy = true;
        _done = false;
        _progress = 0;
      });
      client = usb.control;
    }

    try {
      // Free the link: the stream would otherwise compete with the upload.
      client.streamStop();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      _set('Uploading M7 image…');
      final m7 = Uint8List.fromList(await File(_m7Path!).readAsBytes());
      if (!await client.imageUpload(m7,
          imageIndex: 0,
          onProgress: (sent, total) => _setProgress(sent / total))) {
        _fail('M7 upload failed.');
        return;
      }
      final List<int> m7Sha = client.sha256(m7);
      _set('Verifying staged M7 image…');
      if (!await client.verifyStaged(m7Sha, imageIndex: 0)) {
        _fail('M7 verification failed — the image the device staged does not '
            'match the file that was sent. Nothing has been marked for boot.');
        return;
      }
      if (!await client.imageTest(m7Sha)) {
        _fail('M7 image test (mark pending) failed.');
        return;
      }

      if (_m4Path != null) {
        _set('Uploading M4 image…');
        _setProgress(0);
        final m4 = Uint8List.fromList(await File(_m4Path!).readAsBytes());
        if (!await client.imageUpload(m4,
            imageIndex: 1,
            onProgress: (sent, total) => _setProgress(sent / total))) {
          _fail('M4 upload failed.');
          return;
        }
        final List<int> m4Sha = client.sha256(m4);
        _set('Verifying staged M4 image…');
        if (!await client.verifyStaged(m4Sha, imageIndex: 1)) {
          _fail('M4 verification failed — the image the device staged does not '
              'match the file that was sent. Nothing has been marked for boot.');
          return;
        }
        if (!await client.imageTest(m4Sha)) {
          _fail('M4 image test (mark pending) failed.');
          return;
        }
      }

      _set('Rebooting device to install…');
      await client.osReset();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
        _progress = 1;
        _status = 'Update sent. The device is rebooting to install the new '
            'firmware and will reconnect in a few seconds. It is running on '
            'trial until you confirm it — use Confirm firmware under '
            'Maintenance once it is back, or MCUboot reverts on the next '
            'reboot.';
      });
    } catch (e) {
      _fail('Update error: $e');
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Confirm the image the device is currently running.
  ///
  /// MCUboot boots a tested image on trial and reverts on the next reboot
  /// unless the host confirms it. That confirmation cannot happen during the
  /// update — the device is rebooting — so it is a separate step once the board
  /// is back, which also proves the new firmware actually came up and can talk.
  Future<void> confirmRunningFirmware(BuildContext context) async {
    final UsbSerialService usb = context.read<UsbSerialService>();
    final ImageSlot? running = await usb.control.runningImage();
    if (!context.mounted) return;

    if (running == null) {
      _snack(context, 'Could not read the device image list.');
      return;
    }
    if (running.confirmed) {
      _snack(context,
          'Already confirmed — running ${running.version} (${running.shortHash}).');
      return;
    }
    final bool ok = await usb.control.imageConfirm(running.hash);
    if (!context.mounted) return;
    _snack(
      context,
      ok
          ? 'Confirmed ${running.version} (${running.shortHash}). It will be '
              'kept across reboots.'
          : 'Confirm failed — the device is still on trial and will revert on '
              'the next reboot.',
    );
  }

  void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void setTransport(OtaTransport t) => setState(() => _transport = t);

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  void _setProgress(double v) {
    if (mounted) setState(() => _progress = v.clamp(0, 1));
  }

  void _fail(String s) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = s;
    });
  }
}

/// Identity: the mono lockup beside the facts that identify this board.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final wifi = context.watch<WifiSerialService>();
    final parser = context.watch<DataParser>();
    final pump = context.watch<LiveDataPump>();

    // Only what the transport and protocol actually tell us. The firmware
    // version is read over MCUmgr when the control port opens
    // (`UsbSerialService.firmwareVersion`); serial and MAC are in neither the
    // stream nor the MCUmgr surface, so they stay em dashes rather than
    // invented values.
    final facts = <(String, String)>[
      ('Model', usb.isConnected || wifi.isConnected ? 'HealthyPi 6' : '—'),
      ('Transport', usb.isConnected ? 'USB CDC' : (wifi.isConnected ? 'WiFi TCP' : '—')),
      ('Port', usb.connectedPortName?.split('/').last ?? '—'),
      ('Protocol', parser.protocolVersionString),
      ('Control port', usb.controlConnected ? 'CDC1 open' : 'closed'),
      ('Stream uptime', formatDuration(pump.streamDuration)),
      ('Serial', '—'),
      ('Firmware', usb.firmwareVersion ?? '—'),
      ('Licence', 'CERN-OHL-P v2'),
    ];

    return HpiCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.well,
              border: Border.all(color: p.outlineSoft),
              borderRadius: HpiRadius.cardR,
            ),
            child: const HpiMonoMark(width: 64),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                for (final f in facts)
                  SizedBox(
                    width: 210,
                    child: HpiKeyValue(f.$1, f.$2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Health counters. Battery, storage and die temperature are not in the current
/// stream, so the row reports the link counters the app does have.
class _CountersRow extends StatelessWidget {
  const _CountersRow();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final parser = context.watch<DataParser>();
    final settings = context.watch<StudioSettings>();
    final data = parser.currentOpenViewData;

    return SizedBox(
      height: 104,
      child: Row(
        children: [
          Expanded(
            child: _Counter(
              label: 'Packets',
              value: '${parser.packetsReceived}',
              unit: 'total',
              tone: p.brand,
            ),
          ),
          kCardGapH,
          Expanded(
            child: _Counter(
              label: 'Skin temp',
              value: data == null || data.temperature == 0
                  ? '—'
                  : settings.temperature(data.temperature).toStringAsFixed(1),
              unit: settings.temperatureUnit,
              tone: p.trace.temperature,
            ),
          ),
          kCardGapH,
          Expanded(
            child: _Counter(
              label: 'Sequence gaps',
              value: '${parser.sequenceGaps}',
              unit: '${parser.missingBySequence} missing',
              tone: parser.sequenceGaps == 0 ? p.success : p.warning,
            ),
          ),
          kCardGapH,
          Expanded(
            child: _Counter(
              label: 'Parse failures',
              value: '${parser.packetsDropped}',
              unit: 'packets',
              tone: parser.packetsDropped == 0 ? p.success : p.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.unit,
    required this.tone,
  });

  final String label;
  final String value;
  final String unit;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return HpiTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HpiLabel(label),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HpiText.vital(tone)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(unit.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HpiText.unit(p)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the sensor inventory will go, once the firmware can report one.
///
/// This card used to list part numbers, bus addresses and sample rates for
/// front-ends that are not on a HealthyPi 6 — none of it came off the wire, and
/// the group-64 surface has no device-info command to fill it with. A table of
/// invented hardware is worse than no table: it reads as a probe result, so a
/// wrong row looks like a fault on the board. It stays out until the firmware
/// answers for its own inventory.
class _SensorInventory extends StatelessWidget {
  const _SensorInventory();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return HpiCard(
      child: Center(
        child: SizedBox(
          width: 420,
          child: HpiColumn(
            gap: 10,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.memory_outlined, size: 30, color: p.textFaint),
              const HpiLabel('Sensor inventory'),
              Text(
                'The firmware does not report its front-end inventory yet, so '
                'Studio has nothing to list here. Per-stream rates and health '
                'are on the Link health screen, which reports what actually '
                'arrives.',
                textAlign: TextAlign.center,
                style: HpiText.body(p).copyWith(fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Firmware update and maintenance, in the side column.
class _FirmwareColumn extends StatelessWidget {
  const _FirmwareColumn({required this.state});

  final DeviceScreenState state;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final ready = state._transport == OtaTransport.wifi || usb.controlConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HpiCard(
          borderColor: state._busy || state._m7Path != null
              ? p.accent.withValues(alpha: 0.35)
              : null,
          child: HpiColumn(
            gap: 12,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update, size: 18, color: p.accent),
                  const SizedBox(width: 9),
                  Expanded(child: HpiSectionTitle('Firmware update')),
                ],
              ),
              HpiSegmented<OtaTransport>(
                expand: true,
                height: 32,
                segments: const [
                  HpiSegment(value: OtaTransport.usb, label: 'USB CDC1'),
                  HpiSegment(value: OtaTransport.wifi, label: 'WiFi TCP'),
                ],
                value: state._transport,
                onChanged: state._busy ? null : state.setTransport,
              ),
              if (state._transport == OtaTransport.wifi)
                SizedBox(
                  height: 34,
                  child: TextField(
                    controller: state._host,
                    enabled: !state._busy,
                    style: HpiText.mono(p.textPrimary, size: 12),
                    decoration: const InputDecoration(
                      hintText: 'healthypi.local',
                    ),
                  ),
                ),
              _FileRow(
                label: 'M7 firmware (required)',
                path: state._m7Path,
                enabled: !state._busy,
                onPick: () => state.pick(m7: true),
              ),
              _FileRow(
                label: 'M4 firmware (optional)',
                path: state._m4Path,
                enabled: !state._busy,
                onPick: () => state.pick(m7: false),
              ),
              if (state._busy) ...[
                Row(
                  children: [
                    Expanded(
                      child: HpiMono('Transferring',
                          size: 11, color: p.textSecondary),
                    ),
                    HpiMono('${(state._progress * 100).toStringAsFixed(0)}%',
                        size: 11, color: p.accent),
                  ],
                ),
                HpiMeter(fraction: state._progress, color: p.accent, height: 6),
              ],
              HpiNote(state._status,
                  color: state._done ? p.success : p.textSecondary),
              if (!ready)
                HpiNote(
                  'No control port. Connect the HealthyPi 6 over USB — the '
                  'second CDC interface carries the MCUmgr session — or switch '
                  'to WiFi.',
                  color: p.accent,
                ),
              const HpiRule(),
              HpiNote(
                'Keep the board connected. Streaming is paused for the duration '
                'and resumes on reboot. Verify the version after it comes back.',
              ),
              if (state._busy)
                HpiGhostButton(
                  label: 'Transfer in progress…',
                  icon: Icons.hourglass_top,
                  expand: true,
                  onPressed: null,
                )
              else
                HpiGhostButton(
                  label: 'Install firmware',
                  icon: Icons.upload,
                  expand: true,
                  tone: p.accent,
                  onPressed:
                      ready && state._m7Path != null ? state.install : null,
                ),
            ],
          ),
        ),
        kCardGap,
        Expanded(
          child: HpiCard(
            child: HpiColumn(
              gap: 10,
              children: [
                const HpiLabel('Maintenance'),
                HpiActionRow(
                  icon: Icons.restart_alt,
                  title: 'Reboot device',
                  onTap: usb.controlConnected && !state._busy
                      ? () async {
                          await usb.control.osReset();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Reset command sent')),
                            );
                          }
                        }
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.verified_outlined,
                  title: 'Confirm firmware',
                  onTap: usb.controlConnected && !state._busy
                      ? () => state.confirmRunningFirmware(context)
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.play_arrow,
                  title: 'Start device stream',
                  onTap: usb.controlConnected && !state._busy
                      ? () => usb.control.streamStart()
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.stop,
                  title: 'Stop device stream',
                  onTap: usb.controlConnected && !state._busy
                      ? () => usb.control.streamStop()
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.sd_card,
                  title: usb.deviceRecording
                      ? 'Stop on-board recording'
                      : 'Start on-board recording',
                  onTap: usb.controlConnected && !state._busy
                      ? () => usb.setDeviceRecording(!usb.deviceRecording)
                      : null,
                ),
                const HpiRule(),
                HpiNote(
                  'Schematics, KiCad files and firmware sources for the board '
                  'are published on GitHub under CERN-OHL-P v2.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.label,
    required this.path,
    required this.enabled,
    required this.onPick,
  });

  final String label;
  final String? path;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HpiLabel(label),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: p.well,
                  border: Border.all(color: p.outline),
                  borderRadius: HpiRadius.buttonR,
                ),
                child: HpiMono(
                  path == null
                      ? 'no file selected'
                      : path!.split(Platform.pathSeparator).last,
                  size: 11,
                  color: path == null ? p.textFaint : p.textPrimary,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            HpiGhostButton(
              label: 'Choose…',
              height: 32,
              onPressed: enabled ? onPick : null,
            ),
          ],
        ),
      ],
    );
  }
}
