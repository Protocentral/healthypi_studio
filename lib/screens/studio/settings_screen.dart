import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../services/data_parser.dart';
import '../../services/live_data_pump.dart';
import '../../services/recording_file_service.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_settings.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_brand.dart';
import '../../widgets/hpi/hpi_primitives.dart';

enum _Category { appearance, acquisition, session, storage, shortcuts, about }

extension on _Category {
  String get label => switch (this) {
        _Category.appearance => 'Appearance',
        _Category.acquisition => 'Acquisition',
        _Category.session => 'Session',
        _Category.storage => 'Data & storage',
        _Category.shortcuts => 'Shortcuts',
        _Category.about => 'About',
      };

  IconData get icon => switch (this) {
        _Category.appearance => Icons.palette_outlined,
        _Category.acquisition => Icons.monitor_heart_outlined,
        _Category.session => Icons.badge_outlined,
        _Category.storage => Icons.save_outlined,
        _Category.shortcuts => Icons.keyboard_outlined,
        _Category.about => Icons.info_outline,
      };
}

/// Settings (design 2i).
///
/// Category rail plus one column of rows. Session metadata sits here as the
/// single place it is authored, and the shortcut list documents the transport
/// keys the console assumes.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  _Category _category = _Category.appearance;

  List<Widget> buildStatusItems(BuildContext context) {
    final p = context.hpi;
    final parser = context.watch<DataParser>();
    return [
      StatusItem('Preferences apply immediately',
          icon: Icons.check_circle, tone: p.success),
      const StatusItem('Studio 1.0.0'),
      StatusItem(parser.protocolVersionString),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      header: const ScreenHeader(
        title: 'Settings',
        subtitle: 'Studio 1.0.0 · preferences apply immediately '
            '(not persisted between launches yet)',
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 190, child: _CategoryRail(
            category: _category,
            onSelect: (c) => setState(() => _category = c),
          )),
          const SizedBox(width: HpiMetrics.columnGap),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (_category) {
                  _Category.appearance => const [_AppearanceCard()],
                  _Category.acquisition => const [_AcquisitionCard()],
                  _Category.session => const [_SessionCard()],
                  _Category.storage => const [_StorageCard()],
                  _Category.shortcuts => const [_ShortcutsCard()],
                  _Category.about => const [_AboutCard()],
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.category, required this.onSelect});

  final _Category category;
  final ValueChanged<_Category> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in _Category.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onSelect(c),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: category == c
                        ? p.brand.withValues(alpha: 0.1)
                        : null,
                    borderRadius: HpiRadius.buttonR,
                  ),
                  child: Row(
                    children: [
                      Icon(c.icon,
                          size: 18,
                          color: category == c ? p.brand : p.textMuted),
                      const SizedBox(width: 10),
                      Text(
                        c.label,
                        style: HpiText.uiTitle(p).copyWith(
                          color:
                              category == c ? p.textPrimary : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StudioSettings>();
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HpiLabel('Appearance'),
          const SizedBox(height: 6),
          HpiSettingRow(
            title: 'Theme',
            description: 'The same tokens on an inverted ramp — for bright '
                'benches and for screenshots in papers',
            control: HpiSegmented<ThemeMode>(
              height: 30,
              segments: const [
                HpiSegment(value: ThemeMode.dark, label: 'Dark'),
                HpiSegment(value: ThemeMode.light, label: 'Light'),
                HpiSegment(value: ThemeMode.system, label: 'System'),
              ],
              value: settings.themeMode,
              onChanged: (v) => settings.themeMode = v,
            ),
          ),
          HpiSettingRow(
            title: 'Grid density',
            description: 'Vertical time divisions behind every trace',
            control: HpiSegmented<GridDensityPref>(
              height: 30,
              segments: const [
                HpiSegment(value: GridDensityPref.fine, label: 'Fine'),
                HpiSegment(value: GridDensityPref.standard, label: 'Standard'),
                HpiSegment(value: GridDensityPref.off, label: 'Off'),
              ],
              value: settings.gridDensity,
              onChanged: (v) => settings.gridDensity = v,
            ),
          ),
          HpiSettingRow(
            title: 'Trace thickness',
            control: SizedBox(
              width: 170,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: settings.traceThickness,
                      min: 1,
                      max: 3,
                      divisions: 8,
                      onChanged: (v) => settings.traceThickness = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  HpiMono(settings.traceThickness.toStringAsFixed(1), size: 11),
                ],
              ),
            ),
          ),
          HpiSettingRow(
            last: true,
            title: 'Reduce motion',
            description: 'Stops the pulse animation on live indicators',
            control: HpiToggle(
              value: settings.reduceMotion,
              onChanged: (v) => settings.reduceMotion = v,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcquisitionCard extends StatelessWidget {
  const _AcquisitionCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StudioSettings>();
    final pump = context.watch<LiveDataPump>();
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HpiLabel('Acquisition defaults'),
          const SizedBox(height: 6),
          HpiSettingRow(
            title: 'Sweep speed',
            control: HpiSegmented<double>(
              height: 30,
              segments: const [
                HpiSegment(value: 12.5, label: '12.5'),
                HpiSegment(value: 25, label: '25'),
                HpiSegment(value: 50, label: '50'),
              ],
              trailingNote: 'mm/s',
              value: settings.sweepSpeedMmPerSec,
              onChanged: (v) => settings.sweepSpeedMmPerSec = v,
            ),
          ),
          HpiSettingRow(
            title: 'Window length',
            control: HpiSegmented<double>(
              height: 30,
              segments: const [
                HpiSegment(value: 5, label: '5s'),
                HpiSegment(value: 10, label: '10s'),
                HpiSegment(value: 30, label: '30s'),
                HpiSegment(value: 60, label: '60s'),
              ],
              value: settings.windowSeconds,
              onChanged: (v) {
                settings.windowSeconds = v;
                pump.controller.setTimeWindow(v);
              },
            ),
          ),
          HpiSettingRow(
            title: 'Auto-start streaming on connect',
            control: HpiToggle(
              value: settings.autoStartOnConnect,
              onChanged: (v) => settings.autoStartOnConnect = v,
            ),
          ),
          HpiSettingRow(
            title: 'Mains frequency',
            description: 'Drives every notch filter on every modality',
            control: HpiSegmented<MainsFrequency>(
              height: 30,
              segments: const [
                HpiSegment(value: MainsFrequency.fifty, label: '50 Hz'),
                HpiSegment(value: MainsFrequency.sixty, label: '60 Hz'),
              ],
              value: settings.mains,
              onChanged: (v) => settings.mains = v,
            ),
          ),
          HpiSettingRow(
            last: true,
            title: 'Units',
            control: HpiSegmented<bool>(
              height: 30,
              segments: const [
                HpiSegment(value: true, label: 'Metric'),
                HpiSegment(value: false, label: 'Imperial'),
              ],
              value: settings.metricUnits,
              onChanged: (v) => settings.metricUnits = v,
            ),
          ),
        ],
      ),
    );
  }
}

