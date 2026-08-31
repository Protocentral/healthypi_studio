import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/export_models.dart';
import '../../services/recording_export_service.dart';
import '../../services/recording_file_service.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_primitives.dart';
import '../../widgets/hpi/hpi_table.dart';

enum _ModalityFilter { all, ecg, eeg, ppg }

/// Recordings & export (design 2d).
///
/// One table, selection-driven. Export is the primary amber action here because
/// recording lives on the Live screen; the detail panel previews the file and
/// states plainly that exports stay raw.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => RecordingsScreenState();
}

class RecordingsScreenState extends State<RecordingsScreen> {
  final Set<String> _selected = {};
  final TextEditingController _search = TextEditingController();
  _ModalityFilter _filter = _ModalityFilter.all;
  bool _newestFirst = true;
  bool _includeMarkers = true;
  String? _lastExportPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RecordingFileService>().loadRecordings();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The amber action for this screen, hoisted into the top bar by the shell.
  Widget buildPrimaryAction(BuildContext context) {
    final exporting = context.watch<RecordingExportService>().isExporting;
    return HpiPrimaryButton(
      label: exporting
          ? 'Exporting…'
          : (_selected.isEmpty
              ? 'Export'
              : 'Export ${_selected.length} selected'),
      icon: Icons.download,
      filledIcon: false,
      onPressed: _selected.isEmpty || exporting ? null : _export,
    );
  }

  List<Widget> buildStatusItems(BuildContext context) {
    final p = context.hpi;
    final files = context.watch<RecordingFileService>();
    final exporter = context.watch<RecordingExportService>();
    return [
      StatusItem(
        files.error == null ? 'Storage OK' : files.error!,
        icon: files.error == null ? Icons.check_circle : Icons.error_outline,
        tone: files.error == null ? p.success : p.error,
      ),
      StatusItem('${files.totalRecordings} recordings · '
          '${formatBytes(files.totalSizeBytes)}'),
      StatusItem(exporter.isExporting
          ? '${exporter.currentOperation} '
              '${(exporter.exportProgress * 100).toStringAsFixed(0)}%'
          : 'idle'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final files = context.watch<RecordingFileService>();
    final rows = _visible(files.recordings);
    final selection =
        files.recordings.where((r) => _selected.contains(r.filePath)).toList();

    return ScreenBody(
      header: ScreenHeader(
        title: StudioDestination.records.title,
        subtitle: '${files.totalRecordings} recordings · '
            '${formatBytes(files.totalSizeBytes)} on disk'
            '${_selected.isEmpty ? "" : " · ${_selected.length} selected"}',
        action: HpiGhostButton(
          label: 'Reveal folder',
          icon: Icons.folder_open,
          onPressed: _revealFolder,
        ),
      ),
      child: ScreenColumns(
        sideWidth: 352,
        side: _DetailColumn(
          selection: selection,
          includeMarkers: _includeMarkers,
          lastExportPath: _lastExportPath,
          onIncludeMarkers: (v) => setState(() => _includeMarkers = v),
        ),
        main: HpiCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            children: [
              _Filters(
                search: _search,
                filter: _filter,
                newestFirst: _newestFirst,
                onFilter: (f) => setState(() => _filter = f),
                onSort: () => setState(() => _newestFirst = !_newestFirst),
                onSearch: () => setState(() {}),
              ),
              Expanded(child: _table(context, rows)),
            ],
          ),
        ),
      ),
    );
  }

  static const List<HpiColumnSpec> _columns = [
    HpiColumnSpec('File', flex: 1),
    HpiColumnSpec('Recorded', width: 130),
    HpiColumnSpec('Length', width: 66),
    HpiColumnSpec('Channels', width: 176),
    HpiColumnSpec('Size', width: 70, align: TextAlign.right),
  ];

