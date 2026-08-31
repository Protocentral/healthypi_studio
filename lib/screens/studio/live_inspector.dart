import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/recording_models.dart';
import '../../services/live_data_pump.dart';
import '../../services/recording_engine.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_primitives.dart';

/// The inspector dock: a 52px strip of tool icons that expands into a panel only
/// when asked, so the canvas keeps its width by default.
class LiveInspectorDock extends StatelessWidget {
  const LiveInspectorDock({super.key});

  static const double panelWidth = 300;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.watch<StudioNavController>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nav.dockExpanded)
          Container(
            width: panelWidth,
            decoration: BoxDecoration(
              color: p.chrome,
              border: Border(left: BorderSide(color: p.outlineSoft)),
            ),
            child: _Panel(tool: nav.tool),
          ),
        Container(
          width: HpiMetrics.inspectorDockWidth,
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          decoration: BoxDecoration(
            color: p.chrome,
            border: Border(left: BorderSide(color: p.outlineSoft)),
          ),
          child: Column(
            children: [
              for (final tool in InspectorTool.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _DockButton(
                    tool: tool,
                    active: nav.dockExpanded && nav.tool == tool,
                    onTap: () => nav.selectTool(tool),
                  ),
                ),
              const Spacer(),
              _IconSlot(
                icon: nav.dockExpanded
                    ? Icons.keyboard_double_arrow_right
                    : Icons.keyboard_double_arrow_left,
                tooltip: nav.dockExpanded ? 'Collapse inspector' : 'Expand inspector',
                onTap: () => nav.setDockExpanded(!nav.dockExpanded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.tool,
    required this.active,
    required this.onTap,
  });

  final InspectorTool tool;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _IconSlot(
      icon: tool.icon,
      tooltip: tool.label,
      active: active,
      onTap: onTap,
    );
  }
}

class _IconSlot extends StatelessWidget {
  const _IconSlot({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? p.brand.withValues(alpha: 0.16) : null,
              borderRadius: HpiRadius.buttonR,
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? p.brandInk : p.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.tool});

  final InspectorTool tool;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.outlineSoft)),
          ),
          child: Row(
            children: [
              Expanded(child: HpiSectionTitle(tool.label)),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => nav.setDockExpanded(false),
                  child: Icon(Icons.close, size: 16, color: p.textMuted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: switch (tool) {
              InspectorTool.channels => const _ChannelsPanel(),
              InspectorTool.filters => const _FiltersShortcut(),
              InspectorTool.recording => const _RecordingPanel(),
              InspectorTool.export => const _ExportShortcut(),
              InspectorTool.firmware => const _FirmwareShortcut(),
            },
          ),
        ),
      ],
    );
  }
}

/// Channel visibility and per-channel scaling — what the old 320px panel did,
/// now on demand.
class _ChannelsPanel extends StatelessWidget {
  const _ChannelsPanel();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final pump = context.watch<LiveDataPump>();
    final controller = pump.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = controller.channels.entries.toList();
        return HpiColumn(
          gap: 10,
          children: [
            for (final e in entries)
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 3,
                    color: p.trace.forChannel(e.key),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.value.config.label,
                      style: HpiText.body(p).copyWith(
                        fontSize: 12,
                        height: 1.2,
                        color: e.value.config.isVisible
                            ? p.textPrimary
                            : p.textFaint,
                      ),
                    ),
                  ),
                  HpiMono(
                    '${e.value.samplingRate.toStringAsFixed(0)} Hz',
                    size: 10,
                    color: p.textFaint,
                  ),
                  const SizedBox(width: 10),
                  HpiToggle(
                    value: e.value.config.isVisible,
                    onChanged: (_) => controller.toggleChannelVisibility(e.key),
                  ),
                ],
              ),
            const HpiRule(margin: EdgeInsets.symmetric(vertical: 4)),
            Row(
              children: [
                Expanded(
                  child: HpiGhostButton(
                    label: 'Auto-scale all',
                    icon: Icons.fit_screen,
                    expand: true,
                    onPressed: controller.autoScaleAll,
                  ),
                ),
              ],
            ),
            HpiNote('Hiding a channel stops it being drawn; it keeps streaming '
                'and keeps being recorded.'),
          ],
        );
      },
    );
  }
}

