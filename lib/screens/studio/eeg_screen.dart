import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/eeg_band_power_service.dart';
import '../../services/eeg_packet_service.dart';
import '../../services/live_data_pump.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_settings.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_plots.dart';
import '../../widgets/hpi/hpi_primitives.dart';
import '../../widgets/hpi/hpi_wave.dart';

/// EEG (design 2c).
///
/// The violet channel family, per-channel gutters carrying gain, and band power
/// and spectrum as peer cards below the traces. Electrode contact is a
/// first-class panel because it is the thing that actually blocks a session.
class EegScreen extends StatefulWidget {
  const EegScreen({super.key});

  @override
  State<EegScreen> createState() => _EegScreenState();
}

class _EegScreenState extends State<EegScreen> {
  final EegBandPowerService _bandPower = EegBandPowerService();
  double _windowSeconds = 4;
  bool _notch = true;
  bool _artifactReject = false;
  bool _showArtifacts = true;
  bool _autoScale = true;

  static const List<String> _channelIds = ['eeg1', 'eeg2'];
  static const List<String> _channelNames = ['Fp1', 'Fp2'];

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final eeg = context.watch<EEGPacketService>();
    final pump = context.watch<LiveDataPump>();
    final live = eeg.latestData != null;

    return ScreenBody(
      header: ScreenHeader(
        title: StudioDestination.eeg.title,
        badge: live
            ? HpiBadge('Live', tone: p.success)
            : HpiBadge(pump.isSimulated ? 'Simulated' : 'No data',
                tone: pump.isSimulated ? p.brand : p.textMuted),
        subtitle: '2 channels · Fp1 / Fp2 · '
            '${LiveDataPump.eegSampleRate.toStringAsFixed(0)} Hz · '
            'filtering on the Filters screen',
        action: HpiGhostButton(
          label: 'Impedance check',
          icon: Icons.bolt,
          // The current firmware does not expose an impedance command; the
          // button stays visible but honest about it.
          onPressed: null,
        ),
      ),
      child: ScreenColumns(
        sideWidth: 296,
        side: _SidePanel(
          eeg: eeg,
          showArtifacts: _showArtifacts,
          autoScale: _autoScale,
          onShowArtifacts: (v) => setState(() => _showArtifacts = v),
          onAutoScale: (v) => setState(() => _autoScale = v),
        ),
        main: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _TraceCard(window: _windowSeconds, notch: _notch, artifactReject: _artifactReject, onWindow: (v) => setState(() => _windowSeconds = v), onNotch: (v) => setState(() => _notch = v), onArtifactReject: (v) => setState(() => _artifactReject = v), channelIds: _channelIds, channelNames: _channelNames)),
            kCardGap,
            SizedBox(
              height: 208,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _BandPowerCard(service: _bandPower)),
                  kCardGapH,
                  SizedBox(width: 480, child: _SpectrumCard(service: _bandPower)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The two traces in one card, with the modality's own control strip at its foot.
class _TraceCard extends StatelessWidget {
  const _TraceCard({
    required this.window,
    required this.notch,
    required this.artifactReject,
    required this.onWindow,
    required this.onNotch,
    required this.onArtifactReject,
    required this.channelIds,
    required this.channelNames,
  });

  final double window;
  final bool notch;
  final bool artifactReject;
  final ValueChanged<double> onWindow;
  final ValueChanged<bool> onNotch;
  final ValueChanged<bool> onArtifactReject;
  final List<String> channelIds;
  final List<String> channelNames;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final pump = context.watch<LiveDataPump>();
    final eeg = context.watch<EEGPacketService>();
    final settings = context.watch<StudioSettings>();

    return HpiCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: ListenableBuilder(
        listenable: pump.controller,
        builder: (context, _) {
          final channels = pump.controller.channels;
          return Column(
            children: [
              for (var i = 0; i < channelIds.length; i++)
                Expanded(
                  child: _EegRow(
                    name: channelNames[i],
                    channelId: channelIds[i],
                    data: channels[channelIds[i]],
                    color: i == 0 ? p.trace.eeg1 : p.trace.eeg2,
                    window: window,
                    gridDivisions: settings.gridDivisions,
                    leadOff: eeg.latestData == null
                        ? null
                        : !eeg.isChannelConnected(i),
                    last: i == channelIds.length - 1,
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                color: p.well,
                child: Row(
                  children: [
                    HpiToolButton(
                      icon: pump.controller.settings.isPaused
                          ? Icons.play_arrow
                          : Icons.pause,
                      label: pump.controller.settings.isPaused
                          ? 'Resume'
                          : 'Freeze',
                      active: pump.controller.settings.isPaused,
                      onPressed: pump.controller.togglePause,
                    ),
                    const SizedBox(width: 10),
                    // The EEG filter chain lives on the Filters screen, which
                    // actually applies it. A second notch switch here only ever
                    // set a flag no painter read.
                    HpiToolButton(
                      icon: Icons.filter_alt,
                      label: 'Filters',
                      onPressed: () =>
                          context.read<StudioNavController>()
                              .go(StudioDestination.filters),
                    ),
                    const SizedBox(width: 10),
                    HpiToolButton(
                      icon: Icons.auto_fix_high,
                      label: 'Artifact reject — not available',
                      onPressed: null,
                    ),
                    const Spacer(),
                    const HpiLabel('Window'),
                    const SizedBox(width: 8),
                    HpiSegmented<double>(
                      segments: const [
                        HpiSegment(value: 2, label: '2s'),
                        HpiSegment(value: 4, label: '4s'),
                        HpiSegment(value: 10, label: '10s'),
                      ],
                      value: window,
                      onChanged: onWindow,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EegRow extends StatelessWidget {
  const _EegRow({
    required this.name,
    required this.channelId,
    required this.data,
    required this.color,
    required this.window,
    required this.gridDivisions,
    required this.last,
    this.leadOff,
  });

  final String name;
  final String channelId;
  final dynamic data;
  final Color color;
  final double window;
  final int gridDivisions;
  final bool last;
  final bool? leadOff;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    if (data == null) {
      return const Center(child: HpiNote('Channel not configured'));
    }
    return DecoratedBox(
      decoration: last
          ? const BoxDecoration()
          : BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: HpiMetrics.channelGutterWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: p.well,
              border: Border(right: BorderSide(color: p.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: HpiFonts.ui,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.55,
                    color: color,
                  ),
                ),
                const Spacer(),
                if (leadOff != null)
                  Row(
                    children: [
                      HpiStatusDot(
                          color: leadOff! ? p.error : p.success, size: 6),
                      const SizedBox(width: 5),
                      HpiLabel(leadOff! ? 'Lead off' : 'Contact',
                          letterSpacing: 0.6),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: HpiWaveTrace(
              data: data,
              windowSeconds: window,
              color: color,
              strokeWidth: 1.4,
              gridDivisions: gridDivisions,
            ),
          ),
        ],
      ),
    );
  }
}

/// Band power over the visible buffer, computed with the app's own FFT service.
class _BandPowerCard extends StatelessWidget {
  const _BandPowerCard({required this.service});

  final EegBandPowerService service;

  @override
  Widget build(BuildContext context) {
    final pump = context.watch<LiveDataPump>();
    final samples = _channelSamples(pump, 'eeg1', 256);
    final powers = samples.length < 32
        ? null
        : service.computeBandPowers(samples, fftSize: 256, channelIndex: 0);

    final bands = <(String, String, double, Color)>[
      ('Delta', '0.5–4 Hz', powers?.relativeDelta ?? 0, const Color(0xFF8B84F0)),
      ('Theta', '4–8 Hz', powers?.relativeTheta ?? 0, const Color(0xFF9B8DF4)),
      ('Alpha', '8–13 Hz', powers?.relativeAlpha ?? 0, const Color(0xFFA78BFA)),
      ('Beta', '13–30 Hz', powers?.relativeBeta ?? 0, const Color(0xFFB69CFB)),
      ('Gamma', '30–45 Hz', powers?.relativeGamma ?? 0, const Color(0xFFC4B0FC)),
    ];

    return HpiCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HpiSectionTitle('Band power', note: 'Fp1 · relative'),
          const SizedBox(height: 14),
          if (powers == null)
            Expanded(child: Center(child: HpiNote('Filling the FFT window…')))
          else
            for (final b in bands)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: HpiMeterRow(
                  name: b.$1,
                  note: b.$2,
                  fraction: b.$3,
                  color: b.$4,
                  value: '${(b.$3 * 100).toStringAsFixed(0)}%',
                ),
              ),
        ],
      ),
    );
  }
}

/// The power spectrum, with the dominant peak called out.
class _SpectrumCard extends StatelessWidget {
  const _SpectrumCard({required this.service});

  final EegBandPowerService service;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final pump = context.watch<LiveDataPump>();
    final samples = _channelSamples(pump, 'eeg1', 256);
    final spectrum = samples.length < 32
        ? const <MapEntry<double, double>>[]
        : service.getFullPowerSpectrum(samples, fftSize: 256);
    final usable = spectrum.where((e) => e.key <= 45).toList();
    final peak = usable.isEmpty
        ? null
        : usable.reduce((a, b) => a.value >= b.value ? a : b);

    return HpiCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HpiSectionTitle(
            'Spectrum',
            note: 'FFT 256 · Hann',
            trailing: peak == null
                ? null
                : HpiMono('peak ${peak.key.toStringAsFixed(1)} Hz',
                    size: 10, color: p.trace.eeg1),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: usable.isEmpty
                ? HpiWell(child: Center(child: HpiNote('Filling the FFT window…')))
                : HpiPlotWell(
                    gridDivisions: 5,
                    footer: const ['0', '10', '20', '30', '45 Hz'],
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: HpiLinePlot(
                        values: usable.map((e) => e.value).toList(),
                        color: p.trace.eeg2,
                        minValue: 0,
                        strokeWidth: 1.6,
                        fill: true,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Electrode contact, channel setup, and the marker list.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.eeg,
    required this.showArtifacts,
    required this.autoScale,
    required this.onShowArtifacts,
    required this.onAutoScale,
  });

  final EEGPacketService eeg;
  final bool showArtifacts;
  final bool autoScale;
  final ValueChanged<bool> onShowArtifacts;
  final ValueChanged<bool> onAutoScale;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final data = eeg.latestData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HpiCard(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: HpiColumn(
            gap: 11,
            children: [
              const HpiLabel('Electrode contact'),
              // The EEG packet reports lead-off per electrode as a bitmask, not
              // an impedance in ohms — so this panel reports contact, not kΩ.
              for (var i = 0; i < 2; i++)
                _ContactRow(
                  name: i == 0 ? 'Fp1' : 'Fp2',
                  state: data == null
                      ? null
                      : eeg.isChannelConnected(i),
                ),
              _ContactRow(
                name: 'Reference',
                state: data == null
                    ? null
                    : (data.leadOffNegative & 0x01) == 0,
              ),
              HpiNote(data == null
                  ? 'Connect a board to read electrode contact. The device '
                      'reports lead-off per electrode; impedance in kΩ is not '
                      'part of the EEG packet.'
                  : 'Re-gel any electrode reporting lead-off before trusting '
                      'the band powers.'),
            ],
          ),
        ),
        kCardGap,
        HpiCard(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: HpiColumn(
            gap: 12,
            children: [
              const HpiLabel('Channel setup'),
              HpiKeyValue('Sample rate',
                  '${LiveDataPump.eegSampleRate.toStringAsFixed(0)} Hz'),
              HpiKeyValue('Packets received', '${eeg.packetsReceived}'),
              HpiNote(
                'Reference electrode, PGA gain and the front-end filter '
                'corners are not reported by the device, so they are not '
                'listed. The display filter chain is on the Filters screen.',
              ),
              const HpiRule(),
              Row(
                children: [
                  Expanded(child: HpiBody('Show artifacts — not available')),
                  HpiToggle(value: false, onChanged: null),
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child: HpiBody('Auto-scale channels — not available')),
                  HpiToggle(value: false, onChanged: null),
                ],
              ),
            ],
          ),
        ),
        kCardGap,
        Expanded(
          child: HpiCard(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            child: HpiColumn(
              gap: 10,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HpiLabel('Signal quality'),
                HpiKeyValue(
                  'Reported quality',
                  eeg.signalQuality == null ? '—' : '${eeg.signalQuality}%',
                ),
                HpiKeyValue('Packets', '${eeg.packetsReceived}'),
                HpiKeyValue(
                  'Channels connected',
                  data == null ? '—' : '${eeg.connectedChannelCount} / 8',
                ),
                HpiKeyValue('Window', formatEegWindow(eeg.historyDuration)),
                const HpiRule(),
                HpiNote(
                  'Markers are written into the running recording — drop them '
                  'from the Live screen with M.',
                  color: p.textFaint,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.name, required this.state});

  final String name;

  /// `true` connected, `false` lead-off, `null` unknown (no device).
  final bool? state;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final (Color tone, String text) = switch (state) {
      true => (p.success, 'contact'),
      false => (p.error, 'lead off'),
      null => (p.textFaint, 'unknown'),
    };
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            name,
            style: HpiText.control(p)
                .copyWith(color: p.textPrimary, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: HpiMeter(
            fraction: state == true ? 1 : (state == false ? 0.12 : 0),
            color: tone,
            height: 6,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 58,
          child: HpiMono(text, size: 10.5, color: tone, align: TextAlign.right),
        ),
      ],
    );
  }
}

/// The most recent EEG samples for a channel, as a plain list for the FFT.
List<double> _channelSamples(LiveDataPump pump, String channelId, int count) {
  final data = pump.controller.channels[channelId];
  if (data == null) return const [];
  final available = data.isBufferFull ? data.maxBufferSize : data.writeIndex;
  if (available == 0) return const [];
  final take = available < count ? available : count;
  final out = List<double>.filled(take, 0);
  final start = data.writeIndex - take;
  for (var i = 0; i < take; i++) {
    final idx = (start + i + data.maxBufferSize * 2) % data.maxBufferSize;
    out[i] = data.buffer[idx].value;
  }
  return out;
}

String formatEegWindow(Duration d) {
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
