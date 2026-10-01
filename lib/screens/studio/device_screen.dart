import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/data_parser.dart';
import '../../services/device_status_service.dart';
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
            const _StatusCard(),
            kCardGap,
            const _WifiCard(),
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
    final status = context.watch<DeviceStatusService>();
    final info = status.info;
    final v = status.versions;

    // Only what the device and the transport report: identity from
    // device_info, versions from fw_versions, both read over the control port
    // when it opens. A field the device did not send stays an em dash.
    final m4 = v?.m4fw ?? info?.m4fw;
    final facts = <(String, String)>[
      ('Model', usb.isConnected || wifi.isConnected ? 'HealthyPi 6' : '—'),
      ('Serial', _orDash(info?.sn)),
      ('Board revision', _orDash(info?.br)),
      ('M7 firmware', _orDash(v?.m7fw ?? info?.fw ?? usb.firmwareVersion)),
      (
        'M4 firmware',
        m4 == null
            ? '—'
            : (m4.isEmpty ? '— (not bound to the M7 yet)' : m4),
      ),
      ('Wi-Fi co-processor', _orDash(v?.espfw ?? info?.espfw)),
      ('Device uptime', info?.up == null ? '—' : formatDuration(Duration(seconds: info!.up!))),
      (
        'Clock',
        status.clockError ??
            (status.clock == null
                ? '—'
                : '${status.clock}${status.clockSetByStudio ? ' (set by Studio)' : ''}'),
      ),
      (
        'Lock',
        switch (status.locked) {
          null => '—',
          true => 'Locked',
          false => 'Unlocked',
        },
      ),
      ('Transport', usb.isConnected ? 'USB CDC' : (wifi.isConnected ? 'WiFi TCP' : '—')),
      ('Port', usb.connectedPortName?.split('/').last ?? '—'),
      ('Control port', usb.controlPortName?.split('/').last ?? 'closed'),
      ('Protocol', parser.protocolVersionString),
      ('Stream uptime', formatDuration(pump.streamDuration)),
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

/// Health counters: the battery from telemetry, and the link counters.
class _CountersRow extends StatelessWidget {
  const _CountersRow();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final parser = context.watch<DataParser>();
    final settings = context.watch<StudioSettings>();
    final data = parser.currentOpenViewData;
    final t = context.watch<DeviceStatusService>().telemetry;
    final batteryUnit = [
      if (t?.vbatMv != null) '${t!.vbatMv} mV',
      if (t?.usb == true) 'on USB',
      if (t?.batt == false) 'no battery',
    ].join(' · ');

    return SizedBox(
      height: 104,
      child: Row(
        children: [
          Expanded(
            child: _Counter(
              label: 'Battery',
              value: t?.soc == null ? '—' : '${t!.soc}%',
              unit: batteryUnit.isEmpty ? 'not reported' : batteryUnit,
              tone: t?.ok == false ? p.warning : p.success,
            ),
          ),
          kCardGapH,
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

/// Stream, SD card and Transfer Mode, as the device reports them.
class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final status = context.watch<DeviceStatusService>();
    final st = status.stream;
    final sd = status.sd;

    String bytes(int? b) => b == null
        ? '—'
        : (b >= 1 << 20
            ? '${(b / (1 << 20)).toStringAsFixed(1)} MB'
            : '${(b / 1024).toStringAsFixed(0)} KB');

    final facts = <(String, String, Color?)>[
      (
        'Device stream',
        st?.active == null ? '—' : (st!.active! ? 'streaming' : 'stopped'),
        st?.active == true ? p.success : null,
      ),
      ('Frames sent', st?.sent == null ? '—' : '${st!.sent}', null),
      (
        'Dropped on device',
        st?.dropped == null ? '—' : '${st!.dropped}',
        (st?.dropped ?? 0) > 0 ? p.warning : null,
      ),
      (
        'SD recording',
        sd?.active == null ? '—' : (sd!.active! ? 'recording' : 'idle'),
        sd?.active == true ? p.accent : null,
      ),
      ('SD file', _orDash(sd?.path), null),
      ('SD written', bytes(sd?.bytes), null),
      ('Transfer Mode', usb.transferArmed ? 'armed' : 'off', null),
    ];

    return HpiCard(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 10,
        children: [
          for (final f in facts)
            SizedBox(
              width: 210,
              child: HpiKeyValue(f.$1, f.$2, valueColor: f.$3),
            ),
        ],
      ),
    );
  }
}

/// The Wi-Fi co-processor, driven over the USB control port. Its radios are
/// off at boot (the C6 is held in reset), so Wi-Fi streaming needs Enable
/// first.
class _WifiCard extends StatefulWidget {
  const _WifiCard();

  @override
  State<_WifiCard> createState() => _WifiCardState();
}

class _WifiCardState extends State<_WifiCard> {
  final _ssid = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ssid.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _run(Future<HpiFailure?> action, String success) async {
    setState(() => _busy = true);
    await _report(context, action, success);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final status = context.watch<DeviceStatusService>();
    final conn = status.conn;
    final wifi = status.wifi;
    final locked = status.locked == true;
    final ready = usb.controlConnected && !_busy;
    final link = switch (conn?.link) {
      null => '—',
      0 => 'off',
      1 => 'starting',
      2 => 'up',
      3 => 'fault',
      final n => 'state $n',
    };
    final radioOn = (conn?.link ?? 0) != 0;

    return HpiCard(
      padding: const EdgeInsets.all(16),
      child: HpiColumn(
        gap: 10,
        children: [
          HpiSectionTitle('Wi-Fi',
              note: 'co-processor radios are off at boot'),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              for (final f in <(String, String)>[
                ('Radio link', link),
                ('Network', _orDash(wifi?.ssid ?? conn?.ssid)),
                ('Address', _orDash(wifi?.ip ?? conn?.ip)),
                ('Signal', (wifi?.rssi ?? conn?.rssi) == null
                    ? '—'
                    : '${wifi?.rssi ?? conn?.rssi} dBm'),
              ])
                SizedBox(width: 210, child: HpiKeyValue(f.$1, f.$2)),
            ],
          ),
          Row(
            children: [
              HpiGhostButton(
                label: radioOn ? 'Turn radio off' : 'Turn Wi-Fi radio on',
                icon: Icons.power_settings_new,
                height: 32,
                onPressed: ready
                    ? () => _run(
                        radioOn
                            ? status.disableRadios()
                            : status.enableWifiRadio(),
                        radioOn ? 'Radio off' : 'Radio starting')
                    : null,
              ),
              const SizedBox(width: 8),
              HpiGhostButton(
                label: 'Start setup access point',
                icon: Icons.wifi_tethering,
                height: 32,
                onPressed: ready && radioOn
                    ? () => _run(status.startSoftAp(), 'Setup access point started')
                    : null,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _ssid,
                    enabled: ready && !locked,
                    style: HpiText.mono(p.textPrimary, size: 12),
                    decoration: const InputDecoration(hintText: 'Network name'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _pw,
                    enabled: ready && !locked,
                    obscureText: true,
                    style: HpiText.mono(p.textPrimary, size: 12),
                    decoration: const InputDecoration(hintText: 'Password'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              HpiGhostButton(
                label: 'Join',
                height: 32,
                onPressed: ready && !locked && radioOn
                    ? () => _run(
                        status.setWifiNetwork(_ssid.text.trim(), _pw.text),
                        'Network saved')
                    : null,
              ),
              const SizedBox(width: 8),
              HpiGhostButton(
                label: 'Forget',
                height: 32,
                onPressed: ready && !locked && radioOn
                    ? () => _run(status.forgetWifiNetwork(), 'Network forgotten')
                    : null,
              ),
            ],
          ),
          if (locked)
            HpiNote('Joining or forgetting a network needs an unlocked device. '
                'The setup access point works while locked.')
          else if (!radioOn && usb.controlConnected)
            HpiNote('Turn the radio on to join a network or stream over Wi-Fi.'),
        ],
      ),
    );
  }
}

/// Where the sensor inventory will go, once the firmware can report one.
///
/// This card used to list part numbers, bus addresses and sample rates for
/// front-ends that are not on a HealthyPi 6 — none of it came off the wire. A
/// table of invented hardware is worse than no table: it reads as a probe
/// result, so a wrong row looks like a fault on the board. The firmware does
/// report HealthyLink modules (`module_list`); listing them here is planned.
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
    final locked = context.watch<DeviceStatusService>().locked == true;
    final lockNote = locked ? ' — device locked' : '';
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
              if (fw.notice case final n?) HpiNote(n, color: p.accent),
              if (fw.error case final e?)
                HpiNote(e, color: p.error)
              else if (fw.recovered case final r?)
                HpiNote(
                  'Recovered: the application is back on '
                  '${r.port.split('/').last} running M7 ${r.m7}.'
                  '${r.m4Behind ? ' The M4 is behind; install the bundle '
                      'again to bring it into line.' : ''}',
                  color: r.m4Behind ? p.warning : p.success,
                )
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
              for (final r in usb.recoveryPorts) ...[
                const HpiRule(),
                HpiKeyValue('Recovery mode', r.portName.split('/').last,
                    valueColor: p.warning),
                HpiNote(
                  'Recovery writes the selected M7 straight into the running '
                  'slot. It bypasses downgrade protection and leaves the M4 '
                  'as it is.',
                ),
                HpiGhostButton(
                  label: 'Recover with the selected firmware',
                  icon: Icons.healing,
                  expand: true,
                  tone: p.warning,
                  onPressed: fw.canRecover ? () => fw.recover(r.portName) : null,
                ),
              ],
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
                  icon: Icons.healing,
                  title: 'Enter recovery mode',
                  onTap: usb.controlConnected && !fw.busy
                      ? () => _confirmEnterRecovery(context)
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.play_arrow,
                  title: 'Start device stream$lockNote',
                  onTap: usb.controlConnected && !fw.busy && !locked
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
                      : 'Start on-board recording$lockNote',
                  onTap: usb.controlConnected &&
                          !fw.busy &&
                          (usb.deviceRecording || !locked)
                      ? () => _report(
                          context,
                          usb.setDeviceRecording(!usb.deviceRecording),
                          usb.deviceRecording
                              ? 'On-board recording stopped'
                              : 'On-board recording started')
                      : null,
                ),
                HpiActionRow(
                  icon: Icons.usb,
                  title: usb.transferArmed
                      ? 'Disarm Transfer Mode'
                      : 'Arm Transfer Mode (SD card as a USB drive)$lockNote',
                  onTap: usb.controlConnected &&
                          !fw.busy &&
                          (usb.transferArmed || !locked)
                      ? () => _toggleTransferMode(context, usb)
                      : null,
                ),
                if (locked)
                  HpiNote(
                    'The device is locked, so it refuses stream, recording and '
                    'Transfer Mode commands. Unlocking needs its shared secret, '
                    'which Studio does not hold yet.',
                    color: p.warning,
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

Future<void> _toggleTransferMode(
    BuildContext context, UsbSerialService usb) async {
  if (!usb.transferArmed) {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arm Transfer Mode?'),
        content: const Text(
          'The device re-enumerates with its SD card as a USB drive. Streaming '
          'and the control port drop until Transfer Mode is disarmed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arm'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
  }
  final arm = !usb.transferArmed;
  await _report(context, usb.setTransferMode(arm),
      arm ? 'Transfer Mode armed' : 'Transfer Mode disarmed');
}

Future<void> _confirmEnterRecovery(BuildContext context) async {
  final fw = context.read<FirmwareUpdateService>();
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Enter recovery mode?'),
      content: const Text(
        'The device reboots into its bootloader. It stops streaming and stays '
        'there until an M7 image is written with Recover. Use this when a '
        'normal update cannot be installed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reboot into recovery'),
        ),
      ],
    ),
  );
  if (go == true) await fw.enterRecovery();
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
