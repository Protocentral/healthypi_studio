import 'dart:io';

/// Runs a process and returns its exit code and output. Swapped for a fake in
/// tests.
typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

Future<ProcessResult> _runProcess(String exe, List<String> args) =>
    Process.run(exe, args);

/// Finds `picotool`, which loads a UF2 into an RP2350 in its ROM bootloader
/// over PICOBOOT (USB 2E8A:000F).
///
/// Studio loads through picotool rather than by copying the UF2 to the
/// BOOTSEL drive, because that drive sometimes fails to mount on macOS (Core
/// bench notes, 2026-11-07). Lookup order: the path the user set, a copy
/// bundled with Studio, then `PATH`, then the usual install locations.
class PicotoolLocator {
  PicotoolLocator({
    this.override,
    Map<String, String>? environment,
    String? resolvedExecutable,
    bool Function(String path)? exists,
    bool? isWindows,
  })  : _env = environment ?? Platform.environment,
        _exe = resolvedExecutable ?? Platform.resolvedExecutable,
        _exists = exists ?? ((p) => File(p).existsSync()),
        _windows = isWindows ?? Platform.isWindows;

  /// The path the user chose, if any. Tried first, and only that path: a
  /// wrong choice is reported rather than silently replaced.
  final String? override;
  final Map<String, String> _env;
  final String _exe;
  final bool Function(String path) _exists;
  final bool _windows;

  String get _name => _windows ? 'picotool.exe' : 'picotool';

  /// Where a copy shipped with Studio would sit: next to the executable, or in
  /// the macOS bundle's Resources.
  List<String> get bundledCandidates {
    final sep = _windows ? '\\' : '/';
    final dir = _exe.substring(0, _exe.lastIndexOf(sep).clamp(0, _exe.length));
    return [
      '$dir$sep$_name',
      '$dir${sep}picotool$sep$_name',
      if (!_windows) '$dir/../Resources/$_name',
    ];
  }

  /// The executable to run, or null when there is none.
  String? locate() {
    final o = override;
    if (o != null && o.isNotEmpty) return _exists(o) ? o : null;
    for (final c in bundledCandidates) {
      if (_exists(c)) return c;
    }
    final path = _env['PATH'] ?? _env['Path'] ?? '';
    for (final dir in path.split(_windows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final c = '$dir${_windows ? '\\' : '/'}$_name';
      if (_exists(c)) return c;
    }
    // A GUI app on macOS does not inherit the shell's PATH.
    if (!_windows) {
      for (final dir in const ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin']) {
        final c = '$dir/$_name';
        if (_exists(c)) return c;
      }
    }
    return null;
  }

  /// What to tell the user when [locate] finds nothing.
  String get missingMessage => override != null && override!.isNotEmpty
      ? 'picotool was not found at $override. Choose the picotool executable '
          'again, or clear the choice to search PATH.'
      : 'picotool was not found. Install it (the Raspberry Pi Pico SDK tools, '
          'or `brew install picotool`), or choose its executable on the Device '
          'screen. Studio needs it to load a UF2 over USB.';
}

/// The two picotool calls the Core update makes.
class Picotool {
  Picotool(this.executable, {ProcessRunner? run}) : _run = run ?? _runProcess;

  final String executable;
  final ProcessRunner _run;

  /// Whether a board in BOOTSEL is visible. `picotool info` exits non-zero
  /// with "No accessible RP-series devices in BOOTSEL mode were found" until
  /// one enumerates.
  Future<bool> bootromPresent() async {
    try {
      final r = await _run(executable, const ['info']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// `picotool load -x <file>`: write the UF2 and run it. Returns null on
  /// success, or picotool's own explanation.
  Future<String?> loadAndRun(String uf2Path) async {
    try {
      final r = await _run(executable, ['load', '-x', uf2Path]);
      if (r.exitCode == 0) return null;
      final why = '${r.stderr}'.trim().isNotEmpty
          ? '${r.stderr}'.trim()
          : '${r.stdout}'.trim();
      return why.isEmpty ? 'picotool exited with ${r.exitCode}' : why;
    } on ProcessException catch (e) {
      return 'could not run picotool: ${e.message}';
    }
  }
}