  Widget _table(BuildContext context, List<RecordingFileInfo> rows) {
    final p = context.hpi;
    final files = context.watch<RecordingFileService>();
    if (files.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (files.recordings.isEmpty) {
      return ScreenEmptyState(
        icon: Icons.folder_off_outlined,
        title: 'No recordings yet',
        message: 'Recordings land in ~/Documents/HealthyPi_Recordings. Start one '
            'from the Live screen and it will appear here when you stop.',
        action: HpiGhostButton(
          label: 'Rescan folder',
          icon: Icons.refresh,
          onPressed: files.loadRecordings,
        ),
      );
    }
    if (rows.isEmpty) {
      return const ScreenEmptyState(
        icon: Icons.search_off,
        title: 'Nothing matches',
        message: 'No recording matches the current search and modality filter.',
      );
    }

    final allSelected = rows.every((r) => _selected.contains(r.filePath));
    return HpiTable(
      columns: _columns,
      trailingWidth: 24,
      leading: HpiCheckbox(
        value: allSelected,
        onChanged: (v) => setState(() {
          if (v) {
            _selected.addAll(rows.map((r) => r.filePath));
          } else {
            _selected.removeAll(rows.map((r) => r.filePath));
          }
        }),
      ),
      rows: [
        for (var i = 0; i < rows.length; i++)
          HpiTableRow(
            columns: _columns,
            selected: _selected.contains(rows[i].filePath),
            marker: _selected.contains(rows[i].filePath) &&
                (i == 0 || !_selected.contains(rows[i - 1].filePath)),
            last: i == rows.length - 1,
            onTap: () => setState(() => _toggle(rows[i].filePath)),
            leading: HpiCheckbox(
              value: _selected.contains(rows[i].filePath),
              onChanged: (_) => setState(() => _toggle(rows[i].filePath)),
            ),
            trailing: Tooltip(
              message: 'Delete recording',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _confirmDelete(rows[i]),
                  child: SizedBox(
                    width: 24,
                    child: Icon(Icons.delete_outline,
                        size: 18, color: p.textFaint),
                  ),
                ),
              ),
            ),
            cells: [
              HpiCell(rows[i].fileName, size: 12, color: p.textPrimary),
              HpiCell(_stamp(rows[i].createdAt), color: p.textMuted),
              HpiCell(rows[i].durationFormatted, color: p.textSecondary),
              HpiCell(
                rows[i].channels.isEmpty
                    ? 'metadata unavailable'
                    : rows[i].channels.join(', '),
                mono: false,
              ),
              HpiCell(rows[i].fileSizeFormatted,
                  align: TextAlign.right, color: p.textSecondary),
            ],
          ),
      ],
    );
  }

  void _toggle(String path) {
    if (!_selected.remove(path)) _selected.add(path);
  }

  List<RecordingFileInfo> _visible(List<RecordingFileInfo> all) {
    final query = _search.text.trim().toLowerCase();
    var rows = all.where((r) {
      if (query.isNotEmpty && !r.fileName.toLowerCase().contains(query)) {
        return false;
      }
      if (_filter == _ModalityFilter.all) return true;
      final needle = switch (_filter) {
        _ModalityFilter.ecg => 'ecg',
        _ModalityFilter.eeg => 'eeg',
        _ModalityFilter.ppg => 'ppg',
        _ModalityFilter.all => '',
      };
      return r.channels.any((c) => c.toLowerCase().contains(needle));
    }).toList();
    rows.sort((a, b) => _newestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));
    return rows;
  }

  Future<void> _export() async {
    final exporter = context.read<RecordingExportService>();
    final files = context.read<RecordingFileService>();
    final targets =
        files.recordings.where((r) => _selected.contains(r.filePath)).toList();

    for (final target in targets) {
      final base = target.fileName.replaceAll(RegExp(r'\.hpd$'), '');
      final path = await exporter.exportToCSV(
        inputFilePath: target.filePath,
        outputFileName: '$base.csv',
        options: CSVExportOptions(
          includeMetadata: true,
          includeTimestamps: true,
          includeMarkers: _includeMarkers,
        ),
      );
      if (!mounted) return;
      if (path == null) {
        _toast(exporter.error ?? 'Export failed');
        return;
      }
      setState(() => _lastExportPath = path);
    }
    if (!mounted) return;
    _toast('Exported ${targets.length} '
        '${targets.length == 1 ? "recording" : "recordings"} to CSV');
  }

  Future<void> _confirmDelete(RecordingFileInfo file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text('${file.fileName} will be removed from disk. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<RecordingFileService>().deleteRecording(file.filePath);
    if (!mounted) return;
    setState(() => _selected.remove(file.filePath));
  }

  Future<void> _revealFolder() async {
    final dir = await context.read<RecordingFileService>().getRecordingsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir.path]);
    } else if (mounted) {
      _toast(dir.path);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _stamp(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$d ${months[t.month - 1]} ${t.year} · $hh:$mm';
  }
}