/// Session metadata — the single place it is authored, stamped into every file.
class _SessionCard extends StatefulWidget {
  const _SessionCard();

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  late final TextEditingController _session;
  late final TextEditingController _subject;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final s = context.read<StudioSession>();
    _session = TextEditingController(text: s.sessionId);
    _subject = TextEditingController(text: s.subject);
    _note = TextEditingController(text: s.protocolNote);
  }

  @override
  void dispose() {
    _session.dispose();
    _subject.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final session = context.read<StudioSession>();
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: HpiColumn(
        gap: 14,
        children: [
          const HpiLabel('Session metadata'),
          _Field(
            label: 'Session ID',
            controller: _session,
            hint: 'S-014',
            onChanged: (v) => session.sessionId = v,
          ),
          _Field(
            label: 'Subject',
            controller: _subject,
            hint: 'A12',
            highlight: true,
            onChanged: (v) => session.subject = v,
          ),
          _Field(
            label: 'Protocol note',
            controller: _note,
            hint: 'Resting baseline, 5 min supine',
            lines: 3,
            onChanged: (v) => session.protocolNote = v,
          ),
          HpiNote('Stamped into every recording and export header. Never leaves '
              'this machine.'),
          HpiNote(
            'Shown as the pill in the top bar so the current subject is visible '
            'from any screen.',
            color: p.textFaint,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.lines = 1,
    this.highlight = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final int lines;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HpiLabel(label, letterSpacing: 0.8),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: lines,
          style: lines > 1
              ? HpiText.body(p).copyWith(fontSize: 11.5)
              : HpiText.mono(p.textPrimary, size: 12),
          decoration: InputDecoration(
            hintText: hint,
            enabledBorder: highlight
                ? OutlineInputBorder(
                    borderRadius: HpiRadius.buttonR,
                    borderSide: BorderSide(color: p.accent),
                  )
                : null,
            fillColor: highlight ? p.accent.withValues(alpha: 0.06) : null,
          ),
        ),
      ],
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StudioSettings>();
    final files = context.watch<RecordingFileService>();
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HpiLabel('Data & storage'),
          const SizedBox(height: 6),
          HpiSettingRow(
            title: 'Recording folder',
            description: '~/Documents/HealthyPi_Recordings · '
                '${files.totalRecordings} files, '
                '${formatBytes(files.totalSizeBytes)}',
            control: HpiGhostButton(
              label: 'Rescan',
              height: 30,
              onPressed: files.loadRecordings,
            ),
          ),
          HpiSettingRow(
            title: 'File naming',
            control: HpiMono(settings.fileNamePattern, size: 11),
          ),
          HpiSettingRow(
            title: 'Auto-export after recording',
            control: HpiToggle(
              value: settings.autoExportAfterRecording,
              onChanged: (v) => settings.autoExportAfterRecording = v,
            ),
          ),
          HpiSettingRow(
            last: true,
            title: 'Keep raw signal in exports',
            description: 'Exports are always raw — baking the display filters '
                'into a file is not implemented',
            control: HpiToggle(value: true, onChanged: null),
          ),
        ],
      ),
    );
  }
}

