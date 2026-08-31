import 'package:flutter/material.dart';

/// The eight destinations in the labelled rail, in rail order.
///
/// Connect is deliberately not a rail item — it is the Live destination's empty
/// state, so the app never feels like a different program when no board is
/// attached (design 2h).
enum StudioDestination {
  live,
  hrv,
  eeg,
  records,
  filters,
  link,
  device,
  settings;

  String get label => switch (this) {
        StudioDestination.live => 'Live',
        StudioDestination.hrv => 'HRV',
        StudioDestination.eeg => 'EEG',
        StudioDestination.records => 'Records',
        StudioDestination.filters => 'Filters',
        StudioDestination.link => 'Link',
        StudioDestination.device => 'Device',
        StudioDestination.settings => 'Settings',
      };

  /// The Saira caps title shown in the screen header.
  String get title => switch (this) {
        StudioDestination.live => 'Live signals',
        StudioDestination.hrv => 'HRV analysis',
        StudioDestination.eeg => 'EEG',
        StudioDestination.records => 'Recordings & export',
        StudioDestination.filters => 'Filters',
        StudioDestination.link => 'Link health',
        StudioDestination.device => 'Device',
        StudioDestination.settings => 'Settings',
      };

  IconData get icon => switch (this) {
        StudioDestination.live => Icons.monitor_heart_outlined,
        StudioDestination.hrv => Icons.ssid_chart,
        StudioDestination.eeg => Icons.psychology_outlined,
        StudioDestination.records => Icons.folder_open,
        StudioDestination.filters => Icons.graphic_eq,
        StudioDestination.link => Icons.network_check,
        StudioDestination.device => Icons.memory,
        StudioDestination.settings => Icons.tune,
      };

  IconData get activeIcon => switch (this) {
        StudioDestination.live => Icons.monitor_heart,
        StudioDestination.hrv => Icons.stacked_line_chart,
        StudioDestination.eeg => Icons.psychology,
        StudioDestination.records => Icons.folder,
        StudioDestination.filters => Icons.graphic_eq,
        StudioDestination.link => Icons.network_check,
        StudioDestination.device => Icons.memory,
        StudioDestination.settings => Icons.tune,
      };

  /// Destinations that only make sense with a device or a loaded recording. The
  /// rail dims these when nothing is attached rather than hiding them.
  bool get needsSource => switch (this) {
        StudioDestination.live => false,
        StudioDestination.settings => false,
        StudioDestination.device => false,
        _ => true,
      };

  /// Rail items above the spacer; [device] and [settings] sit below it.
  static const List<StudioDestination> primary = [
    StudioDestination.live,
    StudioDestination.hrv,
    StudioDestination.eeg,
    StudioDestination.records,
    StudioDestination.filters,
    StudioDestination.link,
  ];

  static const List<StudioDestination> secondary = [
    StudioDestination.device,
    StudioDestination.settings,
  ];
}

/// The tools reachable from the collapsed inspector dock on the Live screen.
enum InspectorTool {
  channels,
  filters,
  recording,
  export,
  firmware;

  IconData get icon => switch (this) {
        InspectorTool.channels => Icons.tune,
        InspectorTool.filters => Icons.graphic_eq,
        InspectorTool.recording => Icons.sd_card,
        InspectorTool.export => Icons.download,
        InspectorTool.firmware => Icons.system_update_alt,
      };

  String get label => switch (this) {
        InspectorTool.channels => 'Channels',
        InspectorTool.filters => 'Filters',
        InspectorTool.recording => 'Recording',
        InspectorTool.export => 'Export',
        InspectorTool.firmware => 'Firmware',
      };
}

/// Which screen the shell is showing, and the two display modes the Live screen
/// adds on top of it.
///
/// Focus mode is a display mode, not a separate shell: the chrome — top bar,
/// labelled rail, status line — never changes.
class StudioNavController extends ChangeNotifier {
  StudioDestination _destination = StudioDestination.live;
  bool _focusMode = false;
  bool _dockExpanded = false;
  bool _connectDismissed = false;
  InspectorTool _tool = InspectorTool.channels;

  StudioDestination get destination => _destination;
  bool get focusMode => _focusMode;

  /// True once the user has chosen to work against demo data instead of
  /// attaching a board. Reset when a transport appears or Connect is reopened.
  bool get connectDismissed => _connectDismissed;

  /// Show the Connect empty state again (from the app bar's device chip).
  void showConnect() {
    _connectDismissed = false;
    _focusMode = false;
    go(StudioDestination.live);
    notifyListeners();
  }

  /// "Keep running the built-in generator" — dismiss Connect for this session.
  void dismissConnect() {
    if (_connectDismissed) return;
    _connectDismissed = true;
    notifyListeners();
  }

  /// True when the 52px inspector dock has been expanded into a panel.
  bool get dockExpanded => _dockExpanded;
  InspectorTool get tool => _tool;

  void go(StudioDestination d) {
    if (_destination == d) return;
    _destination = d;
    // Focus mode only means anything on Live.
    if (d != StudioDestination.live) _focusMode = false;
    notifyListeners();
  }

  void setFocusMode(bool on) {
    if (_focusMode == on) return;
    _focusMode = on;
    notifyListeners();
  }

  void toggleFocusMode() => setFocusMode(!_focusMode);

  void setDockExpanded(bool expanded) {
    if (_dockExpanded == expanded) return;
    _dockExpanded = expanded;
    notifyListeners();
  }

  /// Selecting a tool expands the dock; selecting the open one collapses it.
  void selectTool(InspectorTool tool) {
    if (_dockExpanded && _tool == tool) {
      _dockExpanded = false;
    } else {
      _tool = tool;
      _dockExpanded = true;
    }
    notifyListeners();
  }

  /// Esc: leave Focus mode first, then close the dock.
  bool escape() {
    if (_focusMode) {
      _focusMode = false;
      notifyListeners();
      return true;
    }
    if (_dockExpanded) {
      _dockExpanded = false;
      notifyListeners();
      return true;
    }
    return false;
  }
}