/// Search, modality filter, sort — the table's own header strip.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.search,
    required this.filter,
    required this.newestFirst,
    required this.onFilter,
    required this.onSort,
    required this.onSearch,
  });

  final TextEditingController search;
  final _ModalityFilter filter;
  final bool newestFirst;
  final ValueChanged<_ModalityFilter> onFilter;
  final VoidCallback onSort;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.outlineSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 246,
            height: 30,
            child: TextField(
              controller: search,
              onChanged: (_) => onSearch(),
              style: HpiText.body(p).copyWith(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search file, subject, session…',
                prefixIcon: Icon(Icons.search, size: 16, color: p.textFaint),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 32, minHeight: 30),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          const SizedBox(width: 10),
          for (final f in _ModalityFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: HpiToolButton(
                label: f.name.toUpperCase(),
                active: filter == f,
                onPressed: () => onFilter(f),
              ),
            ),
          const Spacer(),
          const HpiLabel('Sort'),
          const SizedBox(width: 8),
          HpiToolButton(
            icon: newestFirst ? Icons.arrow_downward : Icons.arrow_upward,
            label: newestFirst ? 'Newest' : 'Oldest',
            onPressed: onSort,
          ),
        ],
      ),
    );
  }
}

/// The detail column: file facts, the export contract, and the last export.
class _DetailColumn extends StatelessWidget {
  const _DetailColumn({
    required this.selection,
    required this.includeMarkers,
    required this.lastExportPath,
    required this.onIncludeMarkers,
  });

  final List<RecordingFileInfo> selection;
  final bool includeMarkers;
  final String? lastExportPath;
  final ValueChanged<bool> onIncludeMarkers;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final exporter = context.watch<RecordingExportService>();
    final one = selection.length == 1 ? selection.first : null;
    final totalBytes =
        selection.fold<int>(0, (sum, r) => sum + r.fileSize);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HpiCard(
          child: HpiColumn(
            gap: 11,
            children: [
              Row(
                children: [
                  Icon(Icons.description, size: 18, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HpiMono(
                      one?.fileName ??
                          (selection.isEmpty
                              ? 'No file selected'
                              : '${selection.length} files selected'),
                      size: 12,
                      color: p.textPrimary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (one != null) ...[
                HpiKeyValue('Duration', one.durationFormatted),
                HpiKeyValue('Samples', '${one.totalSamples ?? "—"}'),
                HpiKeyValue('Channels',
                    one.channels.isEmpty ? '—' : '${one.channels.length}'),
                HpiKeyValue('Size', one.fileSizeFormatted),
                HpiKeyValue(
                  'Subject',
                  one.metadata?.subjectMetadata?.subjectId ?? '—',
                ),
                HpiKeyValue(
                  'Protocol',
                  one.metadata?.sessionMetadata?.protocolName ?? '—',
                ),
              ] else if (selection.isNotEmpty)
                HpiKeyValue('Total size', formatBytes(totalBytes))
              else
                HpiNote('Pick one or more recordings in the table to see their '
                    'details and export them.'),
            ],
          ),
        ),
        kCardGap,
        HpiCard(
          child: HpiColumn(
            gap: 12,
            children: [
              const HpiLabel('Export'),
              // CSV is the only format Studio writes, so this states the
              // format rather than offering a choice of one.
              const HpiOptionRow(
                title: 'CSV',
                subtitle: 'One row per sample · widest tool support',
                selected: true,
                icon: Icons.table_chart,
              ),
              Row(
                children: [
                  Expanded(
                    child: HpiBody(
                        'Apply display filters — not yet available'),
                  ),
                  HpiToggle(value: false, onChanged: null),
                ],
              ),
              Row(
                children: [
                  Expanded(child: HpiBody('Include markers & events')),
                  HpiToggle(value: includeMarkers, onChanged: onIncludeMarkers),
                ],
              ),
              if (exporter.isExporting) ...[
                HpiMeter(
                  fraction: exporter.exportProgress,
                  color: p.accent,
                  height: 6,
                ),
                HpiMono(exporter.currentOperation,
                    size: 10.5, color: p.textFaint),
              ],
              HpiNote('Exports carry the raw recorded signal. Baking the '
                  'on-screen filter chain into a file is not implemented, so '
                  'that switch is disabled rather than silently ignored.'),
              if (selection.isNotEmpty)
                HpiNote('Estimated output ${selection.length} '
                    '${selection.length == 1 ? "file" : "files"}'
                    ' · source ${formatBytes(totalBytes)}'),
            ],
          ),
        ),
        kCardGap,
        Expanded(
          child: HpiCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: HpiColumn(
              gap: 9,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HpiLabel('Recent export'),
                if (lastExportPath == null)
                  HpiNote('Nothing exported in this session yet.')
                else ...[
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: p.success),
                      const SizedBox(width: 9),
                      Expanded(
                        child: HpiMono(
                          lastExportPath!.split(Platform.pathSeparator).last,
                          size: 11,
                          color: p.textSecondary,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  HpiMono(lastExportPath!, size: 10.5, color: p.textFaint),
                ],
                if (exporter.error != null)
                  HpiNote(exporter.error!, color: p.error),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