class _ShortcutsCard extends StatelessWidget {
  const _ShortcutsCard();

  static const List<(String, String)> _keys = [
    ('Space', 'Freeze / resume'),
    ('R', 'Start / stop recording'),
    ('F', 'Focus mode'),
    ('M', 'Drop marker'),
    ('1 – 8', 'Jump to screen'),
    ('Esc', 'Exit focus / close dock'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: HpiColumn(
        gap: 10,
        children: [
          const HpiLabel('Shortcuts'),
          for (final k in _keys)
            Row(
              children: [
                HpiKeyCap(k.$1),
                const SizedBox(width: 10),
                Text(k.$2,
                    style: HpiText.body(p).copyWith(fontSize: 11.5, height: 1.2)),
              ],
            ),
          const HpiRule(margin: EdgeInsets.symmetric(vertical: 4)),
          HpiNote('The transport keys work anywhere in the app; the numbers jump '
              'straight to a rail destination.'),
        ],
      ),
    );
  }
}

/// The version comes off the built bundle, never a literal: a hand-typed string
/// here silently disagrees with `pubspec.yaml` the first time a release is cut,
/// and it is the number users quote in bug reports.
class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    }).catchError((Object e) {
      debugPrint('⚠️ Could not read package info: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final parser = context.watch<DataParser>();
    final nav = context.read<StudioNavController>();
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: HpiColumn(
        gap: 11,
        children: [
          const HpiLabel('About'),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(HpiBrandAssets.round, width: 48, height: 48),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HpiWordmark(height: 16),
                    const SizedBox(height: 6),
                    HpiMono(
                      _version == null ? 'Studio' : 'Studio $_version',
                      size: 11,
                      color: p.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const HpiRule(),
          HpiKeyValue('Stream protocol', parser.protocolVersionString),
          const HpiKeyValue('File format', '.hpd (BIOSIG v1)'),
          const HpiKeyValue('Firmware update', 'MCUmgr SMP'),
          const HpiKeyValue('Licence', 'MIT'),
          const HpiRule(),
          HpiNote('Research use only. Not a medical device and not for '
              'diagnosis.'),
          Row(
            children: [
              HpiGhostButton(
                label: 'Link health',
                icon: Icons.network_check,
                onPressed: () => nav.go(StudioDestination.link),
              ),
              const SizedBox(width: 8),
              HpiGhostButton(
                label: 'Device',
                icon: Icons.memory,
                onPressed: () => nav.go(StudioDestination.device),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