/// Recording transport, with the destination and the pre-buffer stated up front.
class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final engine = context.watch<RecordingEngine>();
    final pump = context.watch<LiveDataPump>();
    final recording = engine.state == RecordingState.recording;
    final paused = engine.state == RecordingState.paused;

    return HpiColumn(
      gap: 12,
      children: [
        Row(
          children: [
            HpiStatusDot(
              color: recording ? p.error : p.textFaint,
              size: 8,
              pulse: recording,
              period: const Duration(milliseconds: 900),
            ),
            const SizedBox(width: 8),
            Text(
              switch (engine.state) {
                RecordingState.recording => 'Recording',
                RecordingState.paused => 'Paused',
                RecordingState.stopped => 'Stopped',
                RecordingState.error => 'Error',
                RecordingState.idle => 'Idle',
              },
              style: HpiText.uiTitle(p),
            ),
            const Spacer(),
            HpiMono(formatDuration(engine.elapsedTime),
                size: 12, color: p.textSecondary),
          ],
        ),
        HpiKeyValue('Samples written', '${engine.samplesRecorded}'),
        HpiKeyValue('File size', formatBytes(engine.fileSizeBytes)),
        HpiKeyValue('HRV packets', '${engine.hrvPacketsRecorded}'),
        HpiKeyValue(
          'Channels armed',
          '${pump.controller.visibleChannels.length}',
        ),
        const HpiRule(),
        if (recording || paused)
          Row(
            children: [
              Expanded(
                child: HpiGhostButton(
                  label: paused ? 'Resume' : 'Pause',
                  icon: paused ? Icons.play_arrow : Icons.pause,
                  expand: true,
                  onPressed: () => paused
                      ? engine.resumeRecording()
                      : engine.pauseRecording(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HpiGhostButton(
                  label: 'Stop',
                  icon: Icons.stop,
                  tone: p.error,
                  expand: true,
                  onPressed: pump.controller.stopRecording,
                ),
              ),
            ],
          )
        else
          HpiNote('Use “Start recording” in the top bar. The pre-buffer means '
              'the seconds before you press it are saved too.'),
      ],
    );
  }
}

class _FiltersShortcut extends StatelessWidget {
  const _FiltersShortcut();

  @override
  Widget build(BuildContext context) => const _Shortcut(
        destination: StudioDestination.filters,
        icon: Icons.graphic_eq,
        message: 'Filtering is applied to the on-screen trace only. The full '
            'chain per modality, with a before/after preview, lives on the '
            'Filters screen.',
        label: 'Open Filters',
      );
}

class _ExportShortcut extends StatelessWidget {
  const _ExportShortcut();

  @override
  Widget build(BuildContext context) => const _Shortcut(
        destination: StudioDestination.records,
        icon: Icons.download,
        message: 'Recordings and export share one screen: pick files in the '
            'table, choose a format, export.',
        label: 'Open Recordings & export',
      );
}

class _FirmwareShortcut extends StatelessWidget {
  const _FirmwareShortcut();

  @override
  Widget build(BuildContext context) => const _Shortcut(
        destination: StudioDestination.device,
        icon: Icons.system_update_alt,
        message: 'Firmware update is a card on the Device screen. Streaming '
            'pauses for the transfer and resumes on reboot.',
        label: 'Open Device',
      );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.destination,
    required this.icon,
    required this.message,
    required this.label,
  });

  final StudioDestination destination;
  final IconData icon;
  final String message;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    return HpiColumn(
      gap: 14,
      children: [
        Icon(icon, size: 22, color: p.brand),
        HpiBody(message),
        HpiGhostButton(
          label: label,
          icon: Icons.arrow_forward,
          expand: true,
          onPressed: () => nav.go(destination),
        ),
      ],
    );
  }
}
