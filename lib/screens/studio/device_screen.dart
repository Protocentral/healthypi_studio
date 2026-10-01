import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/data_parser.dart';
import '../../services/live_data_pump.dart';
import '../../services/firmware/bundle.dart';
import '../../services/firmware/firmware_updater.dart';
import '../../services/firmware_update_service.dart';
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

/// Device & firmware (design 2g).
///
/// Identity, health counters and firmware update. The update itself runs in
/// [FirmwareUpdateService] at shell level; this screen only drives it.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => DeviceScreenState();
}

class DeviceScreenState extends State<DeviceScreen> {
  List<Widget> buildStatusItems(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final fw = context.watch<FirmwareUpdateService>();
    if (fw.busy) {
      final f = fw.progress.fraction;
      return [
        StatusItem('Updating firmware · streaming paused',
            icon: Icons.system_update, tone: p.accent),
        StatusItem(_stageLabel(fw.progress.stage) +
            (f == null ? '' : ' · ${(f * 100).toStringAsFixed(0)}%')),
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
      if (usb.lastControlFailure case final f?)
        StatusItem(f.toString(), icon: Icons.error_outline, tone: p.warning),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final fw = context.watch<FirmwareUpdateService>();
    final parser = context.watch<DataParser>();

    return ScreenBody(
      header: ScreenHeader(
        title: StudioDestination.device.title,
        badge: fw.busy
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
        side: const _FirmwareColumn(),
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
}

String _stageLabel(UpdateStage s) => switch (s) {
      UpdateStage.idle => 'Ready',
      UpdateStage.checking => 'Checking the device',
      UpdateStage.uploadingM4 => 'Uploading M4',
      UpdateStage.committingM4 => 'M4: verifying and writing bank 2',
      UpdateStage.uploadingM7 => 'Uploading M7',
      UpdateStage.markingM7 => 'M7: marking for install',
      UpdateStage.resetting => 'Rebooting the device',
      UpdateStage.verifying => 'Reading back versions',
      UpdateStage.done => 'Done',
      UpdateStage.failed => 'Failed',
    };

Future<void> _pickFirmware(BuildContext context) async {
  final fw = context.read<FirmwareUpdateService>();
  final res = await FilePicker.platform.pickFiles(
    dialogTitle: 'Select a firmware bundle (.hpifw) or a signed M7 image (.bin)',
    type: FileType.custom,
    allowedExtensions: const ['hpifw', 'bin'],
  );
  final path = res?.files.single.path;
  if (path != null) await fw.select(path);
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
  const _FirmwareColumn();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final fw = context.watch<FirmwareUpdateService>();
    final bundle = fw.bundle;
    final outcome = fw.outcome;
    final fraction = fw.progress.fraction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HpiCard(
          borderColor: fw.busy || fw.source != FirmwareSource.none
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
              _FileRow(
                label: 'Firmware bundle (.hpifw)',
                path: fw.path,
                enabled: !fw.busy,
                onPick: () => _pickFirmware(context),
              ),
              if (fw.selectionError case final e?)
                HpiNote(e, color: p.error)
              else if (bundle != null) ...[
                HpiKeyValue('Release', bundle.release),
                for (final name in FirmwareBundle.applyOrder)
                  if (bundle.images[name] case final img?)
                    HpiKeyValue(name.toUpperCase(), img.version),
                HpiKeyValue('Signed by', bundle.signer.label,
                    valueColor:
                        bundle.signer.development ? p.warning : p.success),
              ] else if (fw.source == FirmwareSource.rawM7) ...[
                HpiKeyValue('M7 image', fw.rawVersion ?? '—'),
                HpiNote(
                  'A single M7 image, outside a bundle: there is no manifest '
                  'signature to check, and the M4 is left as it is. MCUboot '
                  'still verifies the image signature before booting it.',
                  color: p.warning,
                ),
              ],
              if (fw.busy) ...[
                Row(
                  children: [
                    Expanded(
                      child: HpiMono(_stageLabel(fw.progress.stage),
                          size: 11, color: p.textSecondary),
                    ),
                    if (fraction != null)
                      HpiMono('${(fraction * 100).toStringAsFixed(0)}%',
                          size: 11, color: p.accent),
                  ],
                ),
                HpiMeter(fraction: fraction ?? 0, color: p.accent, height: 6),
              ],
              if (fw.error case final e?)
                HpiNote(e, color: p.error)
              else if (outcome != null)
                HpiNote(
                  outcome.applied.isEmpty
                      ? 'Nothing to install: the device already runs these '
                          'versions.'
                      : outcome.ok
                          ? 'Installed and verified. The device reports '
                              'M7 ${outcome.versionsAfter['m7'] ?? '—'}, '
                              'M4 ${_orDash(outcome.versionsAfter['m4'])}.'
                          : 'The device came back, but did not report the '
                              'expected firmware. See the log below.',
                  color: outcome.ok ? p.success : p.error,
                ),
              if (fw.log.isNotEmpty)
                HpiWell(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: HpiMono(fw.log.join('\n'),
                        size: 10.5, color: p.textSecondary),
                  ),
                ),
              if (!usb.controlConnected)
                HpiNote(
                  'No control port. Connect the HealthyPi 6 over USB — the '
                  'second CDC interface carries the update session.',
                  color: p.accent,
                ),
              const HpiRule(),
              HpiNote(
                'Keep the board connected. Streaming pauses during the update, '
                'and the device reboots, twice if the M7 changed, before '
                'Studio reads back the installed versions. An older M7 is '
                'refused before upload: MCUboot would not boot it.',
              ),
              if (fw.busy)
                HpiGhostButton(
                  label: 'Update in progress…',
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
                  onPressed: fw.canInstall ? fw.install : null,
                ),
              // Present but unavailable, with the reason, per the honesty rule.
              HpiActionRow(
                icon: Icons.wifi,
                title: 'Update over Wi-Fi — needs the HealthyBridge SMP relay, '
                    'not yet in the ESP32 firmware',
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
                  onTap: usb.controlConnected && !fw.busy
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
                  icon: Icons.play_arrow,
                  title: 'Start device stream',
                  onTap: usb.controlConnected && !fw.busy
                      ? () => _report(context, usb.setDeviceStreaming(true),
                          'Device stream started')
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.stop,
                  title: 'Stop device stream',
                  onTap: usb.controlConnected && !fw.busy
                      ? () => _report(context, usb.setDeviceStreaming(false),
                          'Device stream stopped')
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.sd_card,
                  title: usb.deviceRecording
                      ? 'Stop on-board recording'
                      : 'Start on-board recording',
                  onTap: usb.controlConnected && !fw.busy
                      ? () => _report(
                          context,
                          usb.setDeviceRecording(!usb.deviceRecording),
                          usb.deviceRecording
                              ? 'On-board recording stopped'
                              : 'On-board recording started')
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

String _orDash(String? s) => s == null || s.isEmpty ? '—' : s;

/// Show the device's answer to a control command: the failure by name, or
/// [success].
Future<void> _report(
    BuildContext context, Future<HpiFailure?> result, String success) async {
  final failure = await result;
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(failure == null ? success : failure.toString())),
  );
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
